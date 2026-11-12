// Contract: each save owns its own scratch files.
//
// A save is "download to a cache file, then hand the path to the platform".
// Two detail routes (or a retry after a slow first attempt) can save the same
// wallpaper at the same time. If both used the same cache path, one transfer
// would overwrite the other and either cleanup would delete the file the other
// is still copying — a silently corrupt or failed save.
//
// What is protected:
//  - concurrent saves of one wallpaper use distinct source files, so a
//    finished save never deletes or overwrites an in-flight one,
//  - scratch files are deleted after success, after a platform failure, and
//    after a transfer failure (no cache leak),
//  - the platform still receives the wallpaper's deterministic filename.

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_wallpaper/system_wallpaper.dart';
import 'package:vanne/core/downloads/download_service.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

/// Writes fixture bytes to the requested path; each transfer gets its own
/// byte value so a test can prove nothing was overwritten.
final class _FixtureDio implements Dio {
  final downloads = <String>[];

  Object? failure;

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
    if (failure != null) throw failure!;
    final bytes = [downloads.length, downloads.length, downloads.length];
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    onReceiveProgress?.call(bytes.length, bytes.length);
    return Response<dynamic>(
      requestOptions: RequestOptions(path: urlPath),
      statusCode: 200,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records what the platform was handed and can hold a copy open.
final class _RecordingStoragePlatform extends DownloadStoragePlatform {
  _RecordingStoragePlatform({
    this.result = const DownloadSaveSuccess('content://mock/saved'),
  });

  final DownloadSaveResult result;

  final sourcePaths = <String>[];

  /// Which bytes were visible when the copy was requested.
  final sourceBytes = <List<int>>[];

  /// Consumed in call order; lets a test keep one copy in flight.
  final copyGates = <Completer<void>>[];

  @override
  Future<DownloadSaveResult> saveDownload({
    required String sourcePath,
    required String folderName,
    required String mimeType,
    String? treeUri,
  }) async {
    final file = File(sourcePath);
    sourcePaths.add(sourcePath);
    final exists = file.existsSync();
    sourceBytes.add(exists ? file.readAsBytesSync() : const <int>[]);
    if (copyGates.isNotEmpty) await copyGates.removeAt(0).future;
    return result;
  }
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory cacheDir;

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('vanne-download-cache');
    // The service asks path_provider for the cache root; that is the one
    // platform seam it uses besides the storage channel.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async =>
              call.method == 'getTemporaryDirectory' ? cacheDir.path : null,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (cacheDir.existsSync()) await cacheDir.delete(recursive: true);
  });

  /// Waits for [condition] in real time; plain `test()` bodies are not under
  /// fake async, so polling the fixture is deterministic enough.
  Future<void> waitFor(bool Function() condition, String description) async {
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('timed out waiting for $description');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('concurrent saves of one wallpaper never share a scratch file', () async {
    final dio = _FixtureDio();
    final platform = _RecordingStoragePlatform();
    final service = DownloadService(dio: dio, platform: platform);

    // Hold the first save inside the platform copy, after its transfer has
    // already written bytes to the cache.
    final slowCopy = Completer<void>();
    platform.copyGates.add(slowCopy);

    final first = service.saveDownload(_wallpaper());
    await waitFor(
      () => platform.sourcePaths.isNotEmpty,
      'the first platform copy',
    );
    final firstSource = platform.sourcePaths.first;

    // A second save of the same wallpaper runs end to end, cleanup included.
    await service.saveDownload(_wallpaper());

    expect(dio.downloads, hasLength(2));
    expect(
      dio.downloads[0],
      isNot(dio.downloads[1]),
      reason: 'sharing a path would corrupt or delete the other save',
    );
    expect(
      platform.sourceBytes.last,
      [2, 2, 2],
      reason: 'the finished save copied its own transfer',
    );
    expect(
      File(firstSource).existsSync(),
      isTrue,
      reason: 'the finished save must not delete the in-flight one',
    );
    expect(
      platform.sourceBytes.first,
      [1, 1, 1],
      reason: 'the in-flight transfer was never overwritten',
    );

    slowCopy.complete();
    await first;

    expect(platform.sourcePaths, hasLength(2));
    expect(
      platform.sourcePaths.first.split(Platform.pathSeparator).last,
      DownloadService.fileNameFor(_wallpaper()),
      reason: 'the platform still sees the wallpaper filename',
    );
    expect(
      cacheDir.listSync(),
      isEmpty,
      reason: 'every scratch directory is cleaned up',
    );
  });

  test('a failed platform copy still cleans up its scratch file', () async {
    final dio = _FixtureDio();
    final platform = _RecordingStoragePlatform(
      result: const DownloadSaveFailure(
        DownloadSaveErrorCode.io,
        'copy failed',
      ),
    );
    final service = DownloadService(dio: dio, platform: platform);

    await expectLater(
      service.saveDownload(_wallpaper()),
      throwsA(isA<DownloadException>()),
    );

    expect(platform.sourceBytes, [
      [1, 1, 1],
    ]);
    expect(cacheDir.listSync(), isEmpty, reason: 'no cache leak on failure');
  });

  test('a failed transfer leaves no scratch file behind', () async {
    final dio = _FixtureDio()
      ..failure = DioException(
        requestOptions: RequestOptions(path: 'https://example.invalid/x.jpg'),
        type: DioExceptionType.connectionError,
      );
    final service = DownloadService(
      dio: dio,
      platform: _RecordingStoragePlatform(),
    );

    await expectLater(
      service.saveDownload(_wallpaper()),
      throwsA(
        isA<DownloadException>().having(
          (error) => error.message,
          'message',
          'Network unavailable. Check your connection.',
        ),
      ),
    );

    expect(cacheDir.listSync(), isEmpty);
  });
}
