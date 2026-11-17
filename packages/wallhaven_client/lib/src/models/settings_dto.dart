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
        thumbSize: parseStringField(json['thumb_size']),
        perPage: parseIntField(json['per_page']),
        purities: parseStringListField(json['purity']),
        categories: parseStringListField(json['categories']),
        resolutions: parseStringListField(json['resolutions']),
        aspectRatios: parseStringListField(json['aspect_ratios']),
        toplistRange: parseStringField(json['toplist_range']),
        tagBlacklist: parseStringListField(json['tag_blacklist']),
        userBlacklist: parseStringListField(json['user_blacklist']),
      );
}
