/// Display enums for wallpaper purity and category.
///
/// Distinct from the wire enums in `../enums/` used for search parameters:
/// these classify results, those build queries.
library;

/// Content purity of a wallpaper.
enum Purity { sfw, sketchy, nsfw }

/// Resolves a wire purity string to [Purity]; unknown/null → `sfw`
/// (conservative default for display purposes).
Purity purityFromWire(String? value) => switch (value) {
      'sketchy' => Purity.sketchy,
      'nsfw' => Purity.nsfw,
      _ => Purity.sfw,
    };

/// Content category of a wallpaper.
enum Category { general, anime, people }

/// Resolves a wire category string to [Category]; unknown/null → `general`.
Category categoryFromWire(String? value) => switch (value) {
      'anime' => Category.anime,
      'people' => Category.people,
      _ => Category.general,
    };
