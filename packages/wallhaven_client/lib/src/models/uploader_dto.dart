/// Uploader JSON payload.
library;

import 'json_fields.dart';

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
    final rawAvatar = parseObjectField(json['avatar']);
    final avatar = <String, String>{};
    rawAvatar?.forEach((key, value) {
      final url = parseStringField(value);
      if (url != null) avatar[key] = url;
    });
    return UploaderDto(
      username: parseStringField(json['username']) ?? '',
      group: parseStringField(json['group']),
      avatar: Map.unmodifiable(avatar),
    );
  }
}
