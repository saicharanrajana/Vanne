import 'tag_dto.dart';
import 'thumbs_dto.dart';
import 'uploader_dto.dart';
import 'json_fields.dart';

/// Wallpaper object as delivered by `/w/{id}` and search listings.
///
/// Listings omit `uploader` and `tags`; only detail responses carry them.
final class WallpaperDto {
  final String id;
  final String url;
  final String? shortUrl;
  final UploaderDto? uploader;
  final int views;
  final int favorites;

  /// External source link, often empty.
  final String source;

  /// Wire purity string (`sfw`/`sketchy`/`nsfw`).
  final String purity;

  /// Wire category string (`general`/`anime`/`people`).
  final String category;
  final int width;
  final int height;

  /// Preformatted resolution string, e.g. `1920x1080`.
  final String resolution;

  /// Preformatted ratio string, e.g. `1.91`.
  final String ratio;
  final int fileSize;

  /// MIME type, e.g. `image/jpeg`.
  final String fileType;
  final DateTime? createdAt;

  /// Dominant colors as hex strings including `#`.
  final List<String> colors;

  /// Full-resolution image URL.
  final String path;
  final ThumbsDto thumbs;
  final List<TagDto> tags;

  const WallpaperDto({
    required this.id,
    required this.url,
    this.shortUrl,
    this.uploader,
    required this.views,
    required this.favorites,
    required this.source,
    required this.purity,
    required this.category,
    required this.width,
    required this.height,
    required this.resolution,
    required this.ratio,
    required this.fileSize,
    required this.fileType,
    this.createdAt,
    required this.colors,
    required this.path,
    required this.thumbs,
    required this.tags,
  });

  factory WallpaperDto.fromJson(Map<String, dynamic> json) => WallpaperDto(
        id: json['id'] as String? ?? '',
        url: json['url'] as String? ?? '',
        shortUrl: json['short_url'] as String?,
        uploader: json['uploader'] is Map<String, dynamic>
            ? UploaderDto.fromJson(json['uploader'] as Map<String, dynamic>)
            : null,
        views: parseIntField(json['views']) ?? 0,
        favorites: parseIntField(json['favorites']) ?? 0,
        source: json['source'] as String? ?? '',
        purity: json['purity'] as String? ?? '',
        category: json['category'] as String? ?? '',
        width: parseIntField(json['dimension_x']) ?? 0,
        height: parseIntField(json['dimension_y']) ?? 0,
        resolution: json['resolution'] as String? ?? '',
        ratio: json['ratio'] as String? ?? '',
        fileSize: parseIntField(json['file_size']) ?? 0,
        fileType: json['file_type'] as String? ?? '',
        createdAt: parseTimestamp(json['created_at']),
        colors: [
          // Skip malformed color entries instead of rejecting the response.
          for (final color in (json['colors'] as List<dynamic>? ?? <dynamic>[]))
            if (color is String) color,
        ],
        path: json['path'] as String? ?? '',
        thumbs: json['thumbs'] is Map<String, dynamic>
            ? ThumbsDto.fromJson(json['thumbs'] as Map<String, dynamic>)
            : const ThumbsDto(),
        tags: [
          for (final tag in (json['tags'] as List<dynamic>? ?? <dynamic>[]))
            if (tag is Map<String, dynamic>) TagDto.fromJson(tag),
        ],
      );
}
