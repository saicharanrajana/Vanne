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
//  - a failed single removal restores only that collection,
//  - a move that cannot be persisted restores the previous order,
//  - curated collections are permanent: reconciliation restores them on every
//    launch and the controller refuses to delete them.
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
import 'package:vanne/core/domain/favorite_wallpaper.dart';
import 'package:vanne/core/favorites/favorites_repository.dart';
import 'package:vanne/features/collections/application/collections_controller.dart';
import 'package:vanne/features/favorites/application/favorites_controller.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

/// Favorites store whose writes the test can hold open or fail on demand.
final class _ScriptedFavoritesRepository implements FavoritesRepository {
  _ScriptedFavoritesRepository([
    Iterable<FavoriteWallpaper> initial = const [],
  ]) {
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
  final _order = <String>[];
  final started = <String>[];
  final _gates = <String, List<Completer<void>>>{};
  final _failures = <String>{};
  var _rejectNextAdd = false;
  var _orderFailures = 0;

  Map<String, CollectionEntry> get stored => Map.unmodifiable(_stored);

  /// The order the last successful [saveOrder] persisted.
  List<String> get storedOrder => List<String>.unmodifiable(_order);

  Completer<void> gate(String operation) {
    final gate = Completer<void>();
    _gates.putIfAbsent(operation, () => []).add(gate);
    return gate;
  }

  void failNext(String operation) => _failures.add(operation);

  /// Simulates the repository's "nothing was written" answer.
  void rejectNextAdd() => _rejectNextAdd = true;

  /// Simulates stores that accept the write but cannot keep it.
  void rejectNextOrder() => _orderFailures++;

  void rejectNextOrders(int count) => _orderFailures += count;

  Future<void> _begin(String operation) async {
    started.add(operation);
    final gates = _gates[operation];
    final gate = gates == null || gates.isEmpty ? null : gates.removeAt(0);
    if (gates != null && gates.isEmpty) _gates.remove(operation);
    if (gate != null) await gate.future;
    if (_failures.remove(operation)) {
      throw StateError('storage failure: $operation');
    }
  }

  @override
  Future<List<CollectionEntry>> getAll() async => _stored.values.toList();

  @override
  Future<List<String>?> getStoredOrder() async {
    await _begin('getStoredOrder');
    return _order.isEmpty ? null : List<String>.from(_order);
  }

  @override
  Future<bool> saveOrder(List<String> ids) async {
    await _begin('saveOrder');
    if (_orderFailures > 0) {
      _orderFailures--;
      return false;
    }
    _order
      ..clear()
      ..addAll(ids);
    return true;
  }

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
  Future<void> remove(String id) async {
    await _begin('remove:$id');
    _stored.remove(id);
  }

  @override
  Future<bool> update(CollectionEntry entry) async {
    await _begin('update:${entry.id}');
    if (!_stored.containsKey(entry.id)) return false;
    _stored[entry.id] = entry;
    return true;
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
      expect(controller.favoriteIds.value, {
        'aaa111',
        'bbb222',
        'ccc333',
      }, reason: 'both taps are visible immediately');

      repository.failNext('add:bbb222');
      gateA.complete();
      await pumpEventQueue();
      gateB.complete();
      await pumpEventQueue();

      expect(await failing, isFalse, reason: 'caller must show an error');
      expect(await succeeding, isTrue);
      expect(controller.favoriteIds.value, {
        'aaa111',
        'ccc333',
      }, reason: 'the unrelated successful favorite survives the rollback');
      expect(repository.stored.keys, {'aaa111', 'ccc333'});
    });

    test(
      'a write in flight is never overlapped; the next tap reconciles',
      () async {
        await controller.restore();
        final gate = repository.gate('add:bbb222');

        final adding = controller.toggle(_wallpaper('bbb222'));
        await pumpEventQueue();
        expect(repository.started, [
          'add:bbb222',
        ], reason: 'the write started with the intent of the first tap');

        final removing = controller.toggle(_wallpaper('bbb222'));
        expect(controller.favoriteIds.value, {'aaa111'});
        await pumpEventQueue();
        expect(repository.started, [
          'add:bbb222',
        ], reason: 'one write per wallpaper at a time');

        gate.complete();
        await pumpEventQueue();
        await pumpEventQueue();

        expect(repository.started, [
          'add:bbb222',
          'remove:bbb222',
        ], reason: 'the queued tap syncs storage after the first write');
        expect(await adding, isTrue);
        expect(await removing, isTrue);
        expect(controller.favoriteIds.value, {'aaa111'});
        expect(repository.stored.keys, {
          'aaa111',
        }, reason: 'screen and disk end in the same state');
      },
    );

