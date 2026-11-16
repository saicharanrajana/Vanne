import 'package:wallhaven_client/wallhaven_client.dart';

import '../storage/settings_store.dart';
import 'collection_entry.dart';
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

/// Ids of the curated first-install collections.
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

/// Curated seed collections for first install. Stable ids avoid churn.
///
/// Every seed is a tag collection so it can also appear under Search's
/// "By tag" row.
final seedCollections = <CollectionEntry>[
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
];

/// Seeds [seedCollections] exactly once per install.
///
/// An empty list is a legitimate user state (delete every collection), so
/// "empty" alone cannot mean "first launch". [SettingsStore.collectionsSeeded]
/// records that seeding already happened:
///
/// - marker present → nothing to do,
/// - marker absent + list empty → first launch, seed and mark,
/// - marker absent + existing entries → an install that predates the marker;
///   mark it without touching the user's data.
///
/// The only migration gap is an older install whose collections were all
/// deleted before this marker existed: it re-seeds once, because the old
/// scheme left no way to tell that state from a fresh install.
Future<void> seedCollectionsOnce(
  SettingsStore settings,
  CollectionsRepository repository,
) async {
  if (settings.collectionsSeeded) return;
  if ((await repository.getAll()).isEmpty) {
    await repository.addAll(seedCollections);
  }
  await settings.markCollectionsSeeded();
}
