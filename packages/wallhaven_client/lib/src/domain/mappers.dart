/// DTO → domain mappers.
///
/// The single place where JSON-derived values become public models; after
/// these functions run, no DTO or `Map<String, dynamic>` survives.
library;

import '../models/collection_dto.dart';
import '../models/search_meta_dto.dart';
import '../models/settings_dto.dart';
import '../models/tag_dto.dart';
import '../models/thumbs_dto.dart';
import '../models/uploader_dto.dart';
import '../models/wallpaper_dto.dart';
import 'collection.dart';
import 'pagination.dart';
import 'purity.dart';
import 'settings.dart';
import 'tag.dart';
import 'wallpaper.dart';

/// Converts a [WallpaperDto] into the public [Wallpaper].
Wallpaper wallpaperFromDto(WallpaperDto dto) => Wallpaper(
      id: dto.id,
      url: dto.url,
      shortUrl: dto.shortUrl,
      source: dto.source,
      purity: purityFromWire(dto.purity),
      category: categoryFromWire(dto.category),
      width: dto.width,
      height: dto.height,
      resolution: dto.resolution,
      ratio: dto.ratio,
      fileSizeBytes: dto.fileSize,
      fileType: dto.fileType,
      createdAt: dto.createdAt,
      colors: List.unmodifiable(dto.colors),
      views: dto.views,
      favorites: dto.favorites,
      path: dto.path,
      thumbnails: thumbsFromDto(dto.thumbs),
      uploader: dto.uploader == null ? null : uploaderFromDto(dto.uploader!),
      tags: dto.tags.isEmpty
          ? null // listings carry no tags at all
          : List.unmodifiable(dto.tags.map(tagFromDto)),
    );

/// Converts an [UploaderDto] into the public [Uploader].
Uploader uploaderFromDto(UploaderDto dto) => Uploader(
      username: dto.username,
      group: dto.group,
      avatar: Map.unmodifiable(dto.avatar),
    );

/// Converts a [ThumbsDto] into the public [Thumbnails].
Thumbnails thumbsFromDto(ThumbsDto dto) => Thumbnails(
      large: dto.large,
      original: dto.original,
      small: dto.small,
    );

/// Converts a [TagDto] into the public [Tag].
Tag tagFromDto(TagDto dto) => Tag(
      id: dto.id,
      name: dto.name,
      alias: dto.alias,
      category: dto.category,
      categoryId: dto.categoryId,
      purity: dto.purity,
      createdAt: dto.createdAt,
    );

/// Decodes meta.query into typed domain values (plain string vs exact-tag
/// `{id, tag}` object).
SearchMeta searchMetaFromDto(SearchMetaDto dto) {
  final rawQuery = dto.query;
  String? query;
  ExactTagQuery? exactTagQuery;
  if (rawQuery is Map<String, dynamic>) {
    // Exact-tag searches echo `{id: <int>, tag: <String>}`.
    final id = int.tryParse('${rawQuery['id']}');
    final tag = rawQuery['tag'];
    if (id != null && tag is String) {
      exactTagQuery = ExactTagQuery(id: id, tag: tag);
    }
  } else if (rawQuery is String) {
    query = rawQuery;
  }
  return SearchMeta(
    currentPage: dto.currentPage,
    lastPage: dto.lastPage,
    perPage: dto.perPage,
    total: dto.total,
    query: query,
    exactTagQuery: exactTagQuery,
    seed: dto.seed,
  );
}

/// Converts a [CollectionDto] into the public [WallpaperCollection].
WallpaperCollection collectionFromDto(CollectionDto dto) => WallpaperCollection(
      id: dto.id,
      label: dto.label,
      views: dto.views,
      public: dto.public,
      count: dto.count,
    );

/// Converts a [UserSettingsDto] into the public [UserSettings]. Unknown
/// wire strings degrade to their conservative defaults rather than failing.
UserSettings userSettingsFromDto(UserSettingsDto dto) => UserSettings(
      thumbSize: dto.thumbSize,
      perPage: dto.perPage,
      purities: [
        for (final value in dto.purities) purityFromWire(value),
      ],
      categories: [
        for (final value in dto.categories) categoryFromWire(value),
      ],
      resolutions: List.unmodifiable(dto.resolutions),
      aspectRatios: List.unmodifiable(dto.aspectRatios),
      toplistRange: dto.toplistRange,
      tagBlacklist: List.unmodifiable(dto.tagBlacklist),
      userBlacklist: List.unmodifiable(dto.userBlacklist),
    );
