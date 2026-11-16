import 'package:flutter/foundation.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import 'collection_entry.dart';
import 'collection_order.dart';
import 'collections_repository.dart';

/// Bundled square covers for the curated first-install collections.
///
/// Assets are shipped with the app, so these cards render on the first launch
/// without a network request or a cache warm-up. The 400×400 crops are drawn
/// with BoxFit.cover, which fills the square card without distortion.
const seedArtCover = 'assets/collections/art.jpg';
const seedNatureCover = 'assets/collections/nature.jpg';
const seedAbstractCover = 'assets/collections/abstract.jpg';
const seedMinimalCover = 'assets/collections/minimal.jpg';

/// Ids of the curated collections shipped with the app.
///
/// These four are permanent: they are restored on every launch if missing and
/// can never be deleted from storage or the controller. They are ordinary
/// entries otherwise — reorderable, and matched like any other row.
///
/// Curated seeds were persisted before [CollectionOrigin] existed, so an
/// install that predates the field stores them without an origin. Those ids are
/// only ever produced by [seedCollections], whose queries are tags, so the
/// controller promotes them to [CollectionOrigin.tag] on load rather than
/// rewriting the user's stored rows.
const curatedSeedIds = <String>{
  'seed-art',
  'seed-nature',
  'seed-abstract',
  'seed-minimal',
};

/// Known covers by seed id. Also lets installs created before cover metadata
/// existed show a bundled cover without being rewritten.
const seedCoverAssets = <String, String>{
  'seed-art': seedArtCover,
  'seed-nature': seedNatureCover,
  'seed-abstract': seedAbstractCover,
  'seed-minimal': seedMinimalCover,
};

/// Palettes sampled from the bundled covers, most common colour first.
///
/// Measured, not guessed: each 400×400 JPEG was decoded and bucketed on the
/// top four bits per channel; the four fullest buckets are listed with their
/// mean RGB. Search's By tag row uses the first entry to tint the selection
/// stroke of that seed's card, so it has to describe the real artwork.
const seedCoverColors = <String, List<String>>{
  'seed-art': ['#192717', '#384628', '#B9B8A7', '#C8C5A9'],
  'seed-nature': ['#797968', '#595647', '#898667', '#272818'],
  'seed-abstract': ['#161616', '#E7E7E7', '#484848', '#C8C8C8'],
  'seed-minimal': ['#324353', '#989898', '#A8A8A6', '#A2B4C2'],
};

/// The cover palette used for presentation.
///
/// The collection's own saved palette wins; curated seeds fall back to the
/// sampled constants above so installs that predate the field still get a
/// stroke that matches their cover. An empty result is honest: the card has no
/// palette, and the caller shows its neutral fallback.
List<String> coverPaletteFor(CollectionEntry entry) {
  if (entry.coverColors.isNotEmpty) return entry.coverColors;
  return seedCoverColors[entry.id] ?? const [];
}

/// Whether [id] names a curated collection that must always exist.
bool isCuratedCollection(String id) => curatedSeedIds.contains(id);

/// Curated seed collections. Stable ids avoid churn.
///
/// Every seed is a tag collection so it can also appear under Search's
/// "By tag" row.
final List<CollectionEntry> seedCollections = List.unmodifiable(
  <CollectionEntry>[
    CollectionEntry(
      id: 'seed-art',
      name: 'Art',
      query: 'art',
      kinds: const [],
      coverAsset: seedArtCover,
      coverColors: seedCoverColors['seed-art']!,
      origin: CollectionOrigin.tag,
      createdAt: DateTime(2025, 1, 1),
    ),
    CollectionEntry(
      id: 'seed-nature',
      name: 'Nature',
      query: 'nature landscape',
      kinds: const [],
      coverAsset: seedNatureCover,
      coverColors: seedCoverColors['seed-nature']!,
      origin: CollectionOrigin.tag,
      createdAt: DateTime(2025, 1, 2),
    ),
    CollectionEntry(
      id: 'seed-abstract',
      name: 'Abstract',
      query: 'abstract',
      kinds: const [WallhavenCategory.general],
      coverAsset: seedAbstractCover,
      coverColors: seedCoverColors['seed-abstract']!,
      origin: CollectionOrigin.tag,
      createdAt: DateTime(2025, 1, 3),
    ),
    CollectionEntry(
      id: 'seed-minimal',
      name: 'Minimal',
      query: 'minimalist',
      kinds: const [],
      coverAsset: seedMinimalCover,
      coverColors: seedCoverColors['seed-minimal']!,
      origin: CollectionOrigin.tag,
      createdAt: DateTime(2025, 1, 4),
    ),
  ],
);

/// Makes the curated collections permanent and establishes the display order.
///
/// The curated collections are part of the app, not a first-run gift: they must
/// exist on a fresh install, survive an upgrade from an install that predates
/// them, and come back if an older build let them be deleted. An empty store is
/// therefore never a user state, and the previous one-shot seeding marker no
/// longer gates anything.
///
/// Idempotent by construction:
///
/// * existing rows are read first and never rewritten,
/// * only missing curated ids are inserted, in [seedCollections] order,
/// * the order is reconciled against the rows that actually exist, so a
///   partially applied previous run (or a crash between writes) is repaired on
///   the next launch without duplicating anything.
///
/// Restored collections are appended rather than reinserted where they once
/// were: old positions may have been taken by collections the user still has,
/// and moving those to make room would be a worse surprise than a curated card
/// appearing at the end.
///
/// Runs during startup before the controller publishes any state, so no screen
/// can observe a collections list that is missing a curated entry.
Future<void> reconcileCollections(CollectionsRepository repository) async {
  final existing = await repository.getAll();
  final present = {for (final entry in existing) entry.id};
  final missing = [
    for (final seed in seedCollections)
      if (!present.contains(seed.id)) seed,
  ];
  if (missing.isNotEmpty) {
    await repository.addAll(missing);
  }

  final stored = await repository.getStoredOrder();
  final order = stored == null
      ? CollectionOrder.resolve(stored: null, entries: existing) +
            [for (final seed in missing) seed.id]
      : CollectionOrder.resolve(
          stored: stored,
          entries: [...existing, ...missing],
        );
  // Only write when reconciliation actually changed something, so a healthy
  // launch stays read-only.
  if (!listEquals(order, stored)) {
    await repository.saveOrder(order);
  }
}
