import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../core/collections/collection_entry.dart';
import '../../../../core/collections/seed_collections.dart';
import '../../../../core/domain/feed_filter.dart';
import '../../../../shared/utils/color_display.dart';
import '../../../../shared/utils/collection_display.dart';
import '../../../../shared/utils/hex_color.dart';
import '../../../../shared/widgets/smart_network_image.dart';

/// Geometry shared by the two Search filter carousels.
abstract final class SearchFilterCarouselSpec {
  /// Leading gutter matching the search bar and section headings.
  static const double gutter = 20;

  /// The card surface the user sees: slightly wider than it is tall.
  static const double cardWidth = 120;
  static const double cardHeight = 104;

  /// Exterior gap between neighbouring cards.
  static const double gap = 6;

  /// One card plus the trailing gap; the stock carousel's item extent.
  static const double itemExtent = cardWidth + gap;

  static const double radius = 18;

  /// Selection stroke width. Painted inside the card, so selecting one never
  /// changes the card size or the gap to its neighbours.
  static const double selectionWidth = 4;

  /// `M3ECarousel` keeps its stock 8dp vertical container padding above and
  /// below the track, so the row is 16dp taller than a card.
  static const double height = cardHeight + 16;
}

/// Section heading above a Search filter carousel: plain, neutral text, one
/// step above body copy and well below a page title.
final class SearchFilterHeading extends StatelessWidget {
  final String text;

