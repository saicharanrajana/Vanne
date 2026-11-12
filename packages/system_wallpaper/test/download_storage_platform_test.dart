import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_wallpaper/system_wallpaper.dart';

/// Channel-level contract tests for the download storage bridge.
///
/// These prove the Dart side forwards arguments and maps results correctly;
/// they do not exercise MediaStore or the system folder picker on a device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final channel = DownloadStoragePlatform.channel;
  const platform = DownloadStoragePlatform();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void stub(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  group('saveDownload', () {
    test('forwards the default destination without a tree URI', () async {
      MethodCall? seen;
      stub((call) async {
        seen = call;
        return <String, Object?>{'uri': 'content://media/1'};
      });

      final result = await platform.saveDownload(
        sourcePath: '/tmp/wall.jpg',
        folderName: 'WallpaperApp',
        mimeType: 'image/jpeg',
      );

      expect(result, isA<DownloadSaveSuccess>());
      expect((result as DownloadSaveSuccess).uri, 'content://media/1');
      expect(seen!.method, 'downloads.save');
      expect(seen!.arguments['path'], '/tmp/wall.jpg');
      expect(seen!.arguments['folderName'], 'WallpaperApp');
      expect(seen!.arguments['mimeType'], 'image/jpeg');
      expect(seen!.arguments['treeUri'], isNull);
    });

    test('forwards a chosen tree URI', () async {
      MethodCall? seen;
      stub((call) async {
        seen = call;
        return <String, Object?>{'uri': 'content://tree/file'};
      });

      await platform.saveDownload(
        sourcePath: '/tmp/wall.jpg',
        folderName: 'WallpaperApp',
        mimeType: 'image/png',
        treeUri: 'content://tree/parent',
      );

      expect(seen!.arguments['treeUri'], 'content://tree/parent');
    });

    test('maps a revoked grant to noPermission', () async {
      stub((call) async {
        throw PlatformException(code: 'noPermission', message: 'revoked');
      });

      final result = await platform.saveDownload(
        sourcePath: '/tmp/wall.jpg',
        folderName: 'WallpaperApp',
        mimeType: 'image/jpeg',
        treeUri: 'content://tree/parent',
      );

      expect(
        (result as DownloadSaveFailure).code,
        DownloadSaveErrorCode.noPermission,
      );
    });

    test('maps a moved folder to destinationUnavailable', () async {
      stub((call) async {
        throw PlatformException(code: 'destinationUnavailable');
      });

      final result = await platform.saveDownload(
        sourcePath: '/tmp/wall.jpg',
        folderName: 'WallpaperApp',
        mimeType: 'image/jpeg',
        treeUri: 'content://tree/parent',
      );

      expect(
        (result as DownloadSaveFailure).code,
        DownloadSaveErrorCode.destinationUnavailable,
      );
    });

    test('rejects missing arguments without calling the platform', () async {
      var called = false;
      stub((call) async {
        called = true;
        return null;
      });

      final result = await platform.saveDownload(
        sourcePath: '',
        folderName: 'WallpaperApp',
        mimeType: 'image/jpeg',
      );

      expect(
        (result as DownloadSaveFailure).code,
        DownloadSaveErrorCode.invalidArgs,
      );
      expect(called, isFalse);
    });
  });

  group('pickParent', () {
    test('returns the persisted tree and its display label', () async {
      stub(
        (call) async => <String, Object?>{
          'treeUri': 'content://tree/family',
          'label': 'Family',
        },
      );

      final result = await platform.pickParent();

      expect(result, isA<ParentPicked>());
      expect((result as ParentPicked).treeUri, 'content://tree/family');
      expect(result.label, 'Family');
    });

    test('reports cancellation', () async {
      stub((call) async => <String, Object?>{'canceled': true});

      expect(await platform.pickParent(), isA<ParentPickCanceled>());
    });

    test('surfaces a busy picker instead of starting a second one', () async {
      stub((call) async {
        throw PlatformException(code: 'busy', message: 'already open');
      });

      final result = await platform.pickParent();

      expect((result as ParentPickFailure).code, 'busy');
    });

    test('surfaces a read-only folder rejection', () async {
      stub((call) async {
        throw PlatformException(code: 'noWriteAccess');
      });

      final result = await platform.pickParent();

      expect((result as ParentPickFailure).code, 'noWriteAccess');
    });
  });

  group('checkParent', () {
    test('reports the current label when the grant still works', () async {
      stub(
        (call) async => <String, Object?>{
          'available': true,
          'label': 'Renamed family',
        },
      );

      final result = await platform.checkParent('content://tree/family');

      expect(result, isA<ParentAccessAvailable>());
      expect((result as ParentAccessAvailable).label, 'Renamed family');
    });

    test('reports a lost grant', () async {
      stub((call) async => <String, Object?>{'available': false});

      expect(
        await platform.checkParent('content://tree/family'),
        isA<ParentAccessLost>(),
      );
    });

    test('keeps an unknown platform failure distinguishable', () async {
      stub((call) async {
        throw PlatformException(code: 'io');
      });

      final result = await platform.checkParent('content://tree/family');

      expect(result, isA<ParentAccessUnknown>());
    });
  });

  test('releaseParent swallows platform failures', () async {
    stub((call) async {
      expect(call.method, 'downloads.releaseParent');
      throw PlatformException(code: 'unsupported');
    });

    await expectLater(
      platform.releaseParent('content://tree/family'),
      completes,
    );
  });
}