    test('taps the user already reversed cost no wasted add', () async {
      await controller.restore();

      final adding = controller.toggle(_wallpaper('bbb222'));
      final removing = controller.toggle(_wallpaper('bbb222'));
      expect(controller.favoriteIds.value, {
        'aaa111',
      }, reason: 'the latest tap wins on screen immediately');

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

      expect(
        await removing,
        isFalse,
        reason: 'the failing write reports itself',
      );
      expect(controller.favoriteIds.value, {
        'aaa111',
      }, reason: 'the failed write must not roll back the newer tap');
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
      expect(controller.favoriteIds.value, {
        'aaa111',
      }, reason: 'rollback restores storage, not an optimistic state');
      expect(repository.stored.keys, {'aaa111'});
    });

    test(
      'a failed write after a successful one restores the stored snapshot',
      () async {
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
        expect(controller.favoriteIds.value, {
          'aaa111',
          'bbb222',
        }, reason: 'the snapshot that did reach storage is what comes back');
        expect(repository.stored.keys, {'aaa111', 'bbb222'});
      },
    );

    test(
      'a removal that fails while a newer tap re-adds keeps them in sync',
      () async {
        await controller.restore();
        final gate = repository.gate('remove:aaa111');

        final removing = controller.toggle(_wallpaper('aaa111'));
        await pumpEventQueue();
        final reAdding = controller.toggle(
          _wallpaper('aaa111'),
        ); // newer intent

        repository.failNext('remove:aaa111'); // superseded failure
        gate.complete();
        await pumpEventQueue();
        await pumpEventQueue();

        expect(await removing, isFalse);
        expect(await reAdding, isTrue);
        expect(controller.favoriteIds.value, {'aaa111'});
        expect(repository.stored.keys, {'aaa111'});
      },
    );

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
      expect(controller.favoriteIds.value, {
        'aaa111',
      }, reason: 'a rejected re-add must not erase the stored snapshot');
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
    test(
      'a failed create reports an error, leaves no ghost, and allows retry',
      () async {
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
      },
    );

    test(
      'a rejected create is reported like a failure, exactly once',
      () async {
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
      },
    );

    test('validation errors are returned, never thrown', () async {
      final controller = CollectionsController(
        _ScriptedCollectionsRepository(),
      );

      expect(await controller.create(name: '   ', query: 'x'), 'Name required');
      // Collections are created by bookmarking tag grids, whose names are
      // not length-limited; the card ellipsizes long titles.
      expect(await controller.create(name: 'x' * 31, query: 'x'), isNull);
      expect(await controller.create(name: 'Space', query: 'space'), isNull);
      expect(
        await controller.create(name: ' space ', query: 'space'),
        'Name already exists',
        reason: 'duplicate detection ignores case and padding',
      );
    });

    test('a failed single removal restores only that collection', () async {
      final repository = _ScriptedCollectionsRepository([
        _entry('c_1', 'One'),
        _entry('c_2', 'Two'),
      ]);
      final controller = CollectionsController(repository);
      await controller.restore();
      final gate = repository.gate('remove:c_1');
      repository.failNext('remove:c_1');

      final deleting = controller.remove('c_1');
      expect(controller.ids.value, {'c_2'}, reason: 'deletion is optimistic');
      // A different collection created while the delete is in flight.
      expect(await controller.create(name: 'Three', query: 'three'), isNull);
      final createdId = controller.entries.value.last.id;

      gate.complete();
      expect(await deleting, isFalse);
      await pumpEventQueue();

      expect(controller.ids.value, {
        'c_1',
        'c_2',
        createdId,
      }, reason: 'only the removed entry returns; the new one is kept');
      expect(controller.entries.value.map((entry) => entry.id), [
        'c_1',
        'c_2',
        createdId,
      ], reason: 'the restored row goes back where it was, new rows stay last');
      expect(repository.stored.keys, containsAll(<String>['c_1', 'c_2']));
    });

