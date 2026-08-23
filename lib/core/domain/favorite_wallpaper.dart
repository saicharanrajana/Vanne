import 'dart:convert';

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

  factory FavoriteWallpaper.fromJson(Map<String, dynamic> json) =>
      FavoriteWallpaper(
        id: json['id'] as String,
        pageUrl: json['pageUrl'] as String,
        imageUrl: json['imageUrl'] as String? ?? '',
        thumbnailUrl: json['thumbnailUrl'] as String?,
        width: json['width'] as int? ?? 0,
        height: json['height'] as int? ?? 0,
        resolution: json['resolution'] as String? ?? '',
        ratio: json['ratio'] as String? ?? '',
        fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
        fileType: json['fileType'] as String? ?? '',
        createdAt: json['createdAt'] == null
            ? null
            : DateTime.tryParse(json['createdAt'] as String),
      );

  String encode() => jsonEncode(toJson());

  static FavoriteWallpaper? decode(String raw) {
    try {
      return FavoriteWallpaper.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on FormatException {
      return null;
    }
  }
}
