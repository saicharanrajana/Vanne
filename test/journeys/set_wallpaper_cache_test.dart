// Journeys: preparing a wallpaper for "Set" is a cache round-trip the user
// never sees, so every failure mode has to repair itself silently.
//
// "Set" downloads the full-resolution image into a cache path derived from the
// wallpaper id, then hands that path to the platform. Two shapes of trouble
// reach the user:
//
//  * an older build wrote straight into that path, so a process killed
//    mid-transfer left a truncated file that was reused on every later attempt
//    — "Set" then fails forever with nothing to retry,
//  * the image host is unreachable, and the row must report it, keep no file,
//    and succeed on retry.
//
// What is protected:
//  - a truncated file left by an older build is neither reused nor handed to
//    the platform; the wallpaper is fetched again and the applied bytes are
//    the complete image,
//  - a preparation is reused for the next option (no second transfer),
//  - a failed preparation shows a message, leaves no cache file, and a retry
//    succeeds,
//  - leaving the screen while a transfer is in flight cancels it and publishes
//    nothing.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:system_wallpaper/system_wallpaper.dart';
import 'package:vanne/core/downloads/download_service.dart';
import 'package:vanne/features/wallpaper_detail/application/wallpaper_detail_controller.dart';
import 'package:vanne/shared/widgets/app_snack.dart';

import '../support/test_app.dart';

/// A structurally complete JPEG. The app never decodes the file it prepares
/// (the platform does), so marker-level bytes are enough here.
final _completeJpeg = Uint8List.fromList(const [
  0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, //
  0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9,
]);

/// What the same transfer looks like when the process dies mid-write.
final _truncatedJpeg = Uint8List.fromList(
  _completeJpeg.sublist(0, _completeJpeg.length - 2),
);

enum _HostMode { serve, offline, stall }

/// Image host behind a real `Dio`, so the transport behaves as shipped.
final class _ImageHost implements HttpClientAdapter {
  _HostMode mode = _HostMode.serve;

