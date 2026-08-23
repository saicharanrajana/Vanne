/// A tag attached to a wallpaper, or fetched from `/tag/{id}`.
library;

/// Public tag model.
final class Tag {
  final int id;
  final String name;

  /// Alternative name, when defined.
  final String? alias;
  final String? category;
  final int? categoryId;

  /// Wire purity string (`sfw`/`sketchy`/`nsfw`); null on partial data.
  final String? purity;
  final DateTime? createdAt;

  const Tag({
    required this.id,
    required this.name,
    this.alias,
    this.category,
    this.categoryId,
    this.purity,
    this.createdAt,
  });
}
