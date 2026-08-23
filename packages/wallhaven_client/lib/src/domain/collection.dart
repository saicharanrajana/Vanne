/// A user collection (own or another user's public ones).
library;

/// Public collection model.
final class WallpaperCollection {
  final int id;
  final String label;
  final int views;
  final bool public;
  final int count;

  const WallpaperCollection({
    required this.id,
    required this.label,
    required this.views,
    required this.public,
    required this.count,
  });
}