  /// Transfers started; the count proves cache reuse and real retries.
  int transfers = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    transfers++;
    switch (mode) {
      case _HostMode.serve:
        return ResponseBody.fromBytes(
          _completeJpeg,
          200,
          headers: {
            Headers.contentLengthHeader: [_completeJpeg.length.toString()],
            Headers.contentTypeHeader: ['image/jpeg'],
          },
        );
      case _HostMode.offline:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: 'offline',
        );
      case _HostMode.stall:
        final body = StreamController<Uint8List>();
        // A real adapter surfaces cancellation as an error on the body.
        unawaited(cancelFuture?.then((_) {
          if (body.isClosed) return;
          body.addError(
            DioException(
              requestOptions: options,
              type: DioExceptionType.cancel,
            ),
          );
          body.close();
        }));
        return ResponseBody(body.stream, 200);
    }
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  Finder tile(String id) => find.byKey(ValueKey('wallpaper-tile-$id'));
  final back = find.byIcon(PhosphorIconsBold.arrowLeft).first;

  /// The action row lives inside a draggable sheet; scroll it into view first,
  /// exactly like a user reaching for it.
  Future<void> revealSheet(WidgetTester tester, Finder finder) async {
    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -300),
    );
    await pumpFrames(tester, 6, const Duration(milliseconds: 100));
    await tester.ensureVisible(finder);
    await tester.pump(const Duration(milliseconds: 120));
  }

  Future<void> tapSheet(WidgetTester tester, TestApp app, Finder finder) async {
    await revealSheet(tester, finder);
    await app.persistTap(tester, finder);
  }

  /// Snackbars cover the bottom action row; they run on real timers, so tests
  /// dismiss them instead of waiting.
  Future<void> clearSnack(WidgetTester tester) async {
    AppSnack.messengerKey.currentState?.clearSnackBars();
    await pumpFrames(tester, 6);
  }

  /// Opens the detail screen with this test's image host installed.
  ///
  /// Replacing `app.downloader` works because the detail controller factory
  /// reads the field when a route is created, which happens after this point.
  Future<_ImageHost> openDetail(
    WidgetTester tester,
    TestApp app, {
    Duration receiveTimeout = const Duration(milliseconds: 400),
  }) async {
    await app.launch(tester);
    final host = _ImageHost();
    app.downloader = DownloadService(
      dio: Dio(BaseOptions(receiveTimeout: receiveTimeout))
        ..httpClientAdapter = host,
      destinationController: app.destination,
      platform: app.storagePlatform,
    );
    await pumpUntil(tester, tile('alpha'), reason: 'discover tile');
    await app.tap(tester, tile('alpha'));
    await pumpUntil(tester, find.text('Set'), reason: 'detail actions');
    return host;
  }

  /// File names in the folder the app publishes prepared images into. As real
  /// I/O, and resolved through production code so the layout cannot drift.
  Future<List<String>> preparedFiles(WidgetTester tester) async {
    final names = await tester.runAsync(() async {
      final base = await getTemporaryDirectory();
      final dir = WallpaperDetailController.wallpaperApplyDir(base);
      if (!dir.existsSync()) return <String>[];
      return dir
          .listSync()
          .whereType<File>()
          .map((file) => file.path.split('${dir.path}/').last)
          .toList();
    });
    return names ?? const [];
  }

  Future<List<int>> readBytes(WidgetTester tester, File file) async =>
      (await tester.runAsync(file.readAsBytes))!;

  Future<bool> exists(WidgetTester tester, File file) async =>
      (await tester.runAsync(file.exists))!;

  appTest('a truncated file from an older build is fetched again, not reused', (
    tester,
    app,
  ) async {
    final host = await openDetail(tester, app);

    // An older build crashed mid-write, leaving a prefix at the cache path it
    // used. It looks like a downloaded wallpaper but is not one.
    final legacy = (await tester.runAsync(() async {
      final base = await getTemporaryDirectory();
      final file = File('${base.path}/wallpaper_apply/wallhaven_alpha.jpg');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(_truncatedJpeg);
      return file;
    }))!;
    expect(await exists(tester, legacy), isTrue);

    await tapSheet(tester, app, find.text('Set'));
    await app.settleUntil(
      tester,
      () => find.text('Set wallpaper').evaluate().isNotEmpty,
      reason: 'set-wallpaper sheet after a fresh download',
    );
    expect(host.transfers, 1, reason: 'the stale prefix was never reused');

    await app.persistTap(tester, find.text('Home Screen'));
    await app.settleUntil(
      tester,
      () => app.wallpaperPlatform.appliedPaths.isNotEmpty,
      reason: 'apply reached platform',
    );
    final applied = File(app.wallpaperPlatform.appliedPaths.single);
    expect(
      await readBytes(tester, applied),
      _completeJpeg,
      reason: 'the platform was handed the whole image',
    );
    expect(
      applied.path,
      isNot(legacy.path),
      reason: 'the abandoned prefix stays where it was, unread',
    );

    // A second option reuses the preparation from a moment ago.
    await clearSnack(tester);
    await tapSheet(tester, app, find.text('Set'));
    await app.settleUntil(
      tester,
      () => find.text('Set wallpaper').evaluate().isNotEmpty,
      reason: 'second sheet',
    );
    expect(host.transfers, 1, reason: 'a prepared file is not refetched');

    await app.persistTap(tester, find.text('Lock Screen'));
    await app.settleUntil(
      tester,
      () => app.wallpaperPlatform.appliedPaths.length == 2,
      reason: 'second apply reached platform',
    );
    expect(
      await preparedFiles(tester),
      ['wallhaven_alpha.jpg'],
      reason: 'one published file, no scratch leftovers',
    );
  });

  appTest('a failed preparation reports, keeps nothing, and retries', (
    tester,
    app,
  ) async {
    final host = await openDetail(tester, app);
    host.mode = _HostMode.offline;

    await tapSheet(tester, app, find.text('Set'));
    await pumpUntil(
      tester,
      find.text('Network unavailable. Check your connection.'),
      reason: 'offline message for a failed preparation',
    );
    expect(
      find.text('Set wallpaper'),
      findsNothing,
      reason: 'no sheet is offered for a file that does not exist',
    );
    expect(
      await preparedFiles(tester),
      isEmpty,
      reason: 'a failed transfer publishes nothing',
    );

    // The user fixes their connection and taps again.
    host.mode = _HostMode.serve;
    await clearSnack(tester);
    await tapSheet(tester, app, find.text('Set'));
    await app.settleUntil(
      tester,
      () => find.text('Set wallpaper').evaluate().isNotEmpty,
      reason: 'retry after the network came back',
    );
    expect(host.transfers, 2, reason: 'the retry did a real transfer');

    await app.persistTap(tester, find.text('Home & Lock Screen'));
    await app.settleUntil(
      tester,
      () => app.wallpaperPlatform.appliedTargets.isNotEmpty,
      reason: 'apply after retry',
    );
    expect(app.wallpaperPlatform.appliedTargets, [WallpaperTarget.both]);
  });

  appTest('leaving during a stalled preparation cancels it quietly', (
    tester,
    app,
  ) async {
    // Long inactivity window: the point is that leaving cancels, not that the
    // transport gives up first.
    final host = await openDetail(
      tester,
      app,
      receiveTimeout: const Duration(seconds: 30),
    );
    host.mode = _HostMode.stall;

    await revealSheet(tester, find.text('Set'));
    await tester.runAsync(() => tester.tap(find.text('Set')));
    // The transfer runs in the real zone, so let real time pass.
    await app.settle(tester, rounds: 4);
    expect(host.transfers, 1, reason: 'the transfer started');

    // The user gives up before it finishes: the pop runs the route transition
    // and then disposes the controller, which cancels the transfer.
    await tester.runAsync(() => tester.tap(back));
    await pumpFrames(tester, 10, const Duration(milliseconds: 100));
    await app.settle(tester, rounds: 6);

    expect(
      find.text('Set wallpaper'),
      findsNothing,
      reason: 'a cancelled preparation never opens the sheet',
    );
    expect(
      await preparedFiles(tester),
      isEmpty,
      reason: 'a cancelled transfer publishes nothing',
    );
  });
}
