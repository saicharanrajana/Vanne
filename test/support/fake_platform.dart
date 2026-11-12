/// In-memory implementations of every platform boundary the app touches.
///
/// Widget tests replace the OS, never the app: controllers, repositories and
/// screens stay real, while storage channels, downloads, wallpaper applying
/// and external links are recorded fakes.
library;

import 'dart:async';

import 'package:system_wallpaper/system_wallpaper.dart';
import 'package:vanne/core/services/url_launcher_service.dart';

/// Scriptable `system_wallpaper` storage bridge.
// ignore: must_be_immutable
final class FakeDownloadStoragePlatform extends DownloadStoragePlatform {
  FakeDownloadStoragePlatform();

  final savedDownloads = <SavedDownload>[];
  final pickedParents = <String>[];
  final checkedParents = <String>[];
  final releasedParents = <String>[];

  /// Result returned by the next [saveDownload] calls.
  DownloadSaveResult saveResult = const DownloadSaveSuccess(
    'content://downloads/fixture',
  );

  /// Queued picker outcomes; the last one repeats.
  final pickResults = <ParentPickResult>[const ParentPickCanceled()];

  /// Grant state reported by [checkParent].
  ParentAccessResult checkResult = const ParentAccessAvailable('Downloads');

  /// When set, [saveDownload] waits for this before answering.
  Future<void>? saveGate;

  /// When set, [pickParent] resolves with this instead of [pickResults].
  Future<ParentPickResult>? pendingPick;

  @override
  Future<DownloadSaveResult> saveDownload({
    required String sourcePath,
    required String folderName,
    required String mimeType,
    String? treeUri,
  }) async {
    savedDownloads.add(
      SavedDownload(
        sourcePath: sourcePath,
        folderName: folderName,
        mimeType: mimeType,
        treeUri: treeUri,
      ),
    );
    final gate = saveGate;
    if (gate != null) await gate;
    return saveResult;
  }

  @override
  Future<ParentPickResult> pickParent() async {
    pickedParents.add('pickParent');
    final pending = pendingPick;
    if (pending != null) return pending;
    if (pickResults.length > 1) return pickResults.removeAt(0);
    return pickResults.last;
  }

  @override
  Future<ParentAccessResult> checkParent(String treeUri) async {
    checkedParents.add(treeUri);
    return checkResult;
  }

  @override
  Future<void> releaseParent(String treeUri) async {
    releasedParents.add(treeUri);
  }
}

final class SavedDownload {
  const SavedDownload({
    required this.sourcePath,
    required this.folderName,
    required this.mimeType,
    required this.treeUri,
  });

  final String sourcePath;
  final String folderName;
  final String mimeType;
  final String? treeUri;
}

/// Scriptable `system_wallpaper` apply bridge.
final class FakeWallpaperPlatform extends SystemWallpaperPlatform {
  final appliedTargets = <WallpaperTarget>[];
  final appliedPaths = <String>[];
  int systemPickerLaunches = 0;

  WallpaperResult result = const WallpaperSuccess();

  @override
  Future<WallpaperResult> setWallpaper({
    required String filePath,
    required WallpaperTarget target,
  }) async {
    appliedPaths.add(filePath);
    appliedTargets.add(target);
    return result;
  }

  @override
  Future<WallpaperResult> setWithSystemPicker({
    required String filePath,
  }) async {
    appliedPaths.add(filePath);
    systemPickerLaunches++;
    return result;
  }
}

/// Records external browser launches instead of leaving the app.
final class FakeUrlLauncher {
  final opened = <Uri>[];

  /// Set false to simulate "no browser available".
  bool succeeds = true;

  late final service = UrlLauncherService(
    launch: (uri) async {
      opened.add(uri);
      return succeeds;
    },
  );
}
