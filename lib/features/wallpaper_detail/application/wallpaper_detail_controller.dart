import 'dart:io';

import 'package:dio/dio.dart' show CancelToken;
import 'package:signals/signals.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../../../core/downloads/download_service.dart';
import '../../../core/services/wallpaper_applier.dart';
import '../../../core/wallpaper/wallpaper_repository.dart';

/// Owns one wallpaper-detail screen: optional detail fetch, download
/// progress, and apply-wallpaper outcomes.
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

  /// Apply-wallpaper lifecycle for the Set sheet.
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
      details.set(full);
      wallpaper.set(full);
    } on WallhavenUserException catch (error) {
      detailsError.set(error.message);
    }
  }

  /// Downloads the full-resolution file into the device gallery.
  Future<void> downloadToGallery() async {
    if (download.value.isBusy) return;
    download.set(const DownloadState.downloading());
    try {
      await _downloader.saveToGallery(
        wallpaper.value,
        onProgress: (progress) {
          if (!_disposed) download.set(DownloadState.downloading(progress));
        },
        cancelToken: _lifecycle,
      );
      if (_disposed) return;
      download.set(const DownloadState.done());
    } on DownloadException catch (error) {
      if (_disposed) return; // screen gone — nothing left to report to
      download.set(DownloadState.failed(error.message));
    }
  }

  /// Applies the wallpaper to home/lock/both.
  ///
  /// async_wallpaper requires a local file, so this ensures a cache copy
  /// first (reused across targets within the session).
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
      apply.set(ApplyState.failed('Could not prepare the wallpaper file.'));
    }
  }

  Future<String> _ensureLocalFile() async {
    final cached = _cachedTempPath;
    if (cached != null && File(cached).existsSync()) return cached;

    final dir = await Directory.systemTemp.createTemp('wallpaper_apply');
    final file = File(
      '${dir.path}/${DownloadService.fileNameFor(wallpaper.value)}',
    );
    await _downloader.downloadToFile(
      wallpaper.value,
      file,
      cancelToken: _lifecycle,
    );
    _cachedTempPath = file.path;
    return file.path;
  }

  /// Releases reactive resources when leaving the screen and cancels any
  /// in-flight transfer so no signal is written after disposal.
  void dispose() {
    _disposed = true;
    _lifecycle.cancel();
    download.dispose();
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

  const DownloadState({
    required this.isBusy,
    this.progress,
    this.error,
    this.done = false,
  });

  const DownloadState.idle() : this(isBusy: false);

  const DownloadState.downloading([this.progress])
    : isBusy = true,
      error = null,
      done = false;

  const DownloadState.done()
    : isBusy = false,
      progress = null,
      error = null,
      done = true;

  factory DownloadState.failed(String message) =>
      DownloadState(isBusy: false, error: message);
}

/// Apply-sheet state machine.
final class ApplyState {
  final bool isBusy;
  final ApplyTarget? target;
  final String? error;
  final bool succeeded;

  const ApplyState({
    required this.isBusy,
    this.target,
    this.error,
    this.succeeded = false,
  });

  const ApplyState.idle() : this(isBusy: false);

  const ApplyState.applying(this.target)
    : isBusy = true,
      error = null,
      succeeded = false;

  const ApplyState.success()
    : isBusy = false,
      target = null,
      error = null,
      succeeded = true;

  factory ApplyState.failed(String message) =>
      ApplyState(isBusy: false, error: message);

  factory ApplyState.fromOutcome(ApplyOutcome outcome) => switch (outcome) {
    ApplyOutcome(status: ApplyStatus.applied) => const ApplyState.success(),
    ApplyOutcome(:final message) => ApplyState.failed(message),
  };
}
