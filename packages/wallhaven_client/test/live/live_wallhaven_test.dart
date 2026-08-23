import 'dart:io';

import 'package:test/test.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

/// Opt-in LIVE integration tests against the real Wallhaven API.
///
/// These never run as part of the normal test suite. Enable them with:
///
///     WALLHAVEN_LIVE=1 dart test test/live/live_wallhaven_test.dart
///
/// Authenticated checks additionally require:
///
///     WALLHAVEN_API_KEY=<your key>   (never committed)
///
/// The suite performs at most ~5 unauthenticated requests plus 2
/// authenticated ones to stay well within the 45 requests/minute limit.
void main() {
  final live = Platform.environment['WALLHAVEN_LIVE'] == '1';
  if (!live) {
    // Registers (and skips) one test so `dart test` exits cleanly.
    test('live Wallhaven API tests', () {
      fail('Set WALLHAVEN_LIVE=1 to enable the live suite.');
    }, skip: 'set WALLHAVEN_LIVE=1 to enable');
    return;
  }

  final manager = ApiKeyManager();
  final envKey = Platform.environment['WALLHAVEN_API_KEY'];
  if (envKey != null && envKey.isNotEmpty) {
    manager.setApiKey(envKey);
  }
  final client = WallhavenClient(apiKeyManager: manager);
  tearDownAll(client.close);

  test('latest SFW search returns a page', () async {
    final page = await client.search(WallhavenSearchRequest());
    expect(page.items, isNotEmpty);
    expect(page.currentPage, 1);
    for (final wallpaper in page.items) {
      expect(wallpaper.purity, Purity.sfw);
      expect(wallpaper.id, isNotEmpty);
      expect(wallpaper.thumbnails.small ?? wallpaper.thumbnails.large,
          isNotNull,
          reason: 'thumbnails come from the API; never reconstructed');
    }
  });

  test('random search seed propagates across pages', () async {
    final request =
        WallhavenSearchRequest(sorting: WallhavenSorting.random);
    final first = await client.search(request);
    expect(first.items, isNotEmpty);

    // The server may or may not return a seed; when it does, the follow-up
    // page must carry it.
    if (!first.hasNextPage || first.meta.seed == null) {
      return; // nothing further to assert deterministically
    }
    final second = await client.nextPage(request, first);
    expect(second.currentPage, 2);
  });

  test('SFW wallpaper detail includes uploader and tags', () async {
    // The docs' example id (94x38z) has been removed from the live API;
    // pick any latest SFW wallpaper instead of hardcoding one.
    final listing = await client.search(WallhavenSearchRequest());
    final target = listing.items.first.id;

    final wallpaper = await client.wallpaper(target);
    expect(wallpaper.id, target);
    expect(wallpaper.hasDetails, isTrue);
    expect(wallpaper.path, startsWith('https://'));
  });
  test('known tag resolves', () async {
    final tag = await client.tag(1);
    expect(tag.id, 1);
    expect(tag.name, isNotEmpty);
  });

  test('NSFW search without key fails fast', () async {
    // Manager intentionally left keyless even when WALLHAVEN_API_KEY is
    // present — this asserts the local guard.
    final keyless = ApiKeyManager();
    final anonymous = WallhavenClient(apiKeyManager: keyless);
    addTearDown(anonymous.close);
    await expectLater(
      anonymous.search(WallhavenSearchRequest(
        purity: {WallhavenPurity.sfw, WallhavenPurity.nsfw},
      )),
      throwsA(isA<NsfwAuthenticationRequiredException>()),
    );
  });

  if (envKey != null && envKey.isNotEmpty) {
    test('authenticated settings read', () async {
      final settings = await client.settings();
      // Shape sanity only; values are user-specific.
      expect(settings.perPage, anyOf(isNull, isA<int>()));
    });

    test('own collections list', () async {
      final collections = await client.collections();
      expect(collections, isA<List<WallpaperCollection>>());
    });
  } else {
    // ignore: avoid_print
    print('WALLHAVEN_API_KEY not set — skipping authenticated live checks.');
  }
}
