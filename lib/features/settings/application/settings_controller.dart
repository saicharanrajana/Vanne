import 'package:signals/signals.dart';

import '../../../core/storage/settings_store.dart';
import '../../../core/wallpaper/wallpaper_repository.dart';

/// Reactive application settings. Every mutation persists immediately and
/// notifies watchers (theme, search behavior, content policy).
final class SettingsController {
  final SettingsStore _store;
  final WallpaperRepository _repository;

  /// Material You dynamic color enabled.
  final dynamicColor = signal(true);

  /// True-black dark surfaces for AMOLED displays.
  final pitchBlack = signal(false);

  /// Brightness source: system / light / dark.
  final themeMode = signal(AppThemeMode.system);

  /// NSFW content preference (requires an API key to take effect).
  final nsfwEnabled = signal(false);

  /// Whether a Wallhaven API key is currently configured.
  final hasApiKey = signal(false);

  SettingsController(this._store, this._repository);

  /// Hydrates signals from persistence; call once during bootstrap.
  void restore() {
    batch(() {
      dynamicColor.set(_store.dynamicColor);
      pitchBlack.set(_store.pitchBlack);
      themeMode.set(AppThemeModeX.fromStorageName(_store.themeModeName));
      nsfwEnabled.set(_store.nsfwEnabled);
      hasApiKey.set(_repository.isAuthenticated);
    });
  }

  void setDynamicColor(bool value) {
    _store.dynamicColor = value;
    dynamicColor.set(value);
  }

  void setPitchBlack(bool value) {
    _store.pitchBlack = value;
    pitchBlack.set(value);
  }

  void setThemeMode(AppThemeMode mode) {
    _store.setThemeModeName(mode.name);
    themeMode.set(mode);
  }

  /// Persists the NSFW preference; only reachable with an API key.
  void setNsfwEnabled(bool value) {
    _repository.setNsfwEnabled(value);
    nsfwEnabled.set(value);
  }

  /// Saves a new API key securely; [nsfwEnabled] becomes enforceable.
  Future<void> saveApiKey(String key) async {
    await _repository.saveApiKey(key);
    hasApiKey.set(true);
  }

  /// Removes the API key and force-disables NSFW so no request can ever
  /// ask for it unauthenticated.
  Future<void> removeApiKey() async {
    await _repository.removeApiKey();
    if (nsfwEnabled.value) setNsfwEnabled(false);
    hasApiKey.set(false);
  }
}
