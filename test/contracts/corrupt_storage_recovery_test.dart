// Contract: a corrupt persisted row is skipped, never fatal.
//
// Local boxes are untrusted input. A row can be valid JSON with the wrong
// shape — `[]`, `{}`, a numeric `id`, a string `width` — and the decoders used
// to cast straight out of `jsonDecode` while catching only `FormatException`.
// A cast failure throws `TypeError`, which escaped the batch isolate and
// rejected `getAll()`. Bootstrap awaits collection reconciliation and favorite
// restoration, so a single bad row left the user on the startup retry screen
// for good, with no way to recover except reinstalling.
//
// What is protected:
//  - both decoders reject non-object JSON and contain field-type failures,
//  - a batch with healthy + corrupt rows keeps every healthy row,
//  - an `id`-less row is corrupt (every screen routes and keys by id),
//  - the real `bootstrap()` reaches a working app with corrupt rows on disk,
//  - a box where EVERY row is corrupt still starts with an empty state,
//  - the healthy data that survived is fully usable and persists.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:vanne/app/dependencies.dart';
import 'package:vanne/core/collections/collection_entry.dart';
import 'package:vanne/core/collections/collections_repository.dart';
import 'package:vanne/core/collections/seed_collections.dart';
import 'package:vanne/core/domain/feed_filter.dart';
import 'package:vanne/core/domain/favorite_wallpaper.dart';
import 'package:vanne/core/favorites/favorites_repository.dart';
import 'package:vanne/core/storage/persisted_json.dart';
import 'package:vanne/features/collections/application/collections_controller.dart';
import 'package:vanne/features/favorites/application/favorites_controller.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

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

CollectionEntry _collection(String id) => CollectionEntry(
  id: id,
  name: 'Saved $id',
  query: 'cats',
  origin: CollectionOrigin.tag,
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
  thumbnails: const Thumbnails(),
);

