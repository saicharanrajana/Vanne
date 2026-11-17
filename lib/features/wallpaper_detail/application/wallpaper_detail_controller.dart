import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:path_provider/path_provider.dart';
import 'package:signals/signals.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../core/downloads/download_service.dart';
import '../../../core/services/wallpaper_applier.dart';
import '../../../core/wallpaper/wallpaper_repository.dart';

/// Owns one wallpaper-detail screen: optional detail fetch, download
/// progress, and apply-wallpaper outcomes.
///
/// New flow: "Set" first resolves a local file (with wavy indicator), then
/// poses 4 options (home/lock/both/Crop and set system picker via ATTACH_DATA).
final class WallpaperDetailController {
  final WallpaperRepository _repository;
  final DownloadService _downloader;
  final WallpaperApplier _applier;

  /// The wallpaper being shown. Starts from whatever the grid already
  /// knows; enriched once `/w/{id}` responds.
  final Signal<Wallpaper> wallpaper;

  /// Full metadata (uploader, tags) when the listing entry lacked them.
  final details = signal<Wallpaper?>(null);

  /// Detail-fetch failure; the screen still renders listing data.
  final detailsError = signal<String?>(null);

  /// Download lifecycle for the action row.
  final download = signal(const DownloadState.idle());

  /// Preparation lifecycle for the "Set" flow (download to tmp before sheet).
  final prepare = signal(const PrepareState.idle());

  /// Apply-wallpaper lifecycle for the Set sheet (home/lock/both/Crop and set).
  final apply = signal(const ApplyState.idle());

  /// Cache path produced by a previous "Set" attempt, reused when valid.
  String? _cachedTempPath;

  /// Cancels in-flight transfers when the screen is popped mid-download.
  final CancelToken _lifecycle = CancelToken();

  /// Set by [dispose]; guards signal writes from in-flight operations.
  bool _disposed = false;

  WallpaperDetailController({
    required Wallpaper initial,
    required this._repository,
    required this._downloader,
    required this._applier,
  }) : wallpaper = signal(initial);

  /// Fetches uploader/tags when missing. Silent on failure — the screen
  /// degrades gracefully to listing-level information.
  Future<void> loadDetails() async {
    if (wallpaper.value.hasDetails || detailsError.value != null) return;
    try {
      final full = await _repository.wallpaperDetails(wallpaper.value.id);
      if (_disposed) return;
      details.set(full);
      wallpaper.set(full);
    } on WallhavenUserException catch (error) {
      if (_disposed) return;
      detailsError.set(error.message);
    } catch (_) {
      // An untyped failure must not escape into the zone: the screen would
      // keep its listing data but never learn that details are unavailable.
      if (_disposed) return;
      detailsError.set('Could not load wallpaper details.');
    }
  }

  /// Folder that receives downloads, phrased for display, e.g.
  /// `Pictures/VanneWallpapers` or `<picked parent>/VanneWallpapers`.
  String get downloadFolderPath => _downloader.destinationFolderPath;

  /// Downloads the full-resolution file into the user's download folder.
  Future<void> saveDownload() async {
    if (download.value.isBusy) return;
    download.set(const DownloadState.downloading());
    try {
      final savedPath = await _downloader.saveDownload(
        wallpaper.value,
        onProgress: (progress) {
          if (!_disposed) download.set(DownloadState.downloading(progress));
        },
        cancelToken: _lifecycle,
      );
      if (_disposed) return;
      download.set(DownloadState.done(folderPath: savedPath));
    } on DownloadException catch (error) {
      if (_disposed) return; // screen gone — nothing left to report to
      download.set(DownloadState.failed(error.message));
    }
  }

  /// Resolves a local cache file for the "Set" flow, showing wavy progress
  /// until ready. Cached path is reused across all 4 options.
  ///
  /// Call this *before* opening the sheet. On success returns the path and
  /// sets [prepare] to ready; on failure sets error and throws.
  Future<String> prepareForSet() async {
    if (prepare.value.isResolving) {
      final cached = _cachedTempPath;
      if (cached != null && File(cached).existsSync()) return cached;
      // Already resolving without a valid cache — avoid spawning a second
      // concurrent download; return existing path or let caller retry.
      if (_cachedTempPath != null) return _cachedTempPath!;
      throw const DownloadException('Wallpaper is already being prepared.');
    }
    prepare.set(const PrepareState.resolving());
    try {
      final path = await _ensureLocalFile();
      if (_disposed) return path;
      prepare.set(PrepareState.ready(path));
      return path;
    } on DownloadException catch (error) {
      if (_disposed) rethrow;
      prepare.set(PrepareState.failed(error.message));
      rethrow;
    } on FileSystemException {
      if (_disposed) rethrow;
      // The cached file is unusable (deleted or truncated outside the app):
      // drop the path so the next attempt downloads a fresh copy.
      _cachedTempPath = null;
      const msg = 'Could not prepare the wallpaper file.';
      prepare.set(const PrepareState.failed(msg));
      throw const DownloadException(msg);
    }
  }

  /// Applies the wallpaper to home/lock/both.
  ///
  /// Assumes [prepareForSet] already succeeded (reuses cached file). Falls
  /// back to ensuring the file if called directly.
  Future<void> applyAsWallpaper(ApplyTarget target) async {
    if (apply.value.isBusy) return;
    apply.set(ApplyState.applying(target));
    try {
      final file = File(await _ensureLocalFile());
      final outcome = await _applier.apply(file: file, target: target);
      if (_disposed) return;
      apply.set(ApplyState.fromOutcome(outcome));
    } on DownloadException catch (error) {
      if (_disposed) return;
      apply.set(ApplyState.failed(error.message));
    } on FileSystemException {
      if (_disposed) return;
      _cachedTempPath = null;
      apply.set(ApplyState.failed('Could not prepare the wallpaper file.'));
    }
  }

