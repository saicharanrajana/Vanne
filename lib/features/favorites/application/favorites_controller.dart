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

  /// Favorite IDs — cheap reactive input for tile badges.
  Set<String> get ids => _favorites.value.keys.toSet();

  bool isFavorite(String id) => _favorites.value.containsKey(id);

  /// Toggles a wallpaper's favorite state and persists the change.
  ///
  /// The reactive state updates immediately; only the persistence write
  /// is awaited, so tiles never wait on I/O to reflect the toggle.
  Future<void> toggle(Wallpaper wallpaper) async {
    final current = _favorites.peek();
    if (current.containsKey(wallpaper.id)) {
      _favorites.set({
        for (final entry in current.entries)
          if (entry.key != wallpaper.id) entry.key: entry.value,
      });
      await _repository.remove(wallpaper.id);
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
      await _repository.add(snapshot);
    }
  }
}
