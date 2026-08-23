import 'package:signals/signals.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../core/domain/favorite_wallpaper.dart';
import '../../../core/favorites/favorites_repository.dart';

/// Reactive favorites state shared by grids, detail screens and the
/// Favorites tab. Toggling updates every visible instance instantly.
final class FavoritesController {
  final FavoritesRepository _repository;

  /// ID → snapshot map; widgets watch [ids] or [items].
  final _favorites = signal(const <String, FavoriteWallpaper>{});

  /// Reactive set of favorited IDs — the cheap signal grid tiles watch.
  late final favoriteIds = computed(() => _favorites.value.keys.toSet());

  FavoritesController(this._repository);

  /// Restores persisted favorites; call once during bootstrap.
  Future<void> restore() async {
    final favorites = await _repository.getAll();
    _favorites.set({for (final f in favorites) f.id: f});
  }

  /// Ordered list for the Favorites tab (newest favorite first).
  List<FavoriteWallpaper> get items =>
      _favorites.value.values.toList().reversed.toList();

  /// Grid-ready [Wallpaper] views of [items], recomputed only when the
  /// favorites map actually changes — not on every unrelated signal tick.
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
  /// Optimistic: the reactive state updates immediately, then the write is
  /// awaited. On persistence failure the previous state is restored and
  /// `false` returned so callers can surface an error instead of a false
  /// success.
  Future<bool> toggle(Wallpaper wallpaper) async {
    final current = _favorites.peek();
    final wasFavorite = current.containsKey(wallpaper.id);
    if (wasFavorite) {
      _favorites.set({
        for (final entry in current.entries)
          if (entry.key != wallpaper.id) entry.key: entry.value,
      });
    } else {
      final snapshot = FavoriteWallpaper(
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
      _favorites.set({...current, wallpaper.id: snapshot});
    }
    try {
      wasFavorite
          ? await _repository.remove(wallpaper.id)
          : await _repository.add(_favorites.value[wallpaper.id]!);
      return true;
    } catch (_) {
      _favorites.set(current); // roll back to the pre-toggle state
      return false;
    }
  }
}
