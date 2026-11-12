import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Failures a save can report, mapped from the native side.
enum DownloadSaveErrorCode {
  invalidArgs,
  noPermission,
  destinationUnavailable,
  noSpace,
  notFound,
  io,

  /// The platform explicitly rejected the file's format.
  ///
  /// Only produced when the native side names the format as the problem; it
  /// must never be inferred from a missing platform handler.
  unsupported,

  /// The `downloads.*` method is not implemented by this build/platform
  /// (no handler: a missing or stale native plugin).
  nativeUnavailable,

  unknown,
}

/// Outcome of writing one file to the device.
@immutable
sealed class DownloadSaveResult {
  const DownloadSaveResult();
}

final class DownloadSaveSuccess extends DownloadSaveResult {
  const DownloadSaveSuccess(this.uri);

  /// `content://` URI of the committed document.
  final String uri;
}

final class DownloadSaveFailure extends DownloadSaveResult {
  const DownloadSaveFailure(this.code, this.message);

  final DownloadSaveErrorCode code;
  final String message;
}

/// Outcome of the system folder picker.
@immutable
sealed class ParentPickResult {
  const ParentPickResult();
}

final class ParentPicked extends ParentPickResult {
  const ParentPicked({required this.treeUri, required this.label});

  /// Persistable tree URI returned by the picker.
  final String treeUri;

  /// Provider display name of the picked folder (not a filesystem path).
  final String label;
}

final class ParentPickCanceled extends ParentPickResult {
  const ParentPickCanceled();
}

final class ParentPickFailure extends ParentPickResult {
  const ParentPickFailure(this.code, this.message);

  /// `noActivity`, `busy`, `noWriteAccess`, or `unsupported`.
  final String code;
  final String message;
}

/// Whether a persisted tree URI still grants read+write access.
@immutable
sealed class ParentAccessResult {
  const ParentAccessResult();
}

final class ParentAccessAvailable extends ParentAccessResult {
  const ParentAccessAvailable(this.label);

  /// Current provider display name; the folder may have been renamed.
  final String label;
}

final class ParentAccessLost extends ParentAccessResult {
  const ParentAccessLost();

  /// The grant was revoked or the folder was moved/deleted.
}

final class ParentAccessUnknown extends ParentAccessResult {
  const ParentAccessUnknown(this.message);

  /// Platform error; callers keep the stored destination but must not write.
  final String message;
}

/// First-party Android storage bridge for downloads.
///
/// Two destinations, both permission-free for the user:
/// * default — MediaStore insert under `Pictures/<folderName>`;
/// * chosen — copy into a `documents://` tree the user explicitly granted.
@immutable
class DownloadStoragePlatform {
  const DownloadStoragePlatform({MethodChannel? channel})
    : _channel = channel ?? _defaultChannel;

  static const MethodChannel _defaultChannel = MethodChannel(
    'system_wallpaper',
  );

  final MethodChannel _channel;

  /// Exposed so tests stub the same channel the app uses.
  static MethodChannel get channel => _defaultChannel;

  /// Writes [sourcePath] into `<folderName>` under the destination.
  ///
  /// Pass [treeUri] for a user-chosen parent. The native side resolves (or
  /// creates) `<folderName>` inside that tree and copies the file; a missing
  /// grant fails with [DownloadSaveErrorCode.noPermission] — it never falls
  /// back to the default destination.
  Future<DownloadSaveResult> saveDownload({
    required String sourcePath,
    required String folderName,
    required String mimeType,
    String? treeUri,
  }) async {
    if (sourcePath.isEmpty || folderName.isEmpty) {
      return const DownloadSaveFailure(
        DownloadSaveErrorCode.invalidArgs,
        'A source file and folder name are required.',
      );
    }
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'downloads.save',
        <String, Object?>{
          'path': sourcePath,
          'folderName': folderName,
          'mimeType': mimeType,
          'treeUri': treeUri,
        },
      );
      final uri = response?['uri'] as String?;
      if (uri == null) {
        return const DownloadSaveFailure(
          DownloadSaveErrorCode.io,
          'The file was not saved.',
        );
      }
      return DownloadSaveSuccess(uri);
    } on PlatformException catch (e) {
      return DownloadSaveFailure(
        _saveCode(e.code),
        e.message ?? 'Could not save the wallpaper.',
      );
    } on MissingPluginException {
      // No handler for `downloads.save`: the native bridge is missing or stale.
      // That says nothing about the image, so it must not be reported as a
      // format problem.
      return const DownloadSaveFailure(
        DownloadSaveErrorCode.nativeUnavailable,
        'Saving downloads is unavailable in this build.',
      );
    }
  }

  /// Opens the system folder picker from the attached activity.
  Future<ParentPickResult> pickParent() async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'downloads.pickParent',
      );
      if (response == null) {
        return const ParentPickFailure('unknown', 'Folder picker unavailable.');
      }
      if (response['canceled'] == true) return const ParentPickCanceled();
      final uri = response['treeUri'] as String?;
      final label = response['label'] as String?;
      if (uri == null || label == null || uri.isEmpty || label.isEmpty) {
        return const ParentPickFailure(
          'unknown',
          'The picked folder could not be used.',
        );
      }
      return ParentPicked(treeUri: uri, label: label);
    } on PlatformException catch (e) {
      return ParentPickFailure(
        e.code,
        e.message ?? 'Could not open the folder picker.',
      );
    } on MissingPluginException {
      return const ParentPickFailure(
        'unsupported',
        'Choosing a folder is not supported on this device.',
      );
    }
  }

  /// Checks that [treeUri] still grants read+write access.
  Future<ParentAccessResult> checkParent(String treeUri) async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'downloads.checkParent',
        <String, Object?>{'treeUri': treeUri},
      );
      if (response == null) {
        return const ParentAccessUnknown('No response from the platform.');
      }
      if (response['available'] != true) {
        return const ParentAccessLost();
      }
      return ParentAccessAvailable(
        (response['label'] as String?) ?? 'Selected folder',
      );
    } on PlatformException catch (e) {
      return ParentAccessUnknown(e.message ?? 'Could not verify the folder.');
    } on MissingPluginException {
      return const ParentAccessLost();
    }
  }

  /// Releases the persisted grant for [treeUri]. Best effort: a failure only
  /// means the OS keeps a grant this app may never use again.
  Future<void> releaseParent(String treeUri) async {
    try {
      await _channel.invokeMethod<void>('downloads.releaseParent', {
        'treeUri': treeUri,
      });
    } on PlatformException {
      // Best effort.
    } on MissingPluginException {
      // Not available; nothing to release.
    }
  }

  static DownloadSaveErrorCode _saveCode(String code) => switch (code) {
    'invalidArgs' => DownloadSaveErrorCode.invalidArgs,
    'noPermission' => DownloadSaveErrorCode.noPermission,
    'destinationUnavailable' => DownloadSaveErrorCode.destinationUnavailable,
    'noSpace' => DownloadSaveErrorCode.noSpace,
    'notFound' => DownloadSaveErrorCode.notFound,
    'io' => DownloadSaveErrorCode.io,
    'unsupported' => DownloadSaveErrorCode.unsupported,
    _ => DownloadSaveErrorCode.unknown,
  };
}
