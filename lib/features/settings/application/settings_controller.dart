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

  /// Tags excluded from Wallhaven searches via `-tag` query tokens.
  final blockedTags = signal(<String>{});

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
      blockedTags.set(_store.blockedTags);
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

  /// Persists blocked tags as a normalized set.
  ///
  /// The write goes through the repository, which owns the content policy: it
  /// skips an unchanged set and bumps the policy revision otherwise, so live
  /// feeds restart exactly once per real change. Writing the store directly
  /// would persist the choice but leave every mounted feed on the old one.
  void setBlockedTags(Set<String> value) {
    final normalized = value.map(_normalizeTag).where((s) => s.isNotEmpty).toSet();
    _repository.setBlockedTags(normalized);
    blockedTags.set(_repository.blockedTags);
  }

  /// Parses raw multiline/comma-separated input and persists the result.
  void saveBlockedTagsFromRaw(String raw) {
    setBlockedTags(parseBlockedTags(raw));
  }

  /// Parses Wallhaven tag list input: commas or new lines separated.
  static Set<String> parseBlockedTags(String raw) => raw
      .split(RegExp(r'[,\n]+'))
      .map(_normalizeTag)
      .where((s) => s.isNotEmpty)
      .where((s) => RegExp(r'^[a-z0-9_-]+$').hasMatch(s))
      .toSet();

  /// Serializes a tag set for editing: sorted, comma separated.
  static String serializeBlockedTags(Set<String> tags) {
    final sorted = tags.toList()..sort();
    return sorted.join(', ');
  }

  static String _normalizeTag(String tag) => tag.trim().toLowerCase();

  /// Saves a new API key securely; [nsfwEnabled] becomes enforceable.
  Future<void> saveApiKey(String key) async {
    await _repository.saveApiKey(key);
    hasApiKey.set(true);
  }

  /// Removes the API key and force-disables NSFW so no request can ever
  /// ask for it unauthenticated.
  Future<void> removeApiKey() async {
    await _repository.removeApiKey();
    // The repository already force-disabled the stored preference, in the same
    // step as removing the key: mirror it here without a second write.
    nsfwEnabled.set(false);
    hasApiKey.set(false);
  }
}
