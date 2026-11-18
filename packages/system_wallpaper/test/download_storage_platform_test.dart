import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_wallpaper/system_wallpaper.dart';

/// Channel-level contract tests for the download storage bridge.
///
/// These prove the Dart side forwards arguments and maps results correctly;
/// they do not exercise MediaStore or the system folder picker on a device.
/// Root widget journeys fake this platform object, so they cannot replace it.
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
    test('forwards the save command for both destinations', () async {
      final calls = <MethodCall>[];
      stub((call) async {
        calls.add(call);
        return <String, Object?>{'uri': 'content://media/1'};
      });

      final defaultDestination = await platform.saveDownload(
        sourcePath: '/tmp/wall.jpg',
        folderName: 'WallpaperApp',
        mimeType: 'image/jpeg',
      );
      final chosenDestination = await platform.saveDownload(
        sourcePath: '/tmp/wall.jpg',
        folderName: 'WallpaperApp',
        mimeType: 'image/png',
        treeUri: 'content://tree/parent',
      );

      expect(defaultDestination, isA<DownloadSaveSuccess>());
      expect(
        (defaultDestination as DownloadSaveSuccess).uri,
        'content://media/1',
      );
      expect(chosenDestination, isA<DownloadSaveSuccess>());

      expect(calls, hasLength(2));
      expect(calls[0].method, 'downloads.save');
      expect(calls[0].arguments['path'], '/tmp/wall.jpg');
      expect(calls[0].arguments['folderName'], 'WallpaperApp');
      expect(calls[0].arguments['mimeType'], 'image/jpeg');
      expect(calls[0].arguments['treeUri'], isNull);
      expect(calls[1].arguments['mimeType'], 'image/png');
      expect(calls[1].arguments['treeUri'], 'content://tree/parent');
    });

    test('maps native save errors to distinct failure codes', () async {
      stub((call) async {
        throw PlatformException(code: 'noPermission', message: 'revoked');
      });
      final revoked = await platform.saveDownload(
        sourcePath: '/tmp/wall.jpg',
        folderName: 'WallpaperApp',
        mimeType: 'image/jpeg',
        treeUri: 'content://tree/parent',
      );
      expect(
        (revoked as DownloadSaveFailure).code,
        DownloadSaveErrorCode.noPermission,
      );

      stub((call) async {
        throw PlatformException(code: 'destinationUnavailable');
      });
      final moved = await platform.saveDownload(
        sourcePath: '/tmp/wall.jpg',
        folderName: 'WallpaperApp',
        mimeType: 'image/jpeg',
        treeUri: 'content://tree/parent',
      );
      expect(
        (moved as DownloadSaveFailure).code,
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

    test('passes picker errors through with their codes', () async {
      stub((call) async {
        throw PlatformException(code: 'busy', message: 'already open');
      });
      final busy = await platform.pickParent();
      expect((busy as ParentPickFailure).code, 'busy');

      stub((call) async {
        throw PlatformException(code: 'noWriteAccess');
      });
      final readOnly = await platform.pickParent();
      expect((readOnly as ParentPickFailure).code, 'noWriteAccess');
    });
  });

  group('checkParent', () {
    test('distinguishes available, lost, and unknown grants', () async {
      stub(
        (call) async => <String, Object?>{
          'available': true,
          'label': 'Renamed family',
        },
      );
      final available = await platform.checkParent('content://tree/family');
      expect(available, isA<ParentAccessAvailable>());
      expect((available as ParentAccessAvailable).label, 'Renamed family');

      stub((call) async => <String, Object?>{'available': false});
      expect(
        await platform.checkParent('content://tree/family'),
        isA<ParentAccessLost>(),
      );

      stub((call) async {
        throw PlatformException(code: 'io');
      });
      expect(
        await platform.checkParent('content://tree/family'),
        isA<ParentAccessUnknown>(),
      );
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
