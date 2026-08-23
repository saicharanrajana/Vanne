/// Thumbnail URLs as returned under `thumbs`.
library;

/// Thumbnail URLs for a wallpaper, as delivered by the API.
final class ThumbsDto {
  final String? large;
  final String? original;
  final String? small;

  const ThumbsDto({this.large, this.original, this.small});

  /// Tolerant parse: any missing/null key yields a null URL. Never
  /// reconstruct these URLs manually — always use what the API provides.
  factory ThumbsDto.fromJson(Map<String, dynamic> json) => ThumbsDto(
        large: json['large'] as String?,
        original: json['original'] as String?,
        small: json['small'] as String?,
      );
}
