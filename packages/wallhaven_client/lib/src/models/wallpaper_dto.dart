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

  factory WallpaperDto.fromJson(Map<String, dynamic> json) {
    final uploader = parseObjectField(json['uploader']);
    final thumbs = parseObjectField(json['thumbs']);
    return WallpaperDto(
      id: parseStringField(json['id']) ?? '',
      url: parseStringField(json['url']) ?? '',
      shortUrl: parseStringField(json['short_url']),
      uploader: uploader == null ? null : UploaderDto.fromJson(uploader),
      views: parseIntField(json['views']) ?? 0,
      favorites: parseIntField(json['favorites']) ?? 0,
      source: parseStringField(json['source']) ?? '',
      purity: parseStringField(json['purity']) ?? '',
      category: parseStringField(json['category']) ?? '',
      width: parseIntField(json['dimension_x']) ?? 0,
      height: parseIntField(json['dimension_y']) ?? 0,
      resolution: parseStringField(json['resolution']) ?? '',
      ratio: parseStringField(json['ratio']) ?? '',
      fileSize: parseIntField(json['file_size']) ?? 0,
      fileType: parseStringField(json['file_type']) ?? '',
      createdAt: parseTimestamp(json['created_at']),
      // Malformed entries are skipped instead of rejecting the response.
      colors: parseStringListField(json['colors']),
      path: parseStringField(json['path']) ?? '',
      thumbs: thumbs == null ? const ThumbsDto() : ThumbsDto.fromJson(thumbs),
      tags: [
        for (final tag in parseObjectListField(json['tags']))
          TagDto.fromJson(tag),
      ],
    );
  }
}
