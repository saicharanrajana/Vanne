import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallpaper_app/core/services/url_launcher_service.dart';

void main() {
  test('launches the URL without a canLaunchUrl preflight', () async {
    final url = Uri.parse('https://wallhaven.cc/w/abc123');
    var launchCount = 0;

    final service = UrlLauncherService(
      launch: (launchedUrl) async {
        launchCount++;
        expect(launchedUrl, url);
        return true;
      },
    );

    expect(await service.openInApp(url), isTrue);
    expect(launchCount, 1);
  });

  test('returns false when the platform cannot launch the URL', () async {
    final service = UrlLauncherService(
      launch: (_) async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
    );

    expect(
      await service.openInApp(Uri.parse('https://wallhaven.cc/w/abc123')),
      isFalse,
    );
  });
}
