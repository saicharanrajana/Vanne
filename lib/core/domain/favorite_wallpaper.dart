import 'dart:convert';

import '../storage/persisted_json.dart';

/// Minimal locally-persisted snapshot of a favorited wallpaper.
///
/// Favorites must survive even if the wallpaper disappears from the
/// remote API, so every field the grid and detail screens need to render
/// gracefully is captured at favorite time. Stored as JSON in a Hive box.
final class FavoriteWallpaper {
  final String id;

  /// Page URL, e.g. `https://wallhaven.cc/w/<id>` (used by Open action).
  final String pageUrl;

  /// Full-resolution image URL, or empty when unknown.
  final String imageUrl;

  /// Best grid thumbnail URL.
  final String? thumbnailUrl;

  final int width;
  final int height;
  final String resolution;

  /// Preformatted ratio string, e.g. `0.56`.
  final String ratio;

  final int fileSizeBytes;
  final String fileType;
  final DateTime? createdAt;

  const FavoriteWallpaper({
    required this.id,
    required this.pageUrl,
    required this.imageUrl,
    required this.thumbnailUrl,
    required this.width,
    required this.height,
    required this.resolution,
    required this.ratio,
    required this.fileSizeBytes,
    required this.fileType,
    this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'pageUrl': pageUrl,
    'imageUrl': imageUrl,
    'thumbnailUrl': thumbnailUrl,
    'width': width,
    'height': height,
    'resolution': resolution,
    'ratio': ratio,
    'fileSizeBytes': fileSizeBytes,
    'fileType': fileType,
    'createdAt': createdAt?.toIso8601String(),
  };

  factory FavoriteWallpaper.fromJson(Map<String, dynamic> json) {
    // Every field here comes from local storage, so nothing is cast: a bad
    // value falls back to [toJson]'s own default instead of throwing away a
    // wallpaper the user actually saved. The id is the identity, and
    // [decode] rejects a row without one.
    final id = readString(json['id']) ?? '';
    return FavoriteWallpaper(
      id: id,
      // A lost page URL is reconstructed: the app writes exactly this form.
      pageUrl: readString(json['pageUrl']) ?? 'https://wallhaven.cc/w/$id',
      imageUrl: readString(json['imageUrl']) ?? '',
      thumbnailUrl: readString(json['thumbnailUrl']),
      width: readInt(json['width']),
      height: readInt(json['height']),
      resolution: readString(json['resolution']) ?? '',
      ratio: readString(json['ratio']) ?? '',
      fileSizeBytes: readInt(json['fileSizeBytes']),
      fileType: readString(json['fileType']) ?? '',
      createdAt: DateTime.tryParse(readString(json['createdAt']) ?? ''),
    );
  }

  String encode() => jsonEncode(toJson());

  /// Decodes a stored snapshot, or `null` when [raw] cannot describe one.
  ///
  /// A row is only unreadable when it has no identity: not JSON, not an
  /// object, or no non-empty `id`. Every other field is metadata and is read
  /// with a safe default, so one damaged field cannot delete a wallpaper the
  /// user saved. The [TypeError] catch is the outer guard for the same reason
  /// — an escaping error would reject the whole batch and block startup, since
  /// one bad row must never take the healthy ones down with it.
  static FavoriteWallpaper? decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final favorite = FavoriteWallpaper.fromJson(decoded);
      // The box key is the wallpaper id; an empty id cannot be rendered.
      return favorite.id.isEmpty ? null : favorite;
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }
}
