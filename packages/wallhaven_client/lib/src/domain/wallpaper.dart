/// A Wallhaven wallpaper and its embedded value types.
library;

import 'purity.dart';
import 'tag.dart';

/// A wallpaper's dominant color as a hex string (with `#`), as delivered
/// by the API. Display-only; not a search parameter.
typedef WallpaperColor = String;

/// Thumbnail URLs for a wallpaper.
///
/// The API provides these explicitly; clients must never reconstruct
/// Wallhaven image URLs themselves.
final class Thumbnails {
  /// Large thumbnail (~400px tall).
  final String? large;

  /// Original-aspect thumbnail.
  final String? original;

  /// Small thumbnail (~200px tall) — ideal for dense grids.
  final String? small;

  const Thumbnails({this.large, this.original, this.small});

  /// The best URL for a grid cell: small when available, falling back to
  /// progressively larger variants.
  String? get bestForGrid => small ?? large ?? original;
}

/// A wallpaper's uploader.
final class Uploader {
  final String username;

  /// User group, e.g. `User`, `Moderator`.
  final String? group;

  /// Avatar URLs keyed by size (`200px`, `128px`, `32px`, `20px`).
  final Map<String, String> avatar;

  const Uploader({
    required this.username,
    this.group,
    this.avatar = const {},
  });
}

/// A Wallhaven wallpaper.
///
/// Search listings populate every field except [uploader] and [tags]
/// (those are only included by the detail endpoint `/w/{id}`).
final class Wallpaper {
  final String id;

  /// Page URL, e.g. `https://wallhaven.cc/w/94x38z`.
  final String url;

  /// Short page URL, e.g. `http://whvn.cc/94x38z`.
  final String? shortUrl;

  /// External source link; empty when none was provided.
  final String source;
  final Purity purity;
  final Category category;
  final int width;
  final int height;

  /// Preformatted resolution, e.g. `1920x1080`.
  final String resolution;

  /// Preformatted aspect ratio, e.g. `1.91`.
  final String ratio;

  /// File size in bytes.
  final int fileSizeBytes;

  /// MIME type, e.g. `image/jpeg`.
  final String fileType;
  final DateTime? createdAt;
  final List<WallpaperColor> colors;
  final int views;
  final int favorites;

  /// Full-resolution image URL. May be empty for some entries; prefer
  /// thumbnails for display and treat [path] as nullable-in-practice.
  final String path;
  final Thumbnails thumbnails;

  /// Only present on detail responses (`/w/{id}`), null on listings.
  final Uploader? uploader;

  /// Only present on detail responses (`/w/{id}`), null on listings.
  final List<Tag>? tags;

  const Wallpaper({
    required this.id,
    required this.url,
    this.shortUrl,
    required this.source,
    required this.purity,
    required this.category,
    required this.width,
    required this.height,
    required this.resolution,
    required this.ratio,
    required this.fileSizeBytes,
    required this.fileType,
    this.createdAt,
    required this.colors,
    required this.views,
    required this.favorites,
    required this.path,
    required this.thumbnails,
    this.uploader,
    this.tags,
  });

  /// True when this object came from the detail endpoint and therefore
  /// carries uploader/tags.
  bool get hasDetails => uploader != null && tags != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Wallpaper &&
          other.id == id &&
          other.uploader?.username == uploader?.username &&
          other.fileSizeBytes == fileSizeBytes &&
          other.resolution == resolution &&
          other.ratio == ratio &&
          other.url == url &&
          other.path == path &&
          other.width == width &&
          other.height == height;

  @override
  int get hashCode => Object.hash(
    id,
    uploader?.username,
    fileSizeBytes,
    resolution,
    ratio,
    url,
    path,
    width,
    height,
  );
}
