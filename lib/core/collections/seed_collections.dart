import 'package:wallhaven_client/wallhaven_client.dart';

import '../storage/settings_store.dart';
import 'collection_entry.dart';
import 'collections_repository.dart';

/// Curated seed collections for first install. Stable ids avoid churn.
final seedCollections = <CollectionEntry>[
  CollectionEntry(
    id: 'seed-anime',
    name: 'Anime',
    query: 'anime',
    kinds: const [WallhavenCategory.anime],
    createdAt: DateTime(2025, 1, 1),
  ),
  CollectionEntry(
    id: 'seed-nature',
    name: 'Nature',
    query: 'nature landscape',
    kinds: const [],
    createdAt: DateTime(2025, 1, 2),
  ),
  CollectionEntry(
    id: 'seed-abstract',
    name: 'Abstract',
    query: 'abstract',
    kinds: const [WallhavenCategory.general],
    createdAt: DateTime(2025, 1, 3),
  ),
  CollectionEntry(
    id: 'seed-minimal',
    name: 'Minimal',
    query: 'minimalist',
    kinds: const [],
    createdAt: DateTime(2025, 1, 4),
  ),
  CollectionEntry(
    id: 'seed-architecture',
    name: 'Architecture',
    query: 'architecture building',
    kinds: const [],
    createdAt: DateTime(2025, 1, 5),
  ),
  CollectionEntry(
    id: 'seed-art',
    name: 'Art',
    query: 'art',
    kinds: const [],
    createdAt: DateTime(2025, 1, 6),
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
