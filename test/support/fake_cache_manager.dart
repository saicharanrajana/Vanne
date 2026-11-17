import 'dart:async';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Cache manager for widget tests: fetches straight from the (mocked)
/// [io.HttpClient] and never persists anything, so `flutter_cache_manager`'s
/// backing store is never created.
///
/// Why not the real `DefaultCacheManager`: its store schedules a one-shot
/// cleanup [Timer] (10s) whenever a cached image is first resolved, and
/// whether that timer lands inside the tests' fake-async zone before teardown
/// is machine-speed dependent — locally the suite is green, while the 2-core
/// CI runner reliably leaves the timer pending ("A Timer is still pending even
/// after the widget tree was disposed") in every test that renders an image.
final class FakeCacheManager implements BaseCacheManager {
  @override
  Stream<FileResponse> getFileStream(
    String url, {
    String? key,
    Map<String, String>? headers,
    bool withProgress = false,
  }) {
    final controller = StreamController<FileResponse>();
    () async {
      io.HttpClient? client;
      try {
        final uri = Uri.parse(url);
        client = io.HttpClient();
        final request = await client.getUrl(uri);
        headers?.forEach(request.headers.add);
        final response = await request.close();
        if (response.statusCode >= 400) {
          throw io.HttpException(
            'image fetch failed: ${response.statusCode}',
            uri: uri,
          );
        }
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
        }
        final file = await _writeTempFile(bytes, '.img');
        if (withProgress) {
          controller.add(DownloadProgress(url, bytes.length, bytes.length));
        }
        controller.add(_fileInfo(file, url));
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      } finally {
        client?.close(force: true);
        await controller.close();
      }
    }();
    return controller.stream;
  }

  @override
  Future<File> getSingleFile(
    String url, {
    String key = 'unused',
    Map<String, String> headers = const {},
  }) async {
    final info = await downloadFile(url, authHeaders: headers);
    return info.file;
  }

  @override
  Future<FileInfo> downloadFile(
    String url, {
    String? key,
    Map<String, String>? authHeaders,
    bool force = false,
  }) async {
    final response = await getFileStream(
      url,
      key: key,
      headers: authHeaders,
    ).firstWhere((r) => r is FileInfo);
    return response as FileInfo;
  }

  @override
  Stream<FileInfo> getFile(
    String url, {
    String key = 'unused',
    Map<String, String> headers = const {},
  }) async* {
    await for (final response in getFileStream(url, key: key, headers: headers)) {
      if (response is FileInfo) yield response;
    }
  }

  @override
  Future<FileInfo?> getFileFromCache(String key, {bool ignoreMemCache = false}) async {
    return null;
  }

  @override
  Future<FileInfo?> getFileFromMemory(String key) async {
    return null;
  }

  @override
  Future<File> putFile(
    String url,
    Uint8List fileBytes, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) {
    return _writeTempFile(fileBytes, '.$fileExtension');
  }

  @override
  Future<File> putFileStream(
    String url,
    Stream<List<int>> source, {
    String? key,
    String? eTag,
    Duration maxAge = const Duration(days: 30),
    String fileExtension = 'file',
  }) async {
    final bytes = <int>[];
    await for (final chunk in source) {
      bytes.addAll(chunk);
    }
    return _writeTempFile(bytes, '.$fileExtension');
  }

  @override
  Future<void> removeFile(String key) async {}

  @override
  Future<void> emptyCache() async {}

  @override
  Future<void> dispose() async {}

  Future<File> _writeTempFile(List<int> bytes, String suffix) async {
    final directory = await io.Directory.systemTemp.createTemp('fake-cache-');
    return LocalFileSystem()
        .file('${directory.path}${io.Platform.pathSeparator}image$suffix')
        .writeAsBytes(bytes);
  }

  FileInfo _fileInfo(File file, String url) {
    return FileInfo(
      file,
      FileSource.Online,
      DateTime.now().add(const Duration(days: 30)),
      url,
    );
  }
}
