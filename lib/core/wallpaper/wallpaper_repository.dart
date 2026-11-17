import 'package:signals/signals.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../storage/settings_store.dart';
import '../domain/feed_filter.dart';
import '../errors/error_messages.dart';
import '../security/api_key_store.dart';

/// Application-level facade over the Wallhaven client.
///
/// Owns the API-key lifecycle (secure storage ↔ in-memory manager), the
/// global content policy (purity) and feed-filter → request
/// translation. Portrait filtering is always on — the app is a phone
/// wallpaper app and no longer exposes a toggle. Presentation code depends
/// on this class — never on Dio, JSON, or client internals.
class WallpaperRepository {
  final WallhavenClient client;
  final SecureApiKeyStore keyStore;
  final SettingsStore settingsStore;

  WallpaperRepository({
    required this.client,
    required this.keyStore,
    required this.settingsStore,
  });

  /// Number of changes to the content policy (purity, blocked tags, or the
  /// active API key) since the process started.
  ///
  /// Live feeds read the policy fresh on every request, so a change would
  /// otherwise leave already-loaded pages on screen under the old policy and
  /// mix the two in later pages. [FeedController] watches this signal and
  /// restarts the feed; it is deliberately a counter rather than a boolean so
  /// consecutive changes are never coalesced away.
  final policyRevision = signal(0);

  void _bumpPolicy() => policyRevision.value++;

  /// Whether an API key is currently active.
  bool get isAuthenticated => client.apiKeyManager.isAuthenticated;

  bool get nsfwEnabled => settingsStore.nsfwEnabled;

  Set<String> get blockedTags => settingsStore.blockedTags;

  /// Loads a previously saved key from secure storage into the active
  /// client. Called once at startup.
  Future<void> restoreApiKey() async {
    final key = await keyStore.read();
    if (key != null && key.isNotEmpty) {
      client.apiKeyManager.setApiKey(key);
    }
  }

  /// Persists [apiKey] securely and activates it immediately.
  Future<void> saveApiKey(String apiKey) async {
    final previous = client.apiKeyManager.apiKey;
    await keyStore.save(apiKey);
    client.apiKeyManager.setApiKey(apiKey);
    if (previous != apiKey) _bumpPolicy();
  }

  /// Removes the key from storage and deactivates it.
  ///
  /// NSFW is disabled here rather than by the caller: no request may ever ask
  /// for it unauthenticated, and doing both in one step means live feeds
  /// restart once instead of twice.
  Future<void> removeApiKey() async {
    final hadKey = client.apiKeyManager.apiKey != null;
    final hadNsfw = settingsStore.nsfwEnabled;
    await keyStore.delete();
    client.apiKeyManager.setApiKey(null);
    if (hadNsfw) settingsStore.nsfwEnabled = false;
    if (hadKey || hadNsfw) _bumpPolicy();
  }

  void setNsfwEnabled(bool enabled) {
    if (settingsStore.nsfwEnabled == enabled) return;
    settingsStore.nsfwEnabled = enabled;
    _bumpPolicy();
  }

  void setBlockedTags(Set<String> tags) {
    final current = settingsStore.blockedTags;
    if (current.length == tags.length && current.containsAll(tags)) return;
    settingsStore.blockedTags = tags;
    _bumpPolicy();
  }

  Set<String> _excludedTagsForRequest() => settingsStore.blockedTags;

  /// Runs a search applying global content policy plus the caller's
  /// filter/query.
  ///
  /// When the user has NSFW enabled but no API key, purity is downgraded
  /// to SFW so the request still succeeds; [SearchOutcome.nsfwClamped]
  /// reports that the preference could not be honored.
  Future<SearchOutcome> search({
    String query = '',
    Set<WallhavenColor> colors = const {},
    List<WallhavenCategory> categories = const [],
    FeedFilter filter = const FeedFilter(),
    int page = 1,
    String? seed,
  }) async {
    var purity = _purityForRequest();
    var clamped = false;
    if (nsfwEnabled && !isAuthenticated) {
      purity = const {WallhavenPurity.sfw};
      clamped = true;
    }
    try {
      final excludedTags = _excludedTagsForRequest();
      final effectiveCategories = categories.isNotEmpty
          ? categories.toSet()
          : filter.categories;
      final result = await client.search(
        WallhavenSearchRequest(
          query: query.isEmpty ? null : query,
          categories: effectiveCategories,
          purity: purity,
          colors: colors,
          excludedTags: excludedTags,
          ratios: _ratiosForRequest(),
          sorting: filter.sorting.wire,
          topRange:
              filter.sorting == FeedSorting.popular && filter.topRange != null
              ? filter.topRange!.wire
              : null,
          minResolution: filter.minResolution,
          page: page,
          seed: seed,
        ),
      );
      return SearchOutcome(page: result, nsfwClamped: clamped);
    } on WallhavenException catch (error) {
      throw WallhavenUserException(describeWallhavenError(error));
    }
  }

  /// Always portrait — the app is a phone wallpaper app.
  /// `portrait` matches any `h > w` (9x16, 9x18, 10x16, etc.).
  List<String> _ratiosForRequest() => const ['portrait'];

  Set<WallhavenPurity> _purityForRequest() {
    if (!nsfwEnabled) return const {WallhavenPurity.sfw};
    if (!isAuthenticated) {
      // Preference can't be honored without a key; request stays SFW.
      return const {WallhavenPurity.sfw};
    }
    // NSFW rides with sketchy; both require an authenticated client.
    return const {
      WallhavenPurity.sfw,
      WallhavenPurity.sketchy,
      WallhavenPurity.nsfw,
    };
  }

  /// Fetches full details for a wallpaper; errors are pre-translated.
  Future<Wallpaper> wallpaperDetails(String id) async {
    try {
      return await client.wallpaper(id);
    } on WallhavenException catch (error) {
      throw WallhavenUserException(describeWallhavenError(error));
    }
  }
}

/// Result of a repository search.
final class SearchOutcome {
  final PaginatedResult<Wallpaper> page;

  /// True when the user's NSFW preference could not be honored because no
  /// API key was configured.
  final bool nsfwClamped;

  const SearchOutcome({required this.page, required this.nsfwClamped});
}

/// A wallhaven failure already translated for display. Thrown only by the
/// repository; screens render `message` directly.
final class WallhavenUserException implements Exception {
  final String message;
  const WallhavenUserException(this.message);
  @override
  String toString() => message;
}
