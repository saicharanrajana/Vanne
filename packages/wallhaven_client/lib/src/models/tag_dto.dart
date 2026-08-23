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
        name: json['name'] as String? ?? '',
        alias: json['alias'] as String?,
        category: json['category'] as String?,
        categoryId: parseIntField(json['category_id']),
        purity: json['purity'] as String?,
        createdAt: parseTimestamp(json['created_at']),
      );
}
