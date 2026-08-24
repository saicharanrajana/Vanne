import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Which display(s) the wallpaper should be applied to.
enum WallpaperTarget { home, lock, both }

/// Structured error codes from native side.
enum WallpaperErrorCode {
  unsupported,
  fileNotFound,
  security,
  io,
  invalidArgs,
  unknown,
}

sealed class WallpaperResult {
  const WallpaperResult();
}

class WallpaperSuccess extends WallpaperResult {
  const WallpaperSuccess();
}

class WallpaperFailure extends WallpaperResult {
  final WallpaperErrorCode code;
  final String message;

  const WallpaperFailure(this.code, this.message);
}

class SystemWallpaperPlatform {
  static const MethodChannel _channel = MethodChannel('system_wallpaper');

  @visibleForTesting
  static MethodChannel get channel => _channel;

  Future<WallpaperResult> setWallpaper({
    required String filePath,
    required WallpaperTarget target,
  }) async {
    if (filePath.isEmpty) {
      return const WallpaperFailure(
        WallpaperErrorCode.invalidArgs,
        'File path is empty.',
      );
    }
    try {
      await _channel.invokeMethod('setWallpaper', {
        'path': filePath,
        'target': target.name,
      });
      return const WallpaperSuccess();
    } on PlatformException catch (e) {
      return WallpaperFailure(
        _codeFromString(e.code),
        e.message ?? 'Could not set wallpaper.',
      );
    }
  }

  /// Launches system picker via ACTION_ATTACH_DATA + FLAG_GRANT_READ_URI_PERMISSION
  /// (Google Photos parity). Falls back to getCropAndSetWallpaperIntent on ROMs
  /// that lack ATTACH_DATA handler.
  Future<WallpaperResult> setWithSystemPicker({
    required String filePath,
  }) async {
    if (filePath.isEmpty) {
      return const WallpaperFailure(
        WallpaperErrorCode.invalidArgs,
        'File path is empty.',
      );
    }
    try {
      await _channel.invokeMethod('setWithSystemPicker', {'path': filePath});
      return const WallpaperSuccess();
    } on PlatformException catch (e) {
      return WallpaperFailure(
        _codeFromString(e.code),
        e.message ?? 'Could not open system picker.',
      );
    }
  }

  static WallpaperErrorCode _codeFromString(String code) {
    return switch (code) {
      'unsupported' => WallpaperErrorCode.unsupported,
      'fileNotFound' => WallpaperErrorCode.fileNotFound,
      'security' => WallpaperErrorCode.security,
      'io' => WallpaperErrorCode.io,
      'invalidArgs' => WallpaperErrorCode.invalidArgs,
      _ => WallpaperErrorCode.unknown,
    };
  }
}
