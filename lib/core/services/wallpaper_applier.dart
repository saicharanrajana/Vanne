import 'dart:io';

import 'package:async_wallpaper/async_wallpaper.dart' as plugin;

/// Applies wallpapers through `async_wallpaper` — no manual platform
/// channels. The source must be a local file; callers download the image
/// to a temp file first (see [DownloadService] for the gallery flow).
///
/// Note: pinned to async_wallpaper 3.1.0 — the 3.2.0 release ships
/// non-compiling Kotlin in its Android implementation.
final class WallpaperApplier {
  /// Applies [file] as home/lock/both wallpaper.
  ///
  /// Returns a user-facing message describing the truthful outcome:
  /// success, failure, or unsupported operation.
  Future<ApplyOutcome> apply({
    required File file,
    required ApplyTarget target,
  }) async {
    final result = await plugin.AsyncWallpaper.setWallpaper(
      plugin.WallpaperRequest(
        target: switch (target) {
          ApplyTarget.home => plugin.WallpaperTarget.home,
          ApplyTarget.lock => plugin.WallpaperTarget.lock,
          ApplyTarget.both => plugin.WallpaperTarget.both,
        },
        sourceType: plugin.WallpaperSourceType.file,
        source: file.path,
      ),
    );

    if (result.isSuccess) {
      return const ApplyOutcome.success();
    }
    final error = result.error;
    return ApplyOutcome.failure(switch (error?.code) {
      plugin.WallpaperErrorCode.unsupported =>
        'This device does not support setting that wallpaper.',
      _ => error?.message ?? 'Could not set the wallpaper.',
    });
  }
}

/// Which display(s) the wallpaper should be applied to.
enum ApplyTarget { home, lock, both }

/// Outcome of an apply operation.
final class ApplyOutcome {
  final ApplyStatus status;

  /// Human-readable failure description; empty on success.
  final String message;

  const ApplyOutcome._(this.status, this.message);

  const ApplyOutcome.success() : this._(ApplyStatus.applied, '');

  factory ApplyOutcome.failure(String message) =>
      ApplyOutcome._(ApplyStatus.failed, message);
}

enum ApplyStatus { applied, failed }
