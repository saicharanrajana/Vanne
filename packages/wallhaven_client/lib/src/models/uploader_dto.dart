/// Uploader JSON payload.
library;

/// Uploader block; present in detail responses, absent from listings.
final class UploaderDto {
  final String username;

  /// User group, e.g. `User`, `Moderator`. Nullable on partial data.
  final String? group;

  /// Avatar URLs keyed by size (`200px`, `128px`, `32px`, `20px`).
  final Map<String, String> avatar;

  const UploaderDto({
    required this.username,
    this.group,
    this.avatar = const {},
  });

  /// Tolerant parse: avatar entries with non-string URLs are skipped
  /// rather than failing the whole response.
  factory UploaderDto.fromJson(Map<String, dynamic> json) {
    final rawAvatar = json['avatar'];
    final avatar = <String, String>{};
    if (rawAvatar is Map<String, dynamic>) {
      rawAvatar.forEach((key, value) {
        if (value is String) avatar[key] = value;
      });
    }
    return UploaderDto(
      username: json['username'] as String? ?? '',
      group: json['group'] as String?,
      avatar: Map.unmodifiable(avatar),
    );
  }
}