    test('curated collections cannot be removed, even by id', () async {
      final curated = seedCollections.first;
      final repository = _ScriptedCollectionsRepository();
      final controller = CollectionsController(repository);
      await controller.restore();

      expect(await controller.remove(curated.id), isFalse);
      expect(
        repository.started,
        isNot(contains('remove:${curated.id}')),
        reason: 'the store is never asked to delete a bundled collection',
      );
      expect(controller.isCuratedDefault(curated.id), isTrue);
      expect(controller.canRemove(curated.id), isFalse);
    });

    test(
      'a move that cannot be persisted restores the previous order',
      () async {
        final repository = _ScriptedCollectionsRepository([
          _entry('c_1', 'One'),
          _entry('c_2', 'Two'),
        ]);
        final controller = CollectionsController(repository);
        await controller.restore();

        repository.rejectNextOrder();
        final moved = controller.moveToStart('c_2');
        expect(
          controller.entries.value.first.id,
          'c_2',
          reason: 'the move is optimistic',
        );

        expect(await moved, isFalse);
        expect(controller.entries.value.map((entry) => entry.id), [
          'c_1',
          'c_2',
        ], reason: 'the visible order returns to what is stored');
      },
    );

    test(
      'overlapping failed reorders roll back to the last persisted order',
      () async {
        final repository = _ScriptedCollectionsRepository([
          _entry('a', 'A'),
          _entry('b', 'B'),
          _entry('c', 'C'),
        ]);
        final controller = CollectionsController(repository);
        await controller.restore();

        final firstGate = repository.gate('saveOrder');
        repository.rejectNextOrders(2);
        final first = controller.moveToStart('b');
        await pumpEventQueue();
        final second = controller.moveToStart('c');
        expect(controller.entries.value.map((entry) => entry.id), [
          'c',
          'b',
          'a',
        ]);

        await second;
        firstGate.complete();
        expect(await first, isFalse);
        expect(await second, isFalse);
        expect(controller.entries.value.map((entry) => entry.id), [
          'a',
          'b',
          'c',
        ]);
        expect(repository.storedOrder, ['a', 'b', 'c']);
      },
    );

    test(
      'a failed earlier reorder does not undo a later successful reorder',
      () async {
        final repository = _ScriptedCollectionsRepository([
          _entry('a', 'A'),
          _entry('b', 'B'),
          _entry('c', 'C'),
        ]);
        final controller = CollectionsController(repository);
        await controller.restore();

        final firstGate = repository.gate('saveOrder');
        final secondGate = repository.gate('saveOrder');
        repository.rejectNextOrder();
        final first = controller.moveToStart('b');
        await pumpEventQueue();
        final second = controller.moveToStart('c');

        firstGate.complete();
        expect(await first, isFalse);
        secondGate.complete();
        expect(await second, isTrue);
        expect(controller.entries.value.map((entry) => entry.id), [
          'c',
          'b',
          'a',
        ]);
        expect(repository.storedOrder, ['c', 'b', 'a']);
      },
    );

    test(
      'failed removal repairs persisted order after a concurrent reorder',
      () async {
        final repository = _ScriptedCollectionsRepository([
          _entry('a', 'A'),
          _entry('b', 'B'),
          _entry('c', 'C'),
        ]);
        final controller = CollectionsController(repository);
        await controller.restore();

        final removeGate = repository.gate('remove:b');
        repository.failNext('remove:b');
        final removing = controller.remove('b');
        await pumpEventQueue();
        expect(await controller.reorder(['c', 'a']), isTrue);
        removeGate.complete();
        expect(await removing, isFalse);
        await pumpEventQueue();

        expect(controller.entries.value.map((entry) => entry.id), [
          'c',
          'b',
          'a',
        ]);
        expect(repository.storedOrder, ['c', 'b', 'a']);
        final restarted = CollectionsController(repository);
        await restarted.restore();
        expect(restarted.entries.value.map((entry) => entry.id), [
          'c',
          'b',
          'a',
        ]);
      },
    );

