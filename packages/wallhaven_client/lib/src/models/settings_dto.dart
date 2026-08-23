/// Authenticated user settings JSON payload (`/settings`).
library;

import 'json_fields.dart';

/// All fields are nullable/tolerant: settings must never break the app even
/// when Wallhaven returns partial metadata.
final class UserSettingsDto {
  final String? thumbSize;
  final int? perPage;
  final List<String> purities;
  final List<String> categories;
  final List<String> resolutions;
  final List<String> aspectRatios;
  final String? toplistRange;
  final List<String> tagBlacklist;
  final List<String> userBlacklist;

  const UserSettingsDto({
    this.thumbSize,
    this.perPage,
    this.purities = const [],
    this.categories = const [],
    this.resolutions = const [],
    this.aspectRatios = const [],
    this.toplistRange,
    this.tagBlacklist = const [],
    this.userBlacklist = const [],
  });

  factory UserSettingsDto.fromJson(Map<String, dynamic> json) =>
      UserSettingsDto(
        thumbSize: json['thumb_size'] as String?,
        perPage: parseIntField(json['per_page']),
        purities: _stringList(json['purity']),
        categories: _stringList(json['categories']),
        resolutions: _stringList(json['resolutions']),
        aspectRatios: _stringList(json['aspect_ratios']),
        toplistRange: json['toplist_range'] as String?,
        tagBlacklist: _stringList(json['tag_blacklist']),
        userBlacklist: _stringList(json['user_blacklist']),
      );

  static List<String> _stringList(Object? value) => [
        if (value is List<dynamic>)
          for (final item in value)
            if (item is String) item,
      ];
}
