import 'package:flutter/foundation.dart';

import 'app_identity.dart';

/// Where downloaded wallpapers are written.
///
/// The app never stores a raw filesystem path for a chosen folder: arbitrary
/// document providers are addressed only through the persisted tree URI the
/// system picker returned. [parentLabel] is the provider's own display name,
/// used for UI copy — it is not a path.
sealed class DownloadDestination {
  const DownloadDestination();

  /// Folder that receives the files, phrased for display.
  String get folderPath;

  /// Persisted tree URI for [ChosenDownloadDestination], else `null`.
  String? get treeUri;
}

/// Default destination: the gallery-indexed `Pictures/<app folder>`.
///
/// Writes go through MediaStore, so no storage permission is requested.
final class DefaultDownloadDestination extends DownloadDestination {
  const DefaultDownloadDestination();

  @override
  String get folderPath => AppIdentity.defaultFolderPath;

  @override
  String? get treeUri => null;

  @override
  bool operator ==(Object other) => other is DefaultDownloadDestination;

  @override
  int get hashCode => (DefaultDownloadDestination).hashCode;
}

/// A parent folder the user picked from the system folder picker.
///
/// Downloads land in `<parentLabel>/<AppIdentity.storageFolderName>`. The
/// tree URI carries the persisted read/write grant; if the user revokes it or
/// moves the folder, saves fail with an explicit error rather than silently
/// writing somewhere else.
@immutable
final class ChosenDownloadDestination extends DownloadDestination {
  const ChosenDownloadDestination({
    required this.treeUri,
    required this.parentLabel,
  });

  @override
  final String treeUri;

  /// Provider display name of the picked parent folder.
  final String parentLabel;

  @override
  String get folderPath => AppIdentity.folderPathIn(parentLabel);

  @override
  bool operator ==(Object other) =>
      other is ChosenDownloadDestination &&
      other.treeUri == treeUri &&
      other.parentLabel == parentLabel;

  @override
  int get hashCode => Object.hash(treeUri, parentLabel);
}

/// Whether the persisted grant behind a [ChosenDownloadDestination] is still
/// usable. The default destination is always available.
enum DestinationAccess {
  /// Persisted tree URI resolves with read+write access.
  available,

  /// The grant was revoked, or the folder was moved/deleted.
  lost,
}