  /// Launches system picker via ACTION_ATTACH_DATA (Google Photos parity).
  /// Requires a cached file (call [prepareForSet] first for the intended UX).
  Future<void> setWithSystemPicker() async {
    if (apply.value.isBusy) return;
    apply.set(const ApplyState.applyingSystemPicker());
    try {
      final file = File(await _ensureLocalFile());
      final outcome = await _applier.setWithSystemPicker(file: file);
      if (_disposed) return;
      apply.set(ApplyState.fromOutcome(outcome));
    } on DownloadException catch (error) {
      if (_disposed) return;
      apply.set(ApplyState.failed(error.message));
    } on FileSystemException {
      if (_disposed) return;
      _cachedTempPath = null;
      apply.set(ApplyState.failed('Could not prepare the wallpaper file.'));
    }
  }

  /// Directory holding images prepared by "Set", under a cache root.
  ///
  /// Versioned on purpose: an older build wrote straight to
  /// `wallpaper_apply/<file>` and could leave a truncated prefix behind after a
  /// killed transfer. Moving the folder means those files are ignored rather
  /// than inspected, and the OS reclaims them as cache. Anything this build
  /// publishes here is whole — [DownloadService.downloadToFile] renames it into
  /// place only after the transfer completes.
  static Directory wallpaperApplyDir(Directory base) =>
      Directory('${base.path}/wallpaper_apply/v2');

  Future<String> _ensureLocalFile() async {
    final cached = _cachedTempPath;
    if (cached != null && File(cached).existsSync()) return cached;

    // Use app cache dir (covered by FileProvider cache-path), not
    // Directory.systemTemp which on Android is code_cache and not
    // covered by default FileProvider paths (see screenshot error:
    // "Failed to find configured root that contains .../code_cache/...").
    // Fall back to systemTemp for tests where path_provider isn't mocked.
    Directory base;
    try {
      base = await getTemporaryDirectory();
    } on Exception {
      base = Directory.systemTemp;
    } on Error {
      base = Directory.systemTemp;
    }
    final dir = await wallpaperApplyDir(base).create(recursive: true);
    final target = File(
      '${dir.path}/${DownloadService.fileNameFor(wallpaper.value)}',
    );
    // Reuse a file prepared earlier (e.g. a previous option in the sheet).
    if (await target.exists() && await target.length() > 0) {
      _cachedTempPath = target.path;
      return target.path;
    }

    await _downloader.downloadToFile(
      wallpaper.value,
      target,
      cancelToken: _lifecycle,
    );
    _cachedTempPath = target.path;
    return target.path;
  }

  /// Releases reactive resources when leaving the screen and cancels any
  /// in-flight transfer so no signal is written after disposal.
  void dispose() {
    _disposed = true;
    _lifecycle.cancel();
    download.dispose();
    prepare.dispose();
    apply.dispose();
    details.dispose();
    detailsError.dispose();
    wallpaper.dispose();
  }
}

/// Download button state machine.
final class DownloadState {
  final bool isBusy;
  final double? progress;
  final String? error;
  final bool done;

  /// Folder the file was actually written to, snapshotted when the write
  /// started. Set only on success; the live Settings destination may differ by
  /// the time the transfer finishes.
  final String? folderPath;

  const DownloadState({
    required this.isBusy,
    this.progress,
    this.error,
    this.done = false,
    this.folderPath,
  });

  const DownloadState.idle() : this(isBusy: false);

  const DownloadState.downloading([this.progress])
    : isBusy = true,
      error = null,
      done = false,
      folderPath = null;

  const DownloadState.done({this.folderPath})
    : isBusy = false,
      progress = null,
      error = null,
      done = true;

  factory DownloadState.failed(String message) =>
      DownloadState(isBusy: false, error: message);
}

/// Preparation state for the "Set" flow (resolve file before showing sheet).
final class PrepareState {
  final bool isResolving;
  final String? path;
  final String? error;

  const PrepareState({required this.isResolving, this.path, this.error});

  const PrepareState.idle() : this(isResolving: false);

  const PrepareState.resolving()
    : isResolving = true,
      path = null,
      error = null;

  const PrepareState.ready(this.path) : isResolving = false, error = null;

  const PrepareState.failed(this.error) : isResolving = false, path = null;
}

/// Apply-sheet state machine.
final class ApplyState {
  final bool isBusy;
  final ApplyTarget? target;
  final bool isSystemPicker;
  final String? error;
  final bool succeeded;

  const ApplyState({
    required this.isBusy,
    this.target,
    this.isSystemPicker = false,
    this.error,
    this.succeeded = false,
  });

  const ApplyState.idle() : this(isBusy: false);

  const ApplyState.applying(this.target)
    : isBusy = true,
      error = null,
      succeeded = false,
      isSystemPicker = false;

  const ApplyState.applyingSystemPicker()
    : isBusy = true,
      target = null,
      error = null,
      succeeded = false,
      isSystemPicker = true;

  const ApplyState.success()
    : isBusy = false,
      target = null,
      error = null,
      succeeded = true,
      isSystemPicker = false;

  factory ApplyState.failed(String message) =>
      ApplyState(isBusy: false, error: message);

  factory ApplyState.fromOutcome(ApplyOutcome outcome) => switch (outcome) {
    ApplyOutcome(status: ApplyStatus.applied) => const ApplyState.success(),
    ApplyOutcome(:final message) => ApplyState.failed(message),
  };
}
