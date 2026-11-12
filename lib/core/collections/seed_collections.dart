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

/// Known covers by seed id. Also lets installs created before cover metadata
/// existed show a bundled cover without being rewritten.
const seedCoverAssets = <String, String>{
  'seed-art': seedArtCover,
  'seed-nature': seedNatureCover,
  'seed-abstract': seedAbstractCover,
  'seed-minimal': seedMinimalCover,
};

/// Curated seed collections for first install. Stable ids avoid churn.
final seedCollections = <CollectionEntry>[
  CollectionEntry(
    id: 'seed-art',
    name: 'Art',
    query: 'art',
    kinds: const [],
    coverAsset: seedArtCover,
    createdAt: DateTime(2025, 1, 1),
  ),
  CollectionEntry(
    id: 'seed-nature',
    name: 'Nature',
    query: 'nature landscape',
    kinds: const [],
    coverAsset: seedNatureCover,
    createdAt: DateTime(2025, 1, 2),
  ),
  CollectionEntry(
    id: 'seed-abstract',
    name: 'Abstract',
    query: 'abstract',
    kinds: const [WallhavenCategory.general],
    coverAsset: seedAbstractCover,
    createdAt: DateTime(2025, 1, 3),
  ),
  CollectionEntry(
    id: 'seed-minimal',
    name: 'Minimal',
    query: 'minimalist',
    kinds: const [],
    coverAsset: seedMinimalCover,
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
