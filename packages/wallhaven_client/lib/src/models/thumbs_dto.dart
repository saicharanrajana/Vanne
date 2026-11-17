/// Thumbnail URLs as returned under `thumbs`.
library;

import 'json_fields.dart';

/// Thumbnail URLs for a wallpaper, as delivered by the API.
final class ThumbsDto {
  final String? large;
  final String? original;
  final String? small;

  const ThumbsDto({this.large, this.original, this.small});

  /// Tolerant parse: any missing/null/non-string key yields a null URL. Never
  /// reconstruct these URLs manually — always use what the API provides.
  factory ThumbsDto.fromJson(Map<String, dynamic> json) => ThumbsDto(
    large: parseStringField(json['large']),
    original: parseStringField(json['original']),
    small: parseStringField(json['small']),
  );
}
