/// Single source of truth for the on-device name of this app's download
/// folder.
///
/// Wallpapers are stored in `<chosen parent>/<storageFolderName>`, and by
/// default in `<defaultParentName>/<storageFolderName>`. Keeping the name
/// here means renaming the app is one edit instead of a string hunt through
/// Dart, Kotlin and Settings copy.
///
/// Renaming only affects **new** downloads: folders and files that already
/// exist are never moved or renamed automatically.
abstract final class AppIdentity {
  /// Folder created inside the chosen parent (and inside [defaultParentName]
  /// when the user has not picked a folder).
  static const String storageFolderName = 'VanneWallpapers';

  /// System media collection used when no parent has been chosen.
  ///
  /// `Pictures` is indexed by the device gallery, so default downloads show up
  /// in Photos/Gallery without any storage permission.
  static const String defaultParentName = 'Pictures';

  /// Display path of the default destination, e.g. `Pictures/VanneWallpapers`.
  static String get defaultFolderPath =>
      '$defaultParentName/$storageFolderName';

  /// Display path of the folder created inside [parentLabel].
  static String folderPathIn(String parentLabel) =>
      '$parentLabel/$storageFolderName';
}
