import 'dart:io';

import 'package:system_wallpaper/system_wallpaper.dart';

/// Applies wallpapers through first-party `system_wallpaper` plugin.
///
/// Three direct targets (home/lock/both) use `WallpaperManager.setStream` off
/// the main thread. The fourth option delegates to the system picker via
/// `getCropAndSetWallpaperIntent` (primary) + `ACTION_ATTACH_DATA` fallback
/// with `FLAG_GRANT_READ_URI_PERMISSION` so the OEM crop/palette UI handles
/// the rest.
final class WallpaperApplier {
  final SystemWallpaperPlatform _platform;

  WallpaperApplier({SystemWallpaperPlatform? platform})
      : _platform = platform ?? SystemWallpaperPlatform();

  /// Applies [file] as home/lock/both wallpaper via `setStream`.
  Future<ApplyOutcome> apply({
    required File file,
    required ApplyTarget target,
  }) async {
    final result = await _platform.setWallpaper(
      filePath: file.path,
      target: switch (target) {
        ApplyTarget.home => WallpaperTarget.home,
        ApplyTarget.lock => WallpaperTarget.lock,
        ApplyTarget.both => WallpaperTarget.both,
      },
    );

    return switch (result) {
      WallpaperSuccess() => const ApplyOutcome.success(),
      WallpaperFailure(:final code, :final message) =>
        ApplyOutcome.failure(_messageFor(code, message)),
    };
  }

  /// Launches system picker (ATTACH_DATA + fallback to getCropAndSetWallpaperIntent).
  /// Returns success if an activity resolved; failure with user-facing message otherwise.
  Future<ApplyOutcome> setWithSystemPicker({required File file}) async {
    final result = await _platform.setWithSystemPicker(filePath: file.path);
    return switch (result) {
      WallpaperSuccess() => const ApplyOutcome.success(),
      WallpaperFailure(:final code, :final message) =>
        ApplyOutcome.failure(_messageFor(code, message)),
    };
  }

  String _messageFor(WallpaperErrorCode code, String message) {
    return switch (code) {
      WallpaperErrorCode.unsupported =>
        'No app found to handle this wallpaper action.',
      WallpaperErrorCode.fileNotFound => 'Wallpaper file not found.',
      WallpaperErrorCode.security =>
        'System denied access to set the wallpaper.',
      WallpaperErrorCode.io => message.isNotEmpty
          ? message
          : 'Storage error while setting the wallpaper.',
      WallpaperErrorCode.invalidArgs => message,
      _ => message.isNotEmpty ? message : 'Could not set the wallpaper.',
    };
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
