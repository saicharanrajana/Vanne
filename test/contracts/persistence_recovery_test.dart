// Contract: local writes must never leave the UI and the disk disagreeing.
//
// Everything the user does here is optimistic: the screen updates first, the
// write follows. These tests drive the two failure shapes that pattern can
// produce — a write that throws, and writes that overlap — and pin down exactly
// which state is restored.
//
// What is protected:
//  - a failed favorite rolls back only that wallpaper,
//  - a rollback restores the last snapshot that actually reached storage,
//    never an optimistic state the disk never saw,
//  - same-wallpaper taps reach storage in the order the user made them,
//  - a failed collection save reports an error and leaves no ghost entry,
//  - a failed multi-delete restores only the entries it removed,
//  - curated collections are seeded exactly once per install, so deleting
//    every collection survives a restart.
//
// Failure sequences covered for one wallpaper (disk `D`, screen `U`):
//  1. first write in flight, second tap lands, both writes fail  → U = D
//  2. first write succeeds, the following write fails            → U = D
//  3. removal fails while a newer tap re-adds it                 → U = D
//  4. storage rejects a re-add because the ID is already stored  → U = D
//  5. no newer tap at all, the write fails                       → U = D

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:vanne/core/collections/collection_entry.dart';
import 'package:vanne/core/collections/collections_repository.dart';
import 'package:vanne/core/collections/seed_collections.dart';
import 'package:vanne/core/storage/settings_store.dart';
import 'package:vanne/core/domain/favorite_wallpaper.dart';
import 'package:vanne/core/favorites/favorites_repository.dart';
import 'package:vanne/features/collections/application/collections_controller.dart';
import 'package:vanne/features/favorites/application/favorites_controller.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

/// Favorites store whose writes the test can hold open or fail on demand.
final class _ScriptedFavoritesRepository implements FavoritesRepository {
  _ScriptedFavoritesRepository([Iterable<FavoriteWallpaper> initial = const []]) {
    for (final favorite in initial) {
      _stored[favorite.id] = favorite;
    }
  }

  final _stored = <String, FavoriteWallpaper>{};

  /// Operations as they *start*, e.g. `add:aaa`.
  final started = <String>[];
  final _gates = <String, Completer<void>>{};
  final _failures = <String>{};

  Map<String, FavoriteWallpaper> get stored => Map.unmodifiable(_stored);

  /// Blocks the next `add:<id>` / `remove:<id>` until the returned gate opens.
  Completer<void> gate(String operation) =>
      _gates[operation] ??= Completer<void>();

  /// Makes the next [operation] throw, simulating a storage failure.
  void failNext(String operation) => _failures.add(operation);

  Future<void> _begin(String operation) async {
    started.add(operation);
    final gate = _gates.remove(operation);
    if (gate != null) await gate.future;
    if (_failures.remove(operation)) {
      throw StateError('storage failure: $operation');
    }
  }

  @override
  Future<List<FavoriteWallpaper>> getAll() async => _stored.values.toList();

  @override
  Future<bool> add(FavoriteWallpaper favorite) async {
    await _begin('add:${favorite.id}');
    // Mirrors the real store: an existing key is never overwritten.
    if (_stored.containsKey(favorite.id)) return false;
    _stored[favorite.id] = favorite;
    return true;
  }