/// Rows with no usable identity — the only rows a restore may drop.
///
/// Kept as raw strings because that is exactly what Hive hands back: the
/// decoder sees text, not a typed row. Damaged *metadata* is deliberately not
/// in this list: those rows belong to the user and are restored with safe
/// defaults (see the "damaged metadata" group).
const _corruptRows = <String>[
  'this is not json at all', // FormatException
  '[]', // valid JSON, not an object
  '"just a string"', // valid JSON, not an object
  '123', // valid JSON, not an object
  'null', // valid JSON, not an object
  '{}', // object with no id
  '{"id":42}', // id has the wrong type
  '{"id":""}', // empty id cannot be keyed or routed
  '{"id":null}', // id is absent in all but name
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('decoders', () {
    test('non-finite numeric metadata falls back safely', () {
      expect(readInt(double.infinity), 0);
      expect(readInt(double.nan), 0);
    });

    test('a stored snapshot round-trips', () {
      final decoded = FavoriteWallpaper.decode(_favorite('aaa111').encode());

      expect(decoded, isNotNull);
      expect(decoded!.id, 'aaa111');
      expect(decoded.imageUrl, 'https://example.com/aaa111.jpg');
    });

    test('a stored collection round-trips', () {
      final decoded = CollectionEntry.decode(_collection('user-one').encode());

      expect(decoded, isNotNull);
      expect(decoded!.id, 'user-one');
      expect(decoded.query, 'cats');
      expect(decoded.origin, CollectionOrigin.tag);
    });

    test('every corrupt favorite row decodes to null, not an exception', () {
      for (final raw in _corruptRows) {
        expect(
          FavoriteWallpaper.decode(raw),
          isNull,
          reason: 'row <$raw> must be skipped, not thrown out of the batch',
        );
      }
    });

    test('every corrupt collection row decodes to null, not an exception', () {
      for (final raw in _corruptRows) {
        expect(
          CollectionEntry.decode(raw),
          isNull,
          reason: 'row <$raw> must be skipped, not thrown out of the batch',
        );
      }
    });
  });

  group('damaged metadata keeps the row', () {
    test('a favorite keeps its identity and defaults the rest', () {
      final favorite = FavoriteWallpaper.decode(
        '{"id":"keep1","pageUrl":9,"imageUrl":[],"thumbnailUrl":{},'
        '"width":"wide","fileSizeBytes":null,"createdAt":7}',
      );

      expect(
        favorite,
        isNotNull,
        reason: 'the row identifies a real wallpaper',
      );
      expect(favorite!.id, 'keep1');
      expect(
        favorite.pageUrl,
        'https://wallhaven.cc/w/keep1',
        reason: 'a lost page URL is rebuilt from the id, not left unusable',
      );
      expect(favorite.imageUrl, isEmpty);
      expect(favorite.thumbnailUrl, isNull);
      expect(favorite.width, 0);
      expect(favorite.fileSizeBytes, 0);
      expect(favorite.createdAt, isNull, reason: 'no timestamp is not fatal');
    });

    test('whole JSON doubles are read as whole numbers', () {
      final favorite = FavoriteWallpaper.decode(
        '{"id":"keep2","width":1920.0,"height":1080.0}',
      );

      expect(favorite, isNotNull);
      expect(
        favorite!.width,
        1920,
        reason: 'a double-typed dimension must not delete a saved wallpaper',
      );
      expect(favorite.height, 1080);
    });

    test('a collection keeps its identity and defaults the rest', () {
      final entry = CollectionEntry.decode(
        '{"id":"keep3","name":5,"query":[],"colors":"red","kinds":{},'
        '"origin":42,"createdAt":false,"filter":{"sorting":9,"topRange":[],'
        '"minResolution":false,"categories":"general"}}',
      );

      expect(entry, isNotNull, reason: 'the row identifies a real collection');
      expect(entry!.id, 'keep3');
      expect(entry.name, isEmpty);
      expect(entry.query, isEmpty);
      expect(entry.colors, isEmpty);
      expect(entry.kinds, isEmpty);
      expect(entry.origin, CollectionOrigin.unknown);
      expect(entry.filter.sorting, FeedSorting.newest);
      expect(entry.filter.topRange, isNull);
      expect(entry.filter.minResolution, isNull);
      expect(entry.filter.categories, {WallhavenCategory.general});
      expect(entry.createdAt, isA<DateTime>());
    });

    test(
      'a row with damaged metadata is restored beside healthy rows',
      () async {
        final dir = Directory.systemTemp.createTempSync('vanne_keep_row_');
        Hive.init(dir.path);
        addTearDown(() async {
          await Hive.close();
          try {
            dir.deleteSync(recursive: true);
          } on FileSystemException {
            // Best-effort cleanup.
          }
        });

        final box = await Hive.openBox<String>('favorites');
        await box.put('aaa111', _favorite('aaa111').encode());
        await box.put('keep4', '{"id":"keep4","width":"wide"}');
        await box.close();

        final repository = FavoritesRepository();
        await repository.open();

        expect(
          (await repository.getAll()).map((favorite) => favorite.id),
          ['aaa111', 'keep4'],
          reason: 'one damaged field must not delete the user\u2019s wallpaper',
        );
      },
    );
  });

  group('repositories', () {
    late Directory dir;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('vanne_corrupt_');
      Hive.init(dir.path);
    });

    tearDown(() async {
      await Hive.close();
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort: a leaked temp dir must not fail a passing test.
      }
    });

    test('a healthy favorite survives every corrupt row beside it', () async {
      final box = await Hive.openBox<String>('favorites');
      await box.put('aaa111', _favorite('aaa111').encode());
      for (var i = 0; i < _corruptRows.length; i++) {
        await box.put('corrupt$i', _corruptRows[i]);
      }
      await box.close();

      final repository = FavoritesRepository();
      await repository.open();
      final favorites = await repository.getAll();

      expect(favorites.map((f) => f.id), ['aaa111']);
    });

    test('a healthy collection survives every corrupt row beside it', () async {
      final box = await Hive.openBox<String>('collections');
      await box.put('user-one', _collection('user-one').encode());
      for (var i = 0; i < _corruptRows.length; i++) {
        await box.put('corrupt$i', _corruptRows[i]);
      }
      await box.put('collection_order', 'ignored by the row box');
      await box.close();

      final repository = CollectionsRepository();
      await repository.open();
      final collections = await repository.getAll();

      expect(collections.map((c) => c.id), ['user-one']);
      // The order box is seeded so a repair cannot hide a dropped row.
      expect(await repository.getStoredOrder(), isNull);
    });
  });

  group('real bootstrap', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('vanne_bootstrap_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProviderChannel, (call) async {
            switch (call.method) {
              case 'getApplicationDocumentsDirectory':
              case 'getApplicationSupportDirectory':
              case 'getTemporaryDirectory':
                return dir.path;
            }
            return null;
          });
      FlutterSecureStorage.setMockInitialValues({});
    });

    tearDown(() async {
      await locator.reset();
      await Hive.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_pathProviderChannel, null);
      try {
        dir.deleteSync(recursive: true);
      } on FileSystemException {
        // Best-effort cleanup.
      }
    });

    test('corrupt rows on disk still reach a working app', () async {
      await _seedRealStorage(dir.path, healthyRow: true);

      // The production entry point: this is what used to never complete.
      await bootstrap();

      final favorites = locator<FavoritesController>();
      expect(favorites.favoriteIds.value, {'aaa111'});

      final collections = locator<CollectionsController>();
      expect(collections.ids.value, contains('user-one'));
      expect(
        collections.ids.value,
        containsAll(curatedSeedIds),
        reason: 'reconciliation still restores the curated collections',
      );
    });

    test('a box where every row is corrupt still starts empty', () async {
      await _seedRealStorage(dir.path, healthyRow: false);

      await bootstrap();

      expect(locator<FavoritesController>().favoriteIds.value, isEmpty);
      expect(
        locator<CollectionsController>().ids.value,
        curatedSeedIds.toSet(),
      );
    });

    test('overflowing numeric metadata cannot abort bootstrap', () async {
      await _seedRealStorage(
        dir.path,
        healthyRow: true,
        overflowingNumber: true,
      );

      await bootstrap();

      final favorites = locator<FavoritesController>();
      expect(favorites.favoriteIds.value, {'aaa111', 'overflow1'});
      final restored = await locator<FavoritesRepository>().getAll();
      expect(
        restored.singleWhere((favorite) => favorite.id == 'overflow1').width,
        0,
        reason: '1e999 is non-finite and falls back to the field default',
      );
    });

    test('the rows that survived are fully usable and persist', () async {
      await _seedRealStorage(dir.path, healthyRow: true);
      await bootstrap();

      final favorites = locator<FavoritesController>();
      final collections = locator<CollectionsController>();

      // Usable through the real controllers, not just readable.
      expect(await favorites.toggle(_wallpaper('aaa111')), isTrue);
      expect(favorites.favoriteIds.value, isEmpty, reason: 'unfavorited');
      expect(await collections.remove('user-one'), isTrue);
      expect(collections.ids.value, isNot(contains('user-one')));

      // Restart over the same storage: the writes own the boxes that the
      // corrupt neighbours could previously have poisoned.
      await Hive.close();
      await locator.reset();
      await bootstrap();

      expect(locator<FavoritesController>().favoriteIds.value, isEmpty);
      expect(
        locator<CollectionsController>().ids.value,
        isNot(contains('user-one')),
        reason: 'a collection removed beside corrupt rows stays removed',
      );
      expect(
        locator<CollectionsController>().ids.value,
        containsAll(curatedSeedIds),
        reason: 'the curated collections are still reconciled on every launch',
      );
    });
  });
}

/// Writes the mixed healthy/corrupt state straight into the real boxes.
Future<void> _seedRealStorage(
  String path, {
  required bool healthyRow,
  bool overflowingNumber = false,
}) async {
  Hive.init(path);
  final favorites = await Hive.openBox<String>('favorites');
  if (healthyRow) await favorites.put('aaa111', _favorite('aaa111').encode());
  if (overflowingNumber) {
    await favorites.put('overflow1', '{"id":"overflow1","width":1e999}');
  }
  for (var i = 0; i < _corruptRows.length; i++) {
    await favorites.put('corrupt$i', _corruptRows[i]);
  }
  await favorites.close();

  final collections = await Hive.openBox<String>('collections');
  if (healthyRow) {
    await collections.put('user-one', _collection('user-one').encode());
  }
  for (var i = 0; i < _corruptRows.length; i++) {
    await collections.put('corrupt$i', _corruptRows[i]);
  }
  await collections.close();
}
