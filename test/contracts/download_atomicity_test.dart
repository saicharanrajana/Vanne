// Contract: a cached image is either complete or absent.
//
// "Set wallpaper" reuses a cache file between attempts, and the cache path is
// derived from the wallpaper id. Before this contract, the download wrote
// straight into that deterministic path and reuse checked only `length > 0`.
// A process killed mid-transfer therefore left a truncated file that looked
// usable, and every later attempt handed broken bytes to the wallpaper
// service instead of repairing the cache.
//
// What is protected:
//  - the transfer writes to a unique `.part` file and only a complete file is
//    renamed into the cache, so a kill/cancel/failure publishes nothing,
//  - a failed or cancelled attempt leaves no file behind for the next run,
//  - two controllers preparing the same wallpaper keep separate scratch files,
//  - a stalled transport fails with a bounded, user-facing message and the
//    retry downloads a fresh copy.

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vanne/core/downloads/download_service.dart';
import 'package:vanne/core/services/wallpaper_applier.dart';
import 'package:vanne/core/wallpaper/wallpaper_repository.dart';
import 'package:vanne/features/wallpaper_detail/application/wallpaper_detail_controller.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../support/fake_platform.dart';

/// Transport the test fully controls: it decides what bytes (if any) land and
/// how the transfer ends.
final class _ScriptedDio implements Dio {
  _ScriptedDio(this.write);

  /// Called for every download; [dio] is passed so a handler can read
  /// [downloads].
  Future<void> Function(String path, _ScriptedDio dio) write;