    test('a new collection appends after the user\u2019s order', () async {
      final repository = _ScriptedCollectionsRepository();
      final controller = CollectionsController(repository);
      await controller.restore();

      expect(await controller.create(name: 'One', query: 'one'), isNull);
      expect(await controller.create(name: 'Two', query: 'two'), isNull);
      final one = controller.entries.value.first.id;
      expect(await controller.moveToEnd(one), isTrue);
      expect(await controller.create(name: 'Three', query: 'three'), isNull);

      expect(controller.entries.value.map((entry) => entry.name), [
        'Two',
        'One',
        'Three',
      ], reason: 'a new save goes to the end, not next to its creation order');
    });
  });

  group('curated reconciliation', () {
    late Directory hiveDir;

    setUp(() async {
      hiveDir = await Directory.systemTemp.createTemp('vanne-seeding');
      Hive.init(hiveDir.path);
    });

    tearDown(() async {
      await Hive.close();
      if (hiveDir.existsSync()) await hiveDir.delete(recursive: true);
    });

    test(
      'restores curated collections an older build let the user delete',
      () async {
        final first = CollectionsRepository();
        await first.open();
        await reconcileCollections(first);
        expect(
          (await first.getAll()).map((entry) => entry.id).toSet(),
          seedCollections.map((entry) => entry.id).toSet(),
          reason: 'every curated collection is stored',
        );

        // An older build allowed deleting them; the rows are gone from storage.
        final box = await Hive.openBox<String>('collections');
        await box.delete(seedCollections.first.id);
        await box.delete(seedCollections.last.id);
        await Hive.close();

        final restarted = CollectionsRepository();
        await restarted.open();
        await reconcileCollections(restarted);
        final restored = (await restarted.getAll())
            .map((entry) => entry.id)
            .toSet();
        expect(
          restored,
          seedCollections.map((entry) => entry.id).toSet(),
          reason: 'the bundled collections are part of the app, not a gift',
        );
      },
    );

    test(
      'repairing curated collections keeps the user\u2019s rows and order',
      () async {
        final repository = CollectionsRepository();
        await repository.open();
        await repository.add(_entry('custom', 'Custom'));
        await repository.saveOrder(['custom']);
        await reconcileCollections(repository);

        final ids = (await repository.getAll())
            .map((entry) => entry.id)
            .toSet();
        expect(
          await repository.getStoredOrder(),
          ['custom', ...seedCollections.map((entry) => entry.id)],
          reason: 'a restored collection appends behind what the user arranged',
        );
        expect(ids, {'custom', ...seedCollections.map((entry) => entry.id)});
        expect(
          (await repository.getAll())
              .firstWhere((entry) => entry.id == 'custom')
              .query,
          'custom',
          reason: 'existing rows are never rewritten by reconciliation',
        );
      },
    );

    test(
      'legacy orderless upgrade appends restored defaults after existing users',
      () async {
        final repository = CollectionsRepository();
        await repository.open();
        await repository.add(
          _entry('user-old', 'Old user', createdAt: DateTime(2025, 6, 1)),
        );
        await repository.add(
          _entry('user-new', 'New user', createdAt: DateTime(2026, 1, 1)),
        );

        // Simulate a pre-order install with a missing curated default.
        final collectionsBox = await Hive.openBox<String>('collections');
        await collectionsBox.delete('seed-nature');
        final orderBox = await Hive.openBox<dynamic>('collection_order');
        await orderBox.delete('ids');

        await reconcileCollections(repository);

        expect(await repository.getStoredOrder(), [
          'user-old',
          'user-new',
          'seed-art',
          'seed-nature',
          'seed-abstract',
          'seed-minimal',
        ]);
      },
    );

    test('reconciliation is idempotent across launches', () async {
      final repository = CollectionsRepository();
      await repository.open();
      await reconcileCollections(repository);
      final orderBefore = await repository.getStoredOrder();

      await reconcileCollections(repository);

      expect(await repository.getStoredOrder(), orderBefore);
      expect(
        (await repository.getAll()).length,
        seedCollections.length,
        reason: 'a healthy launch neither duplicates nor rewrites',
      );
    });
  });
}

CollectionEntry _entry(String id, String name, {DateTime? createdAt}) =>
    CollectionEntry(
      id: id,
      name: name,
      query: name.toLowerCase(),
      createdAt: createdAt ?? DateTime(2025, 1, 1),
    );
