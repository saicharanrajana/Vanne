import '../../core/collections/collection_entry.dart';
import 'color_display.dart';

/// Presentation naming shared by saved-collection surfaces.
///
/// Color collections use the same human-readable color title as the
/// Collections page, while retaining the saved collection name as a fallback.
abstract final class CollectionDisplay {
  /// The exact saved hex represented by a color collection, if available.
  static String? colorHexFor(CollectionEntry entry) {
    if (entry.colors.isNotEmpty) return entry.colors.first;
    if (entry.name.trim().startsWith('#')) return entry.name.trim();
    return null;
  }

  /// Title shown on collection cards and collection-derived filter cards.
  static String titleFor(CollectionEntry entry) {
    final colorHex = colorHexFor(entry);
    if (colorHex == null) return entry.displayName;
    return ColorDisplay.nameForHex(colorHex) ?? entry.displayName;
  }
}
