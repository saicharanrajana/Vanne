import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Plain app-settings store backed by a Hive box named `app_settings`.
///
/// Only non-secret preferences live here. The API key must NEVER be
/// written to this store — it belongs in [SecureApiKeyStore].
final class SettingsStore {
  static const _boxName = 'app_settings';

  static const _nsfwKey = 'nsfw_enabled';
  static const _dynamicColorKey = 'dynamic_color';
  static const _pitchBlackKey = 'pitch_black';
  static const _themeModeKey = 'theme_mode';

  Box<dynamic>? _box;

  /// Opens the underlying box; call once during bootstrap before use.
  Future<void> open() async {
    _box ??= await Hive.openBox<dynamic>(_boxName);
  }

  bool _readBool(String key, {required bool fallback}) =>
      _box?.get(key) as bool? ?? fallback;

  void _writeBool(String key, bool value) => _box?.put(key, value);

  // -- Content --------------------------------------------------------------

  /// Whether the user opted into NSFW results. Defaults to `false`.
  /// Including NSFW requires an API key at request time.
  bool get nsfwEnabled => _readBool(_nsfwKey, fallback: false);
  set nsfwEnabled(bool value) => _writeBool(_nsfwKey, value);

  // -- Appearance -----------------------------------------------------------

  /// Whether Android 12+ dynamic color (Material You) drives the palette.
  /// Defaults to `true`; the teal seed is always the graceful fallback.
  bool get dynamicColor => _readBool(_dynamicColorKey, fallback: true);
  set dynamicColor(bool value) => _writeBool(_dynamicColorKey, value);

  /// Whether dark-theme surfaces collapse to true black (AMOLED).
  /// Meaningful only when the effective theme is dark.
  bool get pitchBlack => _readBool(_pitchBlackKey, fallback: false);
  set pitchBlack(bool value) => _writeBool(_pitchBlackKey, value);

  /// Persisted [AppThemeMode] name: `system`, `light`, or `dark`.
  String get themeModeName => _box?.get(_themeModeKey) as String? ?? 'system';

  Future<void> setThemeModeName(String value) =>
      _box!.put(_themeModeKey, value);
}

/// Which brightness source drives the app theme.
enum AppThemeMode { system, light, dark }

extension AppThemeModeX on AppThemeMode {
  static AppThemeMode fromStorageName(String? name) =>
      AppThemeMode.values.firstWhere(
        (mode) => mode.name == name,
        orElse: () => AppThemeMode.system,
      );
}
