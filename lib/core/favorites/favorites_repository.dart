import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../domain/favorite_wallpaper.dart';

/// Local favorites store backed by a Hive box (`favorites`).
///
/// Each entry is the JSON-encoded [FavoriteWallpaper] snapshot keyed by
/// wallpaper ID, so favorites render fully offline and survive remote
/// deletion. No Wallhaven authentication involved.
///
/// JSON encode/decode runs in a separate isolate via [compute]; decoding
/// is batched into a single call so restoring N favorites costs one
/// isolate round-trip, not N.
/// Not `final` so tests can provide fakes via `implements`.
class FavoritesRepository {
  static const _boxName = 'favorites';

  Box<String>? _box;

  Future<void> open() async {
    _box ??= await Hive.openBox<String>(_boxName);
  }

  /// All favorites, newest insertion last.
  Future<List<FavoriteWallpaper>> getAll() async {
    final box = _box;
    if (box == null) return const [];
    final raws = box.values.toList(growable: false);
    if (raws.isEmpty) return const [];
    // Batched: restoring N favorites costs one isolate round-trip, not N.
    return compute(_decodeFavorites, raws);
  }

  /// Adds [favorite]; returns `true` when the set actually changed.
  ///
  /// Encoding inline: one snapshot is a ~300-byte string — an isolate
  /// round-trip would cost more than it saves.
  Future<bool> add(FavoriteWallpaper favorite) async {
    final box = _box;
    if (box == null || box.containsKey(favorite.id)) return false;
    await box.put(favorite.id, favorite.encode());
    return true;
  }

  /// Removes [id]; returns `true` when the set actually changed.
  Future<bool> remove(String id) async {
    final box = _box;
    if (box == null || !box.containsKey(id)) return false;
    await box.delete(id);
    return true;
  }
}

/// Isolate entry point: decode every snapshot; corrupt entries are
/// skipped rather than failing the whole restore.
List<FavoriteWallpaper> _decodeFavorites(List<String> raws) =>
    [for (final raw in raws) ?FavoriteWallpaper.decode(raw)];
