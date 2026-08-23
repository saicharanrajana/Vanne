/// User collection entry JSON payload.
library;

import 'json_fields.dart';

/// A user collection entry from `/collections[/{username}]`.
final class CollectionDto {
  final int id;
  final String label;
  final int views;

  /// Whether the collection is publicly visible (wire value may be 0/1).
  final bool public;
  final int count;

  const CollectionDto({
    required this.id,
    required this.label,
    required this.views,
    required this.public,
    required this.count,
  });

  factory CollectionDto.fromJson(Map<String, dynamic> json) => CollectionDto(
        id: parseIntField(json['id']) ?? 0,
        label: json['label'] as String? ?? '',
        views: parseIntField(json['views']) ?? 0,
        public: parseBoolField(json['public']) ?? false,
        count: parseIntField(json['count']) ?? 0,
      );
}
