import 'dart:async';

import 'package:signals/signals.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../core/domain/favorite_wallpaper.dart';
import '../../../core/favorites/favorites_repository.dart';

/// Reactive favorites state shared by grids, detail screens and the
/// Favorites tab. Toggling updates every visible instance instantly.
///
/// Writes are optimistic: the grid changes before any I/O, then storage is
/// reconciled to what the user currently sees. Two rules keep screen and
/// disk in agreement:
///
/// - **One write per wallpaper at a time.** Taps on the same wallpaper are
///   queued, so a fast tap-twice cannot land on disk with the taps reversed.
/// - **Each write reconciles, it does not replay.** When a queued write runs
///   it reads the *current* state, so two quick taps cost one write of the
///   final intent instead of a wasteful add followed by a remove.
///
/// A failed write rolls back only the wallpaper it was for, to the **last
/// snapshot that actually reached storage**, and only when no newer tap has
/// replaced that intent meanwhile — unrelated favorites are never touched.
/// Restoring a guess instead (the state at tap time) could leave the screen
/// showing a favorite the disk never received.
final class FavoritesController {
  final FavoritesRepository _repository;

  /// ID → snapshot map; widgets watch [ids] or [items].
  final _favorites = signal(const <String, FavoriteWallpaper>{});

  /// Reactive set of favorited IDs — the cheap signal grid tiles watch.
  late final favoriteIds = computed(() => _favorites.value.keys.toSet());

  /// Pending write chains, keyed by wallpaper ID. Entries disappear as soon
  /// as their chain drains, so this stays proportional to taps in flight.
  final _writes = <String, Future<void>>{};

  /// Latest tap per wallpaper. Lets a failed write detect that a newer tap
  /// has superseded it and skip a stale rollback. Entries are dropped when
  /// their write chain drains, so this never grows past toggles in flight.
  final _revisions = <String, int>{};

  /// Wallpapers known to be on disk, as of the last write that succeeded.
  /// Seeded by [restore] and advanced only on success, so a rollback always
  /// lands on a state storage has actually seen. Absent = not stored.
  final _committed = <String, FavoriteWallpaper>{};

  FavoritesController(this._repository);

  /// Restores persisted favorites; call once during bootstrap.
  Future<void> restore() async {
    final favorites = await _repository.getAll();
    _favorites.set({for (final f in favorites) f.id: f});
    _committed
      ..clear()
      ..addAll(_favorites.peek());
  }

  /// Grid-ready [Wallpaper] views of the favorites, newest first. Recomputes
  /// only when the favorites map changes — not on every unrelated signal tick.
  late final wallpapers = computed(
    () => [
      for (final f in _favorites.value.values.toList().reversed)
        _asWallpaper(f),
    ],
  );

  /// Adapts the persisted snapshot back into the domain model the grid
  /// consumes. Listing-only fields (views, colors) are not displayed by
  /// tiles and default harmlessly.
  static Wallpaper _asWallpaper(FavoriteWallpaper favorite) => Wallpaper(
    id: favorite.id,
    url: favorite.pageUrl,
    source: '',
    purity: Purity.sfw,
    category: Category.general,
    width: favorite.width,
    height: favorite.height,
    resolution: favorite.resolution,
    ratio: favorite.ratio,
    fileSizeBytes: favorite.fileSizeBytes,
    fileType: favorite.fileType,
    createdAt: favorite.createdAt,
    colors: const [],
    views: 0,
    favorites: 0,
    path: favorite.imageUrl,
    thumbnails: Thumbnails(small: favorite.thumbnailUrl),
  );

  /// Releases reactive resources (app-lifetime singleton; mainly for tests).
  void dispose() {
    favoriteIds.dispose();
    wallpapers.dispose();
  }

  /// Toggles a wallpaper's favorite state and persists the change.
  ///
  /// Updates the reactive state immediately, then writes. Returns `false`
  /// when the write failed and the change was rolled back, so callers can
  /// surface an error instead of a false success.
  Future<bool> toggle(Wallpaper wallpaper) {
    final id = wallpaper.id;
    final before = _favorites.peek()[id];
    final revision = (_revisions[id] ?? 0) + 1;
    _revisions[id] = revision;

    _setEntry(id, before == null ? _snapshotOf(wallpaper) : null);

    return _serialize(id, () => _sync(id, revision: revision));
  }

  /// Makes storage match the current state for [id].
  Future<bool> _sync(String id, {required int revision}) async {
    final desired = _favorites.peek()[id];
    try {
      if (desired == null) {
        await _repository.remove(id);
        _committed.remove(id);
      } else {
        final written = await _repository.add(desired);
        // `false` means the ID was already stored, so presence is unchanged.
        if (written) {
          _committed[id] = desired;
        } else {
          _committed.putIfAbsent(id, () => desired);
        }
      }
      return true;
    } catch (_) {
      // A newer tap owns this wallpaper now; its own write reports the
      // outcome, so a stale failure must not undo it.
      if (_revisions[id] == revision) _setEntry(id, _committed[id]);
      return false;
    }
  }

  void _setEntry(String id, FavoriteWallpaper? entry) {
    final next = <String, FavoriteWallpaper>{..._favorites.peek()};
    if (entry == null) {
      next.remove(id);
    } else {
      next[id] = entry;
    }
    _favorites.set(next);
  }

  /// Runs [write] after any write already queued for [id].
  Future<bool> _serialize(String id, Future<bool> Function() write) {
    final previous = _writes[id] ?? Future<void>.value();
    final result = previous.then((_) => write());
    late final Future<void> tail;
    // The tail swallows errors, so one failed write never blocks the next.
    tail = result.then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      if (!identical(_writes[id], tail)) return;
      // Nothing is in flight for this wallpaper any more, so neither the
      // chain slot nor its revision counter is needed.
      _writes.remove(id);
      _revisions.remove(id);
    });
    _writes[id] = tail;
    return result;
  }

  static FavoriteWallpaper _snapshotOf(Wallpaper wallpaper) => FavoriteWallpaper(
    id: wallpaper.id,
    pageUrl: wallpaper.url,
    imageUrl: wallpaper.path,
    thumbnailUrl: wallpaper.thumbnails.bestForGrid,
    width: wallpaper.width,
    height: wallpaper.height,
    resolution: wallpaper.resolution,
    ratio: wallpaper.ratio,
    fileSizeBytes: wallpaper.fileSizeBytes,
    fileType: wallpaper.fileType,
    createdAt: wallpaper.createdAt,
  );
}
