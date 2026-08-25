import 'package:wallhaven_client/wallhaven_client.dart';

import 'collection_entry.dart';

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
