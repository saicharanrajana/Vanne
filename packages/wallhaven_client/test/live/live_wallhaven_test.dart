import 'dart:io';

import 'package:test/test.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

/// Opt-in LIVE integration tests against the real Wallhaven API.
///
/// These never run as part of the normal test suite. Enable them with:
///
///     WALLHAVEN_LIVE=1 dart test test/live/live_wallhaven_test.dart
///
/// Authenticated checks additionally require `WALLHAVEN_API_KEY`. The suite
/// performs only a few requests and stays well within the 45 requests/minute
/// limit. The key is never printed.
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

  test('public listing, detail, and tag endpoints stay compatible', () async {
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

    // The docs' example id (94x38z) has been removed from the live API;
    // pick any latest SFW wallpaper instead of hardcoding one.
    final target = page.items.first.id;
    final wallpaper = await client.wallpaper(target);
    expect(wallpaper.id, target);
    expect(wallpaper.hasDetails, isTrue);
    expect(wallpaper.path, startsWith('https://'));

    final tag = await client.tag(1);
    expect(tag.id, 1);
    expect(tag.name, isNotEmpty);
  });

  if (envKey != null && envKey.isNotEmpty) {
    test('authenticated settings and collections endpoints stay compatible',
        () async {
      await client.settings();
      await client.collections();
    });
  }
}