  @override
  Future<bool> remove(String id) async {
    await _begin('remove:$id');
    return _stored.remove(id) != null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Collections store with the same gate/failure controls.
final class _ScriptedCollectionsRepository implements CollectionsRepository {
  _ScriptedCollectionsRepository([
    Iterable<CollectionEntry> initial = const [],
  ]) {
    for (final entry in initial) {
      _stored[entry.id] = entry;
    }
  }

  final _stored = <String, CollectionEntry>{};
  final started = <String>[];
  final _gates = <String, Completer<void>>{};
  final _failures = <String>{};
  var _rejectNextAdd = false;

  Map<String, CollectionEntry> get stored => Map.unmodifiable(_stored);

  Completer<void> gate(String operation) =>
      _gates[operation] ??= Completer<void>();

  void failNext(String operation) => _failures.add(operation);

  /// Simulates the repository's "nothing was written" answer.
  void rejectNextAdd() => _rejectNextAdd = true;

  Future<void> _begin(String operation) async {
    started.add(operation);
    final gate = _gates.remove(operation);
    if (gate != null) await gate.future;
    if (_failures.remove(operation)) {
      throw StateError('storage failure: $operation');
    }
  }

  @override
  Future<List<CollectionEntry>> getAll() async => _stored.values.toList();

  @override
  Future<bool> add(CollectionEntry entry) async {
    await _begin('add');
    if (_rejectNextAdd) {
      _rejectNextAdd = false;
      return false;
    }
    _stored[entry.id] = entry;
    return true;
  }

  @override
  Future<void> addAll(List<CollectionEntry> entries) async {
    await _begin('addAll');
    for (final entry in entries) {
      _stored[entry.id] = entry;
    }
  }

  @override
  Future<void> removeMany(Set<String> ids) async {
    await _begin('removeMany');
    for (final id in ids) {
      _stored.remove(id);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FavoriteWallpaper _favorite(String id) => FavoriteWallpaper(
  id: id,
  pageUrl: 'https://wallhaven.cc/w/$id',
  imageUrl: 'https://example.com/$id.jpg',
  thumbnailUrl: 'https://example.com/$id-thumb.jpg',
  width: 100,
  height: 200,
  resolution: '100x200',
  ratio: '0.5',
  fileSizeBytes: 1,
  fileType: 'image/jpeg',
  createdAt: DateTime(2025),
);

Wallpaper _wallpaper(String id) => Wallpaper(
  id: id,
  url: 'https://wallhaven.cc/w/$id',
  source: '',
  purity: Purity.sfw,
  category: Category.general,
  width: 100,
  height: 200,
  resolution: '100x200',
  ratio: '0.5',
  fileSizeBytes: 1,
  fileType: 'image/jpeg',
  createdAt: DateTime(2025),
  colors: const [],
  views: 0,
  favorites: 0,
  path: 'https://example.com/$id.jpg',
  thumbnails: Thumbnails(small: 'https://example.com/$id-thumb.jpg'),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('favorites', () {
    late _ScriptedFavoritesRepository repository;
    late FavoritesController controller;

    setUp(() {
      repository = _ScriptedFavoritesRepository([_favorite('aaa111')]);
      controller = FavoritesController(repository);
    });

    tearDown(() => controller.dispose());

    test('a failed favorite rolls back only that wallpaper', () async {
      await controller.restore();
      final gateA = repository.gate('add:bbb222');
      final gateB = repository.gate('add:ccc333');

      final failing = controller.toggle(_wallpaper('bbb222'));
      final succeeding = controller.toggle(_wallpaper('ccc333'));
      expect(
        controller.favoriteIds.value,
        {'aaa111', 'bbb222', 'ccc333'},
        reason: 'both taps are visible immediately',
      );

      repository.failNext('add:bbb222');
      gateA.complete();
      await pumpEventQueue();
      gateB.complete();
      await pumpEventQueue();

      expect(await failing, isFalse, reason: 'caller must show an error');
      expect(await succeeding, isTrue);
      expect(
        controller.favoriteIds.value,
        {'aaa111', 'ccc333'},
        reason: 'the unrelated successful favorite survives the rollback',
      );
      expect(repository.stored.keys, {'aaa111', 'ccc333'});
    });

    test('a write in flight is never overlapped; the next tap reconciles', () async {
      await controller.restore();
      final gate = repository.gate('add:bbb222');

      final adding = controller.toggle(_wallpaper('bbb222'));
      await pumpEventQueue();
      expect(
        repository.started,
        ['add:bbb222'],
        reason: 'the write started with the intent of the first tap',
      );

      final removing = controller.toggle(_wallpaper('bbb222'));
      expect(controller.favoriteIds.value, {'aaa111'});
      await pumpEventQueue();
      expect(
        repository.started,
        ['add:bbb222'],
        reason: 'one write per wallpaper at a time',
      );

      gate.complete();
      await pumpEventQueue();
      await pumpEventQueue();

      expect(
        repository.started,
        ['add:bbb222', 'remove:bbb222'],
        reason: 'the queued tap syncs storage after the first write',
      );
      expect(await adding, isTrue);
      expect(await removing, isTrue);
      expect(controller.favoriteIds.value, {'aaa111'});
      expect(
        repository.stored.keys,
        {'aaa111'},
        reason: 'screen and disk end in the same state',
      );
    });

    test('taps the user already reversed cost no wasted add', () async {
      await controller.restore();

      final adding = controller.toggle(_wallpaper('bbb222'));
      final removing = controller.toggle(_wallpaper('bbb222'));
      expect(
        controller.favoriteIds.value,
        {'aaa111'},
        reason: 'the latest tap wins on screen immediately',
      );

      await pumpEventQueue();
      expect(
        repository.started,
        isNot(contains('add:bbb222')),
        reason: 'the queued write sees the final intent, not a stale add',
      );
      expect(repository.started.first, 'remove:bbb222');
      expect(await adding, isTrue);
      expect(await removing, isTrue);
      expect(controller.favoriteIds.value, {'aaa111'});
      expect(repository.stored.keys, {'aaa111'});
    });

    test('a stale failure does not undo a newer tap', () async {
      await controller.restore();
      final gate = repository.gate('remove:aaa111');

      final removing = controller.toggle(_wallpaper('aaa111'));
      await pumpEventQueue();
      final reAdding = controller.toggle(_wallpaper('aaa111')); // newer intent

      repository.failNext('remove:aaa111');
      gate.complete();
      await pumpEventQueue();
      await pumpEventQueue();

      expect(await removing, isFalse, reason: 'the failing write reports itself');
      expect(
        controller.favoriteIds.value,
        {'aaa111'},
        reason: 'the failed write must not roll back the newer tap',
      );
      expect(await reAdding, isTrue);
      expect(repository.stored.keys, {'aaa111'});
    });

    test('every failed write returns the screen to what is stored', () async {
      await controller.restore();
      final gate = repository.gate('add:bbb222');

      // Tap 1 starts a write that is still in flight when tap 2 lands.
      final first = controller.toggle(_wallpaper('bbb222'));
      await pumpEventQueue();
      expect(repository.started, ['add:bbb222']);

      final second = controller.toggle(_wallpaper('bbb222'));
      expect(controller.favoriteIds.value, {'aaa111'});

      // Both fail: the first is superseded, the second is the final write.
      repository.failNext('add:bbb222');
      repository.failNext('remove:bbb222');
      gate.complete();
      await pumpEventQueue();
      await pumpEventQueue();

      expect(await first, isFalse);
      expect(await second, isFalse);
      expect(
        controller.favoriteIds.value,
        {'aaa111'},
        reason: 'rollback restores storage, not an optimistic state',
      );
      expect(repository.stored.keys, {'aaa111'});
    });

    test('a failed write after a successful one restores the stored snapshot', () async {
      await controller.restore();
      final adding = controller.toggle(_wallpaper('bbb222'));
      await adding; // committed
      expect(repository.stored.keys, {'aaa111', 'bbb222'});

      final gate = repository.gate('remove:bbb222');
      final removing = controller.toggle(_wallpaper('bbb222'));
      await pumpEventQueue();
      repository.failNext('remove:bbb222');
      gate.complete();
      await pumpEventQueue();
      await pumpEventQueue();

      expect(await removing, isFalse);
      expect(
        controller.favoriteIds.value,
        {'aaa111', 'bbb222'},
        reason: 'the snapshot that did reach storage is what comes back',
      );
      expect(repository.stored.keys, {'aaa111', 'bbb222'});
    });

    test('a removal that fails while a newer tap re-adds keeps them in sync', () async {
      await controller.restore();
      final gate = repository.gate('remove:aaa111');

      final removing = controller.toggle(_wallpaper('aaa111'));
      await pumpEventQueue();
      final reAdding = controller.toggle(_wallpaper('aaa111')); // newer intent

      repository.failNext('remove:aaa111'); // superseded failure
      gate.complete();
      await pumpEventQueue();
      await pumpEventQueue();

      expect(await removing, isFalse);
      expect(await reAdding, isTrue);
      expect(controller.favoriteIds.value, {'aaa111'});
      expect(repository.stored.keys, {'aaa111'});
    });

    test('a re-add that storage rejects still counts as stored', () async {
      await controller.restore();
      final gate = repository.gate('remove:aaa111');

      final removing = controller.toggle(_wallpaper('aaa111'));
      await pumpEventQueue();
      final reAdding = controller.toggle(_wallpaper('aaa111'));

      repository.failNext('remove:aaa111'); // disk keeps aaa111
      gate.complete();
      await pumpEventQueue();
      await pumpEventQueue();
      expect(await removing, isFalse);
      expect(
        await reAdding,
        isTrue,
        reason: 'the ID is already stored, so nothing was written',
      );

      // A later failing removal must still bring the stored favorite back.
      final lastGate = repository.gate('remove:aaa111');
      repository.failNext('remove:aaa111');
      final finalRemoval = controller.toggle(_wallpaper('aaa111'));
      expect(controller.favoriteIds.value, isEmpty);
      await pumpEventQueue();
      lastGate.complete();
      await pumpEventQueue();
      await pumpEventQueue();

      expect(await finalRemoval, isFalse);
      expect(
        controller.favoriteIds.value,
        {'aaa111'},
        reason: 'a rejected re-add must not erase the stored snapshot',
      );
      expect(repository.stored.keys, {'aaa111'});
    });

    test('a failed un-favorite restores exactly that favorite', () async {
      await controller.restore();
      final gate = repository.gate('remove:aaa111');
      repository.failNext('remove:aaa111');

      final removing = controller.toggle(_wallpaper('aaa111'));
      expect(controller.favoriteIds.value, isEmpty);
      gate.complete();
      await pumpEventQueue();

      expect(await removing, isFalse);
      expect(controller.favoriteIds.value, {'aaa111'});
      expect(repository.stored.keys, {'aaa111'});
    });
  });

  group('collections', () {
    test('a failed create reports an error, leaves no ghost, and allows retry', () async {
      final repository = _ScriptedCollectionsRepository();
      final controller = CollectionsController(repository);
      repository.failNext('add');

      final error = await controller.create(
        name: '  Space  ',
        query: ' space ',
      );
      expect(error, 'Failed to save');
      expect(controller.entries.value, isEmpty, reason: 'no ghost row');

      final retry = await controller.create(name: 'Space', query: ' space ');
      expect(retry, isNull);
      final saved = controller.entries.value.single;
      expect(saved.name, 'Space', reason: 'name is trimmed');
      expect(saved.query, 'space', reason: 'query is trimmed');
      expect(repository.stored.keys, {saved.id});
    });

    test('a rejected create is reported like a failure, exactly once', () async {
      final repository = _ScriptedCollectionsRepository();
      final controller = CollectionsController(repository);
      repository.rejectNextAdd();

      expect(
        await controller.create(name: 'Space', query: 'space'),
        'Failed to save',
      );
      expect(controller.entries.value, isEmpty);
      expect(
        await controller.create(name: 'Space', query: 'space'),
        isNull,
        reason: 'the next attempt succeeds and the name is free again',
      );
    });

    test('validation errors are returned, never thrown', () async {
      final controller = CollectionsController(_ScriptedCollectionsRepository());

      expect(await controller.create(name: '   ', query: 'x'), 'Name required');
      expect(
        await controller.create(name: 'x' * 31, query: 'x'),
        'Name too long (max 30)',
      );
      expect(await controller.create(name: 'Space', query: 'space'), isNull);
      expect(
        await controller.create(name: ' space ', query: 'space'),
        'Name already exists',
        reason: 'duplicate detection ignores case and padding',
      );
    });

    test('a failed multi-delete restores only the entries it removed', () async {
      final repository = _ScriptedCollectionsRepository([
        _entry('c_1', 'One'),
        _entry('c_2', 'Two'),
      ]);
      final controller = CollectionsController(repository);
      await controller.restore();
      final gate = repository.gate('removeMany');
      repository.failNext('removeMany');

      final deleting = controller.removeMany({'c_1'});
      expect(controller.ids.value, {'c_2'}, reason: 'deletion is optimistic');
      // A different collection created while the delete is in flight.
      expect(await controller.create(name: 'Three', query: 'three'), isNull);
      final createdId = controller.entries.value.last.id;

      gate.complete();
      expect(await deleting, isFalse);
      await pumpEventQueue();

      expect(
        controller.ids.value,
        {'c_1', 'c_2', createdId},
        reason: 'only the removed entry returns; the new one is kept',
      );
      expect(repository.stored.keys, containsAll(<String>['c_1', 'c_2']));
    });
  });

  group('curated seeding', () {
    late Directory hiveDir;

    setUp(() async {
      hiveDir = await Directory.systemTemp.createTemp('vanne-seeding');
      Hive.init(hiveDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (hiveDir.existsSync()) await hiveDir.delete(recursive: true);
    });

    test('seeds once, so deleting every collection survives a restart', () async {
      final settings = SettingsStore();
      await settings.open();
      final first = CollectionsRepository();
      await first.open();
      await seedCollectionsOnce(settings, first);
      expect(
        (await first.getAll()).map((entry) => entry.id).toSet(),
        seedCollections.map((entry) => entry.id).toSet(),
        reason: 'every curated collection is stored',
      );

      // The user deletes every curated collection, then the app restarts.
      await first.removeMany({for (final entry in seedCollections) entry.id});
      await Hive.close();

      final restartedSettings = SettingsStore();
      await restartedSettings.open();
      final restarted = CollectionsRepository();
      await restarted.open();
      await seedCollectionsOnce(restartedSettings, restarted);
      expect(
        await restarted.getAll(),
        isEmpty,
        reason: 'a deliberate empty list must not be re-seeded',
      );
    });

    test('never overwrites an install that already has collections', () async {
      final settings = SettingsStore();
      await settings.open();
      final repository = CollectionsRepository();
      await repository.open();
      await repository.add(_entry('custom', 'Custom'));

      await seedCollectionsOnce(settings, repository);

      expect(
        (await repository.getAll()).map((entry) => entry.id),
        ['custom'],
        reason: 'existing data is authoritative',
      );
    });
  });
}

CollectionEntry _entry(String id, String name) => CollectionEntry(
  id: id,
  name: name,
  query: name.toLowerCase(),
  createdAt: DateTime(2025, 1, 1),
);
