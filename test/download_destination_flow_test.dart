import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:system_wallpaper/system_wallpaper.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:vanne/app/dependencies.dart';
import 'package:vanne/app/router/tab_scroll_coordinator.dart';
import 'package:vanne/app/theme/app_theme.dart';
import 'package:vanne/core/downloads/app_identity.dart';
import 'package:vanne/core/downloads/download_destination.dart';
import 'package:vanne/core/downloads/download_destination_controller.dart';
import 'package:vanne/core/downloads/download_service.dart';
import 'package:vanne/core/services/wallpaper_applier.dart';
import 'package:vanne/core/storage/settings_store.dart';
import 'package:vanne/core/wallpaper/wallpaper_repository.dart';
import 'package:vanne/features/settings/application/settings_controller.dart';
import 'package:vanne/features/settings/presentation/settings_screen.dart';
import 'package:vanne/features/wallpaper_detail/application/wallpaper_detail_controller.dart';
import 'package:vanne/features/wallpaper_detail/presentation/widgets/wallpaper_action_bar.dart';
import 'package:vanne/shared/widgets/app_snack.dart';

class _StubRepository implements WallpaperRepository {
  @override
  bool get isAuthenticated => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Dio stand-in that writes bytes instead of touching the network.
class _FakeDio implements Dio {
  _FakeDio({this.gate});

  /// Awaited before the file is written, so tests can hold the transfer open.
  final Future<void>? gate;

  @override
  Future<Response> download(
    String urlPath,
    dynamic savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    FileAccessMode fileAccessMode = FileAccessMode.write,
    String lengthHeader = Headers.contentLengthHeader,
    Object? data,
    Options? options,
  }) async {
    if (gate != null) await gate;
    final file = File(savePath as String);
    await file.writeAsBytes(const [1, 2, 3, 4]);
    onReceiveProgress?.call(4, 4);
    return Response<dynamic>(
      requestOptions: RequestOptions(path: urlPath),
      statusCode: 200,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Wallpaper _wallpaper() => Wallpaper(
  id: 'download-fixture',
  url: 'https://wallhaven.cc/w/download-fixture',
  source: '',
  purity: Purity.sfw,
  category: Category.general,
  width: 1080,
  height: 1920,
  resolution: '1080x1920',
  ratio: '0.56',
  fileSizeBytes: 1000,
  fileType: 'image/jpeg',
  colors: const [],
  views: 0,
  favorites: 0,
  path: 'https://example.invalid/download-fixture.jpg',
  thumbnails: const Thumbnails(),
);

/// Records platform calls and answers them from queueable fakes.
final class _PlatformMock {
  final List<MethodCall> calls = <MethodCall>[];

  Map<String, Object?> Function(MethodCall call)? onPick;
  Map<String, Object?> Function(MethodCall call)? onCheck;
  Future<Object?> Function(MethodCall call)? onSave;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DownloadStoragePlatform.channel, (
          call,
        ) async {
          calls.add(call);
          switch (call.method) {
            case 'downloads.pickParent':
              return onPick?.call(call) ?? <String, Object?>{'canceled': true};
            case 'downloads.checkParent':
              return onCheck?.call(call) ??
                  <String, Object?>{'available': true, 'label': 'Family'};
            case 'downloads.save':
              return onSave?.call(call) ??
                  <String, Object?>{'uri': 'content://mock/saved'};
            case 'downloads.releaseParent':
              return null;
            default:
              return null;
          }
        });
  }

  void remove() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DownloadStoragePlatform.channel, null);
  }

  Iterable<MethodCall> callsTo(String method) =>
      calls.where((call) => call.method == method);
}

Future<void> _stubPathProvider(Directory dir) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async =>
            call.method == 'getTemporaryDirectory' ? dir.path : null,
      );
}

Future<void> _registerSettingsDependencies(
  DownloadDestinationController destination,
) async {
  final repository = _StubRepository();
  final settings = SettingsController(SettingsStore(), repository)..restore();
  locator
    ..registerSingleton<SettingsController>(settings)
    ..registerSingleton<DownloadDestinationController>(destination)
    ..registerSingleton<TabScrollCoordinator>(TabScrollCoordinator());
}

