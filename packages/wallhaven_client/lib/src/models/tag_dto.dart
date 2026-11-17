import 'json_fields.dart';

/// Tag JSON payload, embedded in wallpaper details and returned by
/// `/tag/{id}`.
///
/// Every field except [id]/[name] is nullable: Wallhaven has historically
/// served tags with incomplete metadata.
final class TagDto {
  final int id;
  final String name;
  final String? alias;
  final String? category;
  final int? categoryId;

  /// Wire purity string, e.g. `sfw`.
  final String? purity;
  final DateTime? createdAt;

  const TagDto({
    required this.id,
    required this.name,
    this.alias,
    this.category,
    this.categoryId,
    this.purity,
    this.createdAt,
  });

  factory TagDto.fromJson(Map<String, dynamic> json) => TagDto(
    id: parseIntField(json['id']) ?? 0,
    name: parseStringField(json['name']) ?? '',
    alias: parseStringField(json['alias']),
    category: parseStringField(json['category']),
    categoryId: parseIntField(json['category_id']),
    purity: parseStringField(json['purity']),
    createdAt: parseTimestamp(json['created_at']),
  );
}
