import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_wallpaper/system_wallpaper.dart';

/// Channel-level contract tests for the wallpaper bridge.
///
/// Root widget journeys substitute a fake platform object, so these are the
/// only tests that can catch a broken native method name, argument key or
/// error-code translation.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('system_wallpaper');
  final platform = SystemWallpaperPlatform();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void stub(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  Future<WallpaperErrorCode> failureCode(
    Future<WallpaperResult> result,
  ) async {
    return ((await result) as WallpaperFailure).code;
  }

  group('SystemWallpaperPlatform', () {
    test('forwards both set commands to the native side', () async {
      final calls = <MethodCall>[];
      stub((call) async {
        calls.add(call);
        return {'success': true};
      });

      expect(
        await platform.setWallpaper(
          filePath: '/tmp/wall.jpg',
          target: WallpaperTarget.home,
        ),
        isA<WallpaperSuccess>(),
      );
      expect(
        await platform.setWithSystemPicker(filePath: '/tmp/wall.jpg'),
        isA<WallpaperSuccess>(),
      );

      expect(calls, hasLength(2));
      expect(calls[0].method, 'setWallpaper');
      expect(calls[0].arguments['path'], '/tmp/wall.jpg');
      expect(calls[0].arguments['target'], 'home');
      expect(calls[1].method, 'setWithSystemPicker');
      expect(calls[1].arguments['path'], '/tmp/wall.jpg');
    });

    test('rejects an empty path before reaching the platform', () async {
      var called = false;
      stub((call) async {
        called = true;
        return {'success': true};
      });

      expect(
        await failureCode(
          platform.setWallpaper(filePath: '', target: WallpaperTarget.both),
        ),
        WallpaperErrorCode.invalidArgs,
      );
      expect(
        await failureCode(platform.setWithSystemPicker(filePath: '')),
        WallpaperErrorCode.invalidArgs,
      );
      expect(called, isFalse);
    });

    test('translates native failures for both entry points', () async {
      stub((call) async => throw PlatformException(code: 'fileNotFound'));
      expect(
        await failureCode(
          platform.setWallpaper(
            filePath: '/tmp/missing.jpg',
            target: WallpaperTarget.lock,
          ),
        ),
        WallpaperErrorCode.fileNotFound,
      );

      stub((call) async => throw PlatformException(code: 'unsupported'));
      expect(
        await failureCode(
          platform.setWallpaper(
            filePath: '/tmp/wall.jpg',
            target: WallpaperTarget.both,
          ),
        ),
        WallpaperErrorCode.unsupported,
      );
      expect(
        await failureCode(
          platform.setWithSystemPicker(filePath: '/tmp/wall.jpg'),
        ),
        WallpaperErrorCode.unsupported,
      );
    });
  });
}