Future<void> _pumpSettings(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      scaffoldMessengerKey: AppSnack.messengerKey,
      theme: AppTheme.build(brightness: Brightness.light),
      // The real app hosts Settings in a Scaffold; snacks need one.
      home: Scaffold(
        body: SettingsScreen(onOpenApiKey: () {}, onOpenBlockedTags: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The Downloads row sits below the fold on the test surface.
Future<void> _revealDownloads(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Downloads'),
    220,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory hiveDir;
  late Directory tempDir;
  late SettingsStore store;
  late _PlatformMock platform;

  setUpAll(() async {
    hiveDir = await Directory.systemTemp.createTemp('download-dest-hive');
    tempDir = await Directory.systemTemp.createTemp('download-dest-tmp');
    Hive.init(hiveDir.path);
  });

  setUp(() async {
    // In-memory backend: widget tests run under fake async, where real file IO
    // never completes. An already-open box is reused by SettingsStore.open().
    final box = await Hive.openBox<dynamic>(
      'app_settings',
      bytes: Uint8List(0),
    );
    await box.clear();
    store = SettingsStore();
    await store.open();
    platform = _PlatformMock()..install();
    await _stubPathProvider(tempDir);
  });

  tearDown(() async {
    platform.remove();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    await locator.reset();
    await Hive.close();
  });

  group('Settings download folder', () {
    testWidgets(
      'default folder is Pictures/VanneWallpapers on its own emphasized line',
      (tester) async {
        await _registerSettingsDependencies(
          DownloadDestinationController(store),
        );
        await _pumpSettings(tester);
        await _revealDownloads(tester);

        expect(find.text(AppIdentity.defaultFolderPath), findsOneWidget);
        // The default root moved from DCIM to Pictures; the legacy root must
        // not appear anywhere in the row.
        expect(AppIdentity.defaultFolderPath, 'Pictures/VanneWallpapers');
        expect(find.textContaining('DCIM'), findsNothing);
        // Path and hint are separate lines, not one run-on sentence.
        expect(
          find.text(
            'Tap to change the downloads location',
          ),
          findsOneWidget,
        );

        final path = tester.widget<Text>(
          find.text(AppIdentity.defaultFolderPath),
        );
        expect(path.style?.fontWeight, FontWeight.w600);
        expect(path.maxLines, 2);
      },
    );

    testWidgets(
      'choosing a parent folder persists it and shows the child path',
      (tester) async {
        platform.onPick = (_) => <String, Object?>{
          'treeUri': 'content://com.android.externalstorage.documents/tree/primary%3AFamily',
          'label': 'Family',
        };
        final controller = DownloadDestinationController(store);
        addTearDown(controller.dispose);
        await _registerSettingsDependencies(controller);
        await _pumpSettings(tester);
        await _revealDownloads(tester);

        await tester.tap(find.text('Downloads'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Choose folder'));
        await tester.pumpAndSettle();

        expect(controller.destination.value, isA<ChosenDownloadDestination>());
        expect(
          controller.destination.value.folderPath,
          'Family/${AppIdentity.storageFolderName}',
        );
        expect(
          store.downloadTreeUri,
          'content://com.android.externalstorage.documents/tree/primary%3AFamily',
        );
        expect(store.downloadParentLabel, 'Family');
        expect(
          find.text('Family/${AppIdentity.storageFolderName}'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Saving downloads to Family/${AppIdentity.storageFolderName}',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('cancelling the picker keeps the previous destination', (
      tester,
    ) async {
      await store.setDownloadDestination(
        treeUri: 'content://tree/keep-me',
        parentLabel: 'Family',
      );
      platform.onPick = (_) => <String, Object?>{'canceled': true};
      final controller = DownloadDestinationController(store);
      addTearDown(controller.dispose);
      await controller.restore();
      await _registerSettingsDependencies(controller);
      await _pumpSettings(tester);
      await _revealDownloads(tester);

      await tester.tap(find.text('Downloads'));
      await tester.pumpAndSettle();
      // The explainer states the picker's own limits before it opens.
      expect(
        find.textContaining('Internal-storage root and Download'),
        findsOneWidget,
      );
      expect(find.textContaining('cloud apps'), findsOneWidget);
      await tester.tap(find.text('Choose folder'));
      await tester.pumpAndSettle();

      expect(controller.destination.value.treeUri, 'content://tree/keep-me');
      expect(store.downloadTreeUri, 'content://tree/keep-me');
      expect(platform.callsTo('downloads.releaseParent'), isEmpty);
    });

    testWidgets('use default resets the destination and releases the grant', (
      tester,
    ) async {
      await store.setDownloadDestination(
        treeUri: 'content://tree/old',
        parentLabel: 'Family',
      );
      final controller = DownloadDestinationController(store);
      addTearDown(controller.dispose);
      await controller.restore();
      await _registerSettingsDependencies(controller);
      await _pumpSettings(tester);
      await _revealDownloads(tester);

      await tester.tap(find.text('Downloads'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use default'));
      await tester.pumpAndSettle();

      expect(controller.destination.value, isA<DefaultDownloadDestination>());
      expect(store.downloadTreeUri, isNull);
      expect(store.downloadParentLabel, isNull);
      expect(
        platform.callsTo('downloads.releaseParent').single.arguments['treeUri'],
        'content://tree/old',
      );
      expect(find.text(AppIdentity.defaultFolderPath), findsOneWidget);
    });

    testWidgets('the destination row survives large text without overflow', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final controller = DownloadDestinationController(store);
      addTearDown(controller.dispose);
      await _registerSettingsDependencies(controller);
      await _pumpSettings(tester);
      await _revealDownloads(tester);

      expect(tester.takeException(), isNull);
      expect(find.text(AppIdentity.defaultFolderPath), findsOneWidget);
    });

    testWidgets('a revoked folder is surfaced in Settings', (tester) async {
      await store.setDownloadDestination(
        treeUri: 'content://tree/revoked',
        parentLabel: 'Family',
      );
      platform.onCheck = (_) => <String, Object?>{'available': false};
      final controller = DownloadDestinationController(store);
      addTearDown(controller.dispose);
      await controller.restore();
      await _registerSettingsDependencies(controller);
      await _pumpSettings(tester);
      await _revealDownloads(tester);

      expect(controller.access.value, DestinationAccess.lost);
      expect(find.textContaining('Folder access was lost'), findsOneWidget);
      expect(
        find.text('Family/${AppIdentity.storageFolderName}'),
        findsOneWidget,
      );
    });
  });

  group('download save routing', () {
    testWidgets(
      'download UI reports an unavailable feature instead of a format error',
      (tester) async {
        platform.remove(); // no native handler for downloads.save
        final controller = WallpaperDetailController(
          initial: _wallpaper(),
          repository: _StubRepository(),
          downloader: DownloadService(
            dio: _FakeDio(),
            destinationController: DownloadDestinationController(store),
          ),
          applier: WallpaperApplier(),
        );
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          MaterialApp(
            scaffoldMessengerKey: AppSnack.messengerKey,
            theme: AppTheme.build(brightness: Brightness.light),
            home: Scaffold(body: WallpaperActionBar(controller: controller)),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(PhosphorIconsBold.cloudArrowDown));
        // The transfer does real file IO, so alternate real async progress
        // with frames until the flow settles.
        for (
          var i = 0;
          i < 30 && controller.download.peek().error == null;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(controller.download.peek().done, isFalse);
        expect(
          controller.download.peek().error,
          'Saving downloads is unavailable in this build.',
        );
        expect(
          find.text('Saving downloads is unavailable in this build.'),
          findsOneWidget,
        );
        expect(find.textContaining('format'), findsNothing);
        expect(find.textContaining('Saved to'), findsNothing);
      },
    );

    test(
      'default destination saves through Pictures and reports after commit',
      () async {
        final gate = Completer<void>();
        platform.onSave = (_) async {
          await gate.future;
          return <String, Object?>{'uri': 'content://media/dcim/1'};
        };
        final controller = DownloadDestinationController(store);
        addTearDown(controller.dispose);
        final service = DownloadService(
          dio: _FakeDio(gate: gate.future),
          destinationController: controller,
        );

        var finished = false;
        final future = service
            .saveDownload(_wallpaper())
            .whenComplete(() => finished = true);

        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(finished, isFalse);

        gate.complete();
        await future;
        expect(finished, isTrue);

        final call = platform.callsTo('downloads.save').single;
        expect(call.arguments['folderName'], AppIdentity.storageFolderName);
        expect(call.arguments['mimeType'], 'image/jpeg');
        expect(call.arguments['treeUri'], isNull);
        expect(call.arguments['path'], endsWith('.jpg'));
        expect(service.destinationFolderPath, AppIdentity.defaultFolderPath);
      },
    );

    test('chosen destination passes the persisted tree URI', () async {
      await store.setDownloadDestination(
        treeUri: 'content://tree/chosen',
        parentLabel: 'Family',
      );
      final controller = DownloadDestinationController(store);
      addTearDown(controller.dispose);
      await controller.restore();
      final service = DownloadService(
        dio: _FakeDio(),
        destinationController: controller,
      );

      await service.saveDownload(_wallpaper());

      final call = platform.callsTo('downloads.save').single;
      expect(call.arguments['treeUri'], 'content://tree/chosen');
      expect(
        service.destinationFolderPath,
        'Family/${AppIdentity.storageFolderName}',
      );
      expect(controller.access.value, DestinationAccess.available);
    });

    test('out-of-space failure keeps an actionable message', () async {
      platform.onSave = (_) async =>
          throw PlatformException(code: 'noSpace', message: 'full');
      final controller = DownloadDestinationController(store);
      addTearDown(controller.dispose);
      final service = DownloadService(
        dio: _FakeDio(),
        destinationController: controller,
      );

      await expectLater(
        service.saveDownload(_wallpaper()),
        throwsA(
          isA<DownloadException>().having(
            (e) => e.message,
            'message',
            contains('Not enough storage space'),
          ),
        ),
      );
    });

    test(
      'a missing native bridge is not reported as a bad image format',
      () async {
        // No handler at all for the downloads method: invokeMethod throws
        // MissingPluginException, which is a build/plugin problem.
        platform.remove();
        final controller = DownloadDestinationController(store);
        addTearDown(controller.dispose);
        final service = DownloadService(
          dio: _FakeDio(),
          destinationController: controller,
        );

        await expectLater(
          service.saveDownload(_wallpaper()),
          throwsA(
            isA<DownloadException>()
                .having(
                  (e) => e.message,
                  'message',
                  'Saving downloads is unavailable in this build.',
                )
                .having(
                  (e) => e.message,
                  'not a format claim',
                  isNot(contains('format')),
                ),
          ),
        );
      },
    );

    test(
      'a revoked folder fails loudly and never falls back to default',
      () async {
        await store.setDownloadDestination(
          treeUri: 'content://tree/revoked',
          parentLabel: 'Family',
        );
        platform.onCheck = (_) => <String, Object?>{'available': false};
        platform.onSave = (_) async =>
            throw PlatformException(code: 'noPermission', message: 'revoked');
        final controller = DownloadDestinationController(store);
        addTearDown(controller.dispose);
        await controller.restore();
        final service = DownloadService(
          dio: _FakeDio(),
          destinationController: controller,
        );

        await expectLater(
          service.saveDownload(_wallpaper()),
          throwsA(
            isA<DownloadException>().having(
              (e) => e.message,
              'message',
              contains('no longer available'),
            ),
          ),
        );

        final saves = platform.callsTo('downloads.save').toList();
        expect(saves, hasLength(1));
        expect(saves.single.arguments['treeUri'], 'content://tree/revoked');
        expect(controller.destination.value.treeUri, 'content://tree/revoked');
        expect(controller.access.value, DestinationAccess.lost);
      },
    );
  });

  group('destination identity under concurrent activity', () {
    const uriA = 'content://tree/a';
    const uriB = 'content://tree/b';

    Future<DownloadDestinationController> chosen(
      String uri,
      String label,
    ) async {
      await store.setDownloadDestination(treeUri: uri, parentLabel: label);
      platform.onCheck = (_) =>
          <String, Object?>{'available': true, 'label': label};
      final controller = DownloadDestinationController(store);
      addTearDown(controller.dispose);
      await controller.restore();
      return controller;
    }

    test('re-selecting a folder A/B/A never releases the live grant', () async {
      final controller = await chosen(uriA, 'FamilyA');
      controller.beginSave();
      var pick = 0;
      platform.onPick = (_) => pick++ == 0
          ? <String, Object?>{'treeUri': uriB, 'label': 'FamilyB'}
          : <String, Object?>{'treeUri': uriA, 'label': 'FamilyA'};

      expect(await controller.chooseParent(), DestinationPickOutcome.picked);
      expect(await controller.chooseParent(), DestinationPickOutcome.picked);
      expect(controller.destination.value.treeUri, uriA);

      controller.endSave();
      final released = platform
          .callsTo('downloads.releaseParent')
          .map((call) => call.arguments['treeUri'])
          .toList();
      expect(released, isNot(contains(uriA)));
      expect(released, contains(uriB));
      expect(controller.destination.value.treeUri, uriA);
    });

    test(
      'a stale folder failure does not accuse the newly chosen folder',
      () async {
        final gate = Completer<void>();
        final controller = await chosen(uriA, 'FamilyA');
        platform.onSave = (call) async {
          await gate.future;
          throw PlatformException(code: 'noPermission', message: 'revoked');
        };
        final service = DownloadService(
          dio: _FakeDio(),
          destinationController: controller,
        );

        final saving = service.saveDownload(_wallpaper());
        await _waitFor(() => platform.callsTo('downloads.save').isNotEmpty);
        expect(
          platform.callsTo('downloads.save').single.arguments['treeUri'],
          uriA,
        );

        platform.onPick = (_) => <String, Object?>{
          'treeUri': uriB,
          'label': 'FamilyB',
        };
        expect(await controller.chooseParent(), DestinationPickOutcome.picked);
        expect(controller.destination.value.treeUri, uriB);

        gate.complete();
        await expectLater(saving, throwsA(isA<DownloadException>()));

        expect(controller.destination.value.treeUri, uriB);
        expect(controller.access.value, DestinationAccess.available);
      },
    );

    testWidgets(
      'success feedback names the folder that actually received the file',
      (tester) async {
        final gate = Completer<void>();
        final controller = await chosen(uriA, 'FamilyA');
        platform.onSave = (_) async {
          await gate.future;
          return <String, Object?>{'uri': 'content://tree/a/file'};
        };
        platform.onPick = (_) => <String, Object?>{
          'treeUri': uriB,
          'label': 'FamilyB',
        };

        final detail = WallpaperDetailController(
          initial: _wallpaper(),
          repository: _StubRepository(),
          downloader: DownloadService(
            dio: _FakeDio(),
            destinationController: controller,
          ),
          applier: WallpaperApplier(),
        );
        addTearDown(detail.dispose);

        await tester.pumpWidget(
          MaterialApp(
            scaffoldMessengerKey: AppSnack.messengerKey,
            theme: AppTheme.build(brightness: Brightness.light),
            home: Scaffold(body: WallpaperActionBar(controller: detail)),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(PhosphorIconsBold.cloudArrowDown));
        for (var i = 0; i < 40; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
          if (platform.callsTo('downloads.save').isNotEmpty) break;
        }
        expect(platform.callsTo('downloads.save'), isNotEmpty);

        // The user switches folders while the transfer is still running.
        await tester.runAsync(() => controller.chooseParent());
        expect(controller.destination.value.treeUri, uriB);

        gate.complete();
        for (var i = 0; i < 40 && detail.download.peek().done == false; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await tester.pumpAndSettle();

        expect(detail.download.peek().done, isTrue);
        expect(
          detail.download.peek().folderPath,
          'FamilyA/${AppIdentity.storageFolderName}',
        );
        expect(
          find.text('Saved to FamilyA/${AppIdentity.storageFolderName}'),
          findsOneWidget,
        );
        expect(
          find.text('Saved to FamilyB/${AppIdentity.storageFolderName}'),
          findsNothing,
        );
      },
    );
  });
}
