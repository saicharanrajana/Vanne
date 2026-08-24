import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_wallpaper/system_wallpaper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('system_wallpaper');
  final platform = SystemWallpaperPlatform();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('SystemWallpaperPlatform', () {
    test('setWallpaper success', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'setWallpaper');
        expect(call.arguments['path'], '/tmp/wall.jpg');
        expect(call.arguments['target'], 'home');
        return {'success': true};
      });

      final result = await platform.setWallpaper(
        filePath: '/tmp/wall.jpg',
        target: WallpaperTarget.home,
      );
      expect(result, isA<WallpaperSuccess>());
    });

    test('setWallpaper validates empty path', () async {
      final result = await platform.setWallpaper(
        filePath: '',
        target: WallpaperTarget.both,
      );
      expect(result, isA<WallpaperFailure>());
      expect((result as WallpaperFailure).code, WallpaperErrorCode.invalidArgs);
    });

    test('setWallpaper maps fileNotFound', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'fileNotFound', message: 'Not found');
      });
      final result = await platform.setWallpaper(
        filePath: '/tmp/missing.jpg',
        target: WallpaperTarget.lock,
      );
      expect((result as WallpaperFailure).code, WallpaperErrorCode.fileNotFound);
    });

    test('setWallpaper maps unsupported', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'unsupported', message: 'No handler');
      });
      final result = await platform.setWallpaper(
        filePath: '/tmp/wall.jpg',
        target: WallpaperTarget.both,
      );
      expect((result as WallpaperFailure).code, WallpaperErrorCode.unsupported);
    });

    test('setWithSystemPicker success', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'setWithSystemPicker');
        return {'success': true};
      });
      final result = await platform.setWithSystemPicker(filePath: '/tmp/wall.jpg');
      expect(result, isA<WallpaperSuccess>());
    });

    test('setWithSystemPicker maps unsupported', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'unsupported', message: 'No app found');
      });
      final result = await platform.setWithSystemPicker(filePath: '/tmp/wall.jpg');
      expect((result as WallpaperFailure).code, WallpaperErrorCode.unsupported);
    });

    test('setWithSystemPicker validates empty path', () async {
      final result = await platform.setWithSystemPicker(filePath: '');
      expect((result as WallpaperFailure).code, WallpaperErrorCode.invalidArgs);
    });
  });
}