  final downloads = <String>[];

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
    final path = savePath as String;
    downloads.add(path);
    await write(path, this);
    onReceiveProgress?.call(1, 1);
    return Response<dynamic>(
      requestOptions: RequestOptions(path: urlPath),
      statusCode: 200,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Only the detail controller's download path is exercised here.
final class _StubRepository implements WallpaperRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Wallpaper _wallpaper() => Wallpaper(
  id: 'atomic-fixture',
  url: 'https://wallhaven.cc/w/atomic-fixture',
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
  path: 'https://example.invalid/atomic-fixture.jpg',
  thumbnails: const Thumbnails(),
);

Future<void> _writeBytes(String path, List<int> bytes) async {
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes);
}

DioException _dioFailure(DioExceptionType type) => DioException(
  requestOptions: RequestOptions(path: 'https://example.invalid/x.jpg'),
  type: type,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory cacheDir;
  WallpaperDetailController? controller;

  WallpaperDetailController controllerFor(Dio dio) {
    final service = DownloadService(
      dio: dio,
      platform: FakeDownloadStoragePlatform(),
    );
    return WallpaperDetailController(
      initial: _wallpaper(),
      repository: _StubRepository(),
      downloader: service,
      applier: WallpaperApplier(platform: FakeWallpaperPlatform()),
    );
  }

  /// The folder the app publishes reusable cache images into. Resolved through
  /// production code so this contract cannot drift from the layout it guards.
  Directory applyDir() => WallpaperDetailController.wallpaperApplyDir(cacheDir);

  List<File> leftovers() {
    final dir = applyDir();
    if (!dir.existsSync()) return const [];
    return dir.listSync().whereType<File>().toList();
  }

  File finalFile() =>
      File('${applyDir().path}/${DownloadService.fileNameFor(_wallpaper())}');

  setUp(() async {
    cacheDir = Directory.systemTemp.createTempSync('vanne_atomic_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async =>
              call.method == 'getTemporaryDirectory' ? cacheDir.path : null,
        );
  });

  tearDown(() async {
    controller?.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (cacheDir.existsSync()) cacheDir.deleteSync(recursive: true);
  });

  test(
    'a failed transfer publishes nothing and the retry repairs it',
    () async {
      final dio = _ScriptedDio((path, dio) async {
        // Half a file, then the connection dies — the state a process kill
        // leaves in the old direct-write path.
        await _writeBytes(path, const [1, 2, 3]);
        throw _dioFailure(DioExceptionType.connectionError);
      });
      final detail = controller = controllerFor(dio);

      await expectLater(
        detail.prepareForSet(),
        throwsA(
          isA<DownloadException>().having(
            (error) => error.message,
            'message',
            'Network unavailable. Check your connection.',
          ),
        ),
      );

      expect(detail.prepare.value.error, isNotNull);
      expect(finalFile().existsSync(), isFalse, reason: 'nothing published');
      expect(leftovers(), isEmpty, reason: 'the scratch file is cleaned up');

      dio.write = (path, dio) async => _writeBytes(path, const [9, 9, 9, 9]);
      final path = await detail.prepareForSet();

      expect(path, finalFile().path);
      expect(File(path).readAsBytesSync(), [9, 9, 9, 9]);
      expect(dio.downloads, hasLength(2), reason: 'the retry re-downloaded');
      expect(leftovers().map((file) => file.path), [
        finalFile().path,
      ], reason: 'exactly the complete file remains');
    },
  );

  test('a cancelled transfer leaves no cache file behind', () async {
    final dio = _ScriptedDio((path, dio) async {
      await _writeBytes(path, const [4, 4]);
      throw _dioFailure(DioExceptionType.cancel);
    });
    final detail = controller = controllerFor(dio);

    await expectLater(
      detail.prepareForSet(),
      throwsA(
        isA<DownloadException>().having(
          (error) => error.message,
          'message',
          'Download cancelled.',
        ),
      ),
    );

    expect(finalFile().existsSync(), isFalse);
    expect(leftovers(), isEmpty, reason: 'a cancelled attempt caches nothing');
  });

  test('an empty 200 response is not treated as a wallpaper', () async {
    final dio = _ScriptedDio((path, dio) => _writeBytes(path, const []));
    final detail = controller = controllerFor(dio);

    await expectLater(
      detail.prepareForSet(),
      throwsA(
        isA<DownloadException>().having(
          (error) => error.message,
          'message',
          'Download failed. Please try again.',
        ),
      ),
    );

    expect(finalFile().existsSync(), isFalse);
    expect(leftovers(), isEmpty);
  });

  test(
    'a filesystem failure publishing a completed transfer is retryable',
    () async {
      final dio = _ScriptedDio(
        (path, dio) => _writeBytes(path, const [1, 2, 3, 4]),
      );
      final service = DownloadService(dio: dio);
      final destination = Directory('${cacheDir.path}/already-a-directory');
      await destination.create();

      await expectLater(
        service.downloadToFile(_wallpaper(), File(destination.path)),
        throwsA(
          isA<DownloadException>().having(
            (error) => error.message,
            'message',
            'Download failed. Please try again.',
          ),
        ),
      );

      expect(destination.existsSync(), isTrue);
      expect(
        cacheDir.listSync().whereType<File>().map((file) => file.path),
        isEmpty,
        reason: 'failed publication removes the downloaded scratch file',
      );
    },
  );

  test('two prepares of one wallpaper keep separate scratch files', () async {
    final gate = Completer<void>();
    final dio = _ScriptedDio((path, dio) async {
      if (dio.downloads.length == 1) await gate.future;
      await _writeBytes(path, [dio.downloads.length, 0, 0]);
    });
    final first = controllerFor(dio);
    final second = controllerFor(dio);
    addTearDown(first.dispose);

    final firstPath = first.prepareForSet();
    // Wait until the first transfer is genuinely inside its scratch write.
    while (dio.downloads.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final firstScratch = dio.downloads.single;
    final secondPath = await second.prepareForSet();
    gate.complete();
    await firstPath;

    expect(dio.downloads, hasLength(2));
    expect(
      dio.downloads[0],
      isNot(dio.downloads[1]),
      reason: 'one scratch path would let one transfer clobber the other',
    );
    expect(secondPath, finalFile().path);
    expect(
      File(secondPath).readAsBytesSync(),
      hasLength(3),
      reason: 'the surviving cache file is a whole transfer, never a mix',
    );
    expect(leftovers().map((file) => file.path), [
      finalFile().path,
    ], reason: 'both scratch files are gone');
    expect(
      File(firstScratch).existsSync(),
      isFalse,
      reason: 'the losing transfer never survives as a cache file',
    );
  });

  group('transport timeouts', () {
    test('a stalled receive fails fast with an actionable message', () async {
      final dio = _ScriptedDio(
        (path, dio) async => throw _dioFailure(DioExceptionType.receiveTimeout),
      );
      final detail = controller = controllerFor(dio);

      await expectLater(
        detail.prepareForSet(),
        throwsA(
          isA<DownloadException>().having(
            (error) => error.message,
            'message',
            'The download stalled. Please try again.',
          ),
        ),
      );

      // The screen shows this instead of an indefinite spinner, and the retry
      // is a plain download attempt.
      expect(
        detail.prepare.value.error,
        'The download stalled. Please try again.',
      );
      dio.write = (path, dio) async => _writeBytes(path, const [7]);
      expect(await detail.prepareForSet(), finalFile().path);
    });

    test('a connection timeout reads as network unavailability', () async {
      final dio = _ScriptedDio(
        (path, dio) async =>
            throw _dioFailure(DioExceptionType.connectionTimeout),
      );
      final detail = controller = controllerFor(dio);

      await expectLater(
        detail.prepareForSet(),
        throwsA(
          isA<DownloadException>().having(
            (error) => error.message,
            'message',
            'Network unavailable. Check your connection.',
          ),
        ),
      );
    });

    test('a failed wallpaper save reports the same bounded failure', () async {
      final dio = _ScriptedDio(
        (path, dio) async => throw _dioFailure(DioExceptionType.receiveTimeout),
      );
      final detail = controller = controllerFor(dio);

      await detail.saveDownload();

      expect(
        detail.download.value.error,
        'The download stalled. Please try again.',
      );
      expect(detail.download.value.isBusy, isFalse);
      expect(cacheDir.listSync(), isEmpty, reason: 'no scratch leak');
    });
  });
}