  const SearchFilterHeading(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: SearchFilterCarouselSpec.gutter,
      ),
      child: Text(
        text,
        style: theme.textTheme.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w500,
          letterSpacing: 0,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Dominant-color filter row: one card per Wallhaven search color.
///
/// Tapping a card toggles it; selection is single-select, so tapping another
/// card replaces it and tapping the selected card clears it.
///
/// Saved colour collections lead the row, ahead of the bundled swatches: they
/// are the colours the user chose, and each card applies the colour saved with
/// it. The [FeedColor] swatches follow in their fixed order.
final class SearchColorCarousel extends StatelessWidget {
  final Set<FeedColor> selected;
  final ValueChanged<FeedColor> onToggle;

  /// Saved colour collections to lead the row with.
  final List<CollectionEntry> entries;

  /// Id of the applied colour collection, or `null` for none.
  final String? selectedCollectionId;
  final ValueChanged<CollectionEntry> onToggleCollection;

  const SearchColorCarousel({
    super.key,
    required this.selected,
    required this.onToggle,
    this.entries = const [],
    this.selectedCollectionId,
    required this.onToggleCollection,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return _FilterCarousel(
      rowKey: 'search-color-carousel',
      cards: [
        // A saved colour whose hex cannot be parsed has no swatch to show, so
        // it is skipped rather than rendered as a misleading blank card.
        for (final entry in entries)
          if (_swatchFor(entry) case final Color swatch)
            _collectionCard(entry, swatch, brightness),
        for (final color in FeedColor.values) _colorCard(color, brightness),
      ],
    );
  }

  /// The colour a saved collection filters by, or `null` when it stores none
  /// this card can show.
  static Color? _swatchFor(CollectionEntry entry) {
    if (entry.colors.isEmpty) return null;
    return parseHexColor(entry.colors.first);
  }

  _FilterCardSpec _colorCard(FeedColor color, Brightness brightness) {
    final swatch = Color(color.colorValue);
    // The saved RGB stays the card's background; the label takes a
    // hue-related foreground that clears 4.5:1 against it. The selection
    // stroke is its own, gentler tone: a text-grade foreground would glare on
    // a dark card and paint a near-black band on a pale one.
    final label = ColorDisplay.onColorFor(swatch);
    final isSelected = selected.contains(color);
    return _FilterCardSpec(
      key: ValueKey('search-color-${color.name}'),
      label: color.label,
      semantics:
          'Filter by color ${color.label}${isSelected ? ', selected' : ''}',
      selected: isSelected,
      ringColor: ColorDisplay.selectionColorFor(swatch, brightness: brightness),
      // A tint of the label colour keeps a white or black card visible as a
      // card without a fixed outline that would vanish on one of them.
      hairlineColor: label.withValues(alpha: 0.28),
      labelColor: label,
      background: ColoredBox(color: swatch),
      onTap: () => onToggle(color),
    );
  }

  /// A saved colour collection, drawn as the colour card it stands for: the
  /// saved swatch is the background and the collection name is the label.
  _FilterCardSpec _collectionCard(
    CollectionEntry entry,
    Color swatch,
    Brightness brightness,
  ) {
    final label = ColorDisplay.onColorFor(swatch);
    final isSelected = entry.id == selectedCollectionId;
    final title = CollectionDisplay.titleFor(entry);
    return _FilterCardSpec(
      key: ValueKey('search-color-collection-${entry.id}'),
      label: title,
      semantics: 'Collection $title${isSelected ? ', selected' : ''}',
      selected: isSelected,
      ringColor: ColorDisplay.selectionColorFor(swatch, brightness: brightness),
      hairlineColor: label.withValues(alpha: 0.28),
      labelColor: label,
      background: ColoredBox(color: swatch),
      onTap: () => onToggleCollection(entry),
    );
  }
}

/// Saved tag-collection row.
///
/// Only collections that stand for a tag query are listed: a color-only
/// collection (or any other saved search without a query) has no tag to
/// combine with the typed query, so the caller filters those out. The caller
/// hides the whole section when the list is empty.
final class SearchTagCollectionCarousel extends StatelessWidget {
  final List<CollectionEntry> entries;
  final String? selectedId;
  final ValueChanged<CollectionEntry> onToggle;

  const SearchTagCollectionCarousel({
    super.key,
    required this.entries,
    required this.selectedId,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _FilterCarousel(
      rowKey: 'search-tag-carousel',
      cards: [for (final entry in entries) _tagCard(entry, scheme: scheme)],
    );
  }

  _FilterCardSpec _tagCard(
    CollectionEntry entry, {
    required ColorScheme scheme,
  }) {
    final coverAsset = entry.coverAsset ?? seedCoverAssets[entry.id];
    final coverUrl = entry.coverUrl;
    final hasCover = coverAsset != null || coverUrl != null;
    // The palette saved with the cover keeps the selection stroke related to
    // the artwork. A card with no palette (legacy, failed or still loading
    // cover) falls back to the neutral outline rather than pretending a
    // theme colour is part of the image.
    final palette = coverPaletteFor(entry);
    final swatch = palette.isEmpty ? null : parseHexColor(palette.first);
    final isSelected = entry.id == selectedId;
    return _FilterCardSpec(
      key: ValueKey('search-tag-${entry.id}'),
      label: entry.displayName,
      semantics:
          'Collection ${entry.displayName}${isSelected ? ', selected' : ''}',
      selected: isSelected,
      ringColor: swatch == null
          ? scheme.outline
          : ColorDisplay.selectionColorFor(
              swatch,
              brightness: scheme.brightness,
            ),
      labelColor: hasCover ? Colors.white : scheme.onSecondaryContainer,
      labelShadow: hasCover,
      // The base tint is the cover's own dominant colour, so a cover that is
      // still decoding or failed to load stays an intentional card instead of
      // the scrim over nothing.
      background: ColoredBox(
        color: swatch ?? scheme.secondaryContainer,
        child: hasCover
            ? _cover(entry, coverAsset: coverAsset, coverUrl: coverUrl)
            : null,
      ),
      onTap: () => onToggle(entry),
    );
  }

  Widget _cover(CollectionEntry entry, {String? coverAsset, String? coverUrl}) {
    final key = ValueKey('search-tag-cover-${entry.id}');
    final asset = coverAsset;
    if (asset != null) {
      return Image.asset(
        asset,
        key: key,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }
    return SmartNetworkImage(
      coverUrl!,
      key: key,
      fit: BoxFit.cover,
      memCacheWidth: 400,
    );
  }
}

/// One carousel card, described independently of the carousel shell.
final class _FilterCardSpec {
  final Key key;
  final String label;
  final String semantics;
  final bool selected;
  final Color ringColor;
  final Color? hairlineColor;
  final Color labelColor;
  final bool labelShadow;
  final Widget background;
  final VoidCallback onTap;

  const _FilterCardSpec({
    required this.key,
    required this.label,
    required this.semantics,
    required this.selected,
    required this.ringColor,
    this.hairlineColor,
    required this.labelColor,
    this.labelShadow = false,
    required this.background,
    required this.onTap,
  });
}

/// Both rows share the stock uncontained [M3ECarousel]: one card size, a
/// gentle shrink at the viewport edges, drag-to-snap and the widget's own
/// bottom-left label. Nothing here re-implements scrolling or text placement.
final class _FilterCarousel extends StatelessWidget {
  final String rowKey;
  final List<_FilterCardSpec> cards;

  const _FilterCarousel({required this.rowKey, required this.cards});

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
    );
    return Padding(
      key: ValueKey(rowKey),
      padding: const EdgeInsetsDirectional.only(
        start: SearchFilterCarouselSpec.gutter,
      ),
      child: M3ECarousel(
        height: SearchFilterCarouselSpec.height,
        type: M3ECarouselType.uncontained,
        freeScroll: true,
        uncontainedItemExtent: SearchFilterCarouselSpec.itemExtent,
        // Stops the edge cards shrinking below two thirds of a card: enough
        // to read as motion without squeezing the label.
        uncontainedShrinkExtent: 96,
        itemPadding: const EdgeInsetsDirectional.only(
          end: SearchFilterCarouselSpec.gap,
        ),
        childElementBorderRadius: SearchFilterCarouselSpec.radius,
        // The stock tap pulse would push the card's own edge outside the
        // clip; turning it off keeps the selection stroke on the card edge.
        fixedPulseDelta: 0,
        haptic: M3EHapticFeedback.light,
        // The carousel only fires its tap haptic when the row itself has a tap
        // handler; the per-card action lives on each item. Scrolling is left to
        // the widget, which does not buzz on a snap.
        onTap: (_) {},
        children: [
          for (final card in cards)
            M3ECarouselItem(
              image: _FilterCard(card: card),
              title: Text(
                card.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle?.copyWith(
                  color: card.labelColor,
                  shadows: card.labelShadow
                      ? const [Shadow(color: Color(0x66000000), blurRadius: 6)]
                      : null,
                ),
              ),
              // The stock dynamic transform hides a title on slots narrower
              // than 200dp; these cards are 120dp wide.
              applyDynamicTextContentTransform: false,
              semanticLabel: card.semantics,
              onTap: card.onTap,
            ),
        ],
      ),
    );
  }
}

/// The card's visual: background, optional image scrim and selection stroke.
///
/// The carousel's item extent is animated at the viewport edges, and this
/// widget is laid out inside that extent, so the whole card — cover, scrim and
/// stroke — travels and shrinks as one surface.
final class _FilterCard extends StatelessWidget {
  final _FilterCardSpec card;

  const _FilterCard({required this.card});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(SearchFilterCarouselSpec.radius);
    final hairline = card.hairlineColor;
    return Stack(
      key: card.key,
      fit: StackFit.expand,
      children: [
        card.background,
        if (card.labelShadow)
          // A light wash and a broad central shade keep a bright cover from
          // swallowing the label without a hard band.
          const IgnorePointer(child: ColoredBox(color: Color(0x2E000000))),
        if (card.labelShadow)
          const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.95,
                  colors: [Color(0x99000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
        if (card.selected)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: card.ringColor,
                  width: SearchFilterCarouselSpec.selectionWidth,
                ),
              ),
            ),
          )
        else if (hairline != null)
          IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: hairline, width: 1),
              ),
            ),
          ),
      ],
    );
  }
}
