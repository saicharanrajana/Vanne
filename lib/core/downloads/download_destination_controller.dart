import 'package:signals/signals.dart';
import 'package:system_wallpaper/system_wallpaper.dart';

import '../../core/storage/settings_store.dart';
import 'download_destination.dart';

/// Result of a user-initiated folder choice, for snack feedback.
enum DestinationPickOutcome { picked, canceled, failed, busy }

/// Owns the download destination: the persisted parent-folder grant, its live
/// availability, and the in-progress picker state.
///
/// The app keeps the **only** record of which tree it writes into
/// ([SettingsStore]); the OS owns the grant itself. Restoring re-validates the
/// grant so a revoked or moved folder surfaces as [DestinationAccess.lost]
/// instead of failing silently at download time.
final class DownloadDestinationController {
  DownloadDestinationController(
    this._store, {
    DownloadStoragePlatform? platform,
  }) : _platform = platform ?? const DownloadStoragePlatform();

  final SettingsStore _store;
  final DownloadStoragePlatform _platform;

  /// Active destination; defaults to `Pictures/<app folder>`.
  final destination = signal<DownloadDestination>(
    const DefaultDownloadDestination(),
  );

  /// Whether the chosen tree still grants access. Always
  /// [DestinationAccess.available] for the default destination.
  final access = signal(DestinationAccess.available);

  /// True while the system folder picker is open.
  final picking = signal(false);

  /// Last picker failure, already phrased for display.
  final error = signal<String?>(null);

  int _activeSaves = 0;
  final _deferredReleases = <String>{};

  /// Restores the persisted destination and re-validates its grant.
  Future<void> restore() async {
    final treeUri = _store.downloadTreeUri;
    final label = _store.downloadParentLabel;
    if (treeUri == null || label == null) return;

    destination.set(
      ChosenDownloadDestination(treeUri: treeUri, parentLabel: label),
    );
    final result = await _platform.checkParent(treeUri);
    switch (result) {
      case ParentAccessAvailable(:final label):
        // Providers may rename a folder without invalidating the grant.
        if (label.isNotEmpty) {
          destination.set(
            ChosenDownloadDestination(treeUri: treeUri, parentLabel: label),
          );
        }
        access.set(DestinationAccess.available);
      case ParentAccessLost():
        access.set(DestinationAccess.lost);
      case ParentAccessUnknown():
        // Cannot prove the grant is gone; keep it and let a save report the
        // concrete failure rather than silently redirecting.
        access.set(DestinationAccess.available);
    }
  }

  /// Opens the system folder picker and persists the picked parent.
  ///
  /// Cancelling leaves the previous destination untouched. A concurrent pick
  /// returns [DestinationPickOutcome.busy] without overwriting the pending one.
  Future<DestinationPickOutcome> chooseParent() async {
    if (picking.value) return DestinationPickOutcome.busy;
    picking.set(true);
    error.set(null);
    try {
      final result = await _platform.pickParent();
      switch (result) {
        case ParentPickCanceled():
          return DestinationPickOutcome.canceled;
        case ParentPickFailure(:final message):
          error.set(message);
          return DestinationPickOutcome.failed;
        case ParentPicked(:final treeUri, :final label):
          // The native side validated read+write before returning, so the
          // new grant is safe to persist. Only now may the old one go.
          final previous = destination.peek().treeUri;
          await _store.setDownloadDestination(
            treeUri: treeUri,
            parentLabel: label,
          );
          destination.set(
            ChosenDownloadDestination(treeUri: treeUri, parentLabel: label),
          );
          access.set(DestinationAccess.available);
          // Re-selecting a folder that was queued for release keeps it: it is
          // the live destination again, so its grant must survive.
          _deferredReleases.remove(treeUri);
          if (previous != null && previous != treeUri) {
            _release(previous);
          }
          return DestinationPickOutcome.picked;
      }
    } finally {
      picking.set(false);
    }
  }

  /// Returns to the default `Pictures/<app folder>` destination and releases the
  /// chosen folder's grant.
  Future<void> resetToDefault() async {
    final previous = destination.peek();
    await _store.clearDownloadDestination();
    destination.set(const DefaultDownloadDestination());
    access.set(DestinationAccess.available);
    error.set(null);
    final treeUri = previous.treeUri;
    if (treeUri != null) _release(treeUri);
  }

  /// Marks the destination that actually failed as unusable, so Settings can
  /// offer "choose again" or "use default".
  ///
  /// [treeUri] is the destination snapshotted when the write started. When the
  /// user has since picked another folder, that newer folder is untouched —
  /// otherwise a stale failure would accuse a healthy destination.
  void markAccessLost(String? treeUri) {
    if (treeUri == null) return;
    if (destination.peek().treeUri != treeUri) return;
    access.set(DestinationAccess.lost);
  }

  /// Called by [DownloadService] around a write so grants are never released
  /// while a save still needs them.
  void beginSave() => _activeSaves++;

  void endSave() {
    if (_activeSaves > 0) _activeSaves--;
    if (_activeSaves > 0 || _deferredReleases.isEmpty) return;
    final current = destination.peek().treeUri;
    final pending = _deferredReleases.toList();
    _deferredReleases.clear();
    for (final treeUri in pending) {
      // Never release the grant the app is currently saving into.
      if (treeUri == current) continue;
      _platform.releaseParent(treeUri);
    }
  }

  void _release(String treeUri) {
    if (_activeSaves > 0) {
      _deferredReleases.add(treeUri);
      return;
    }
    _platform.releaseParent(treeUri);
  }

  void dispose() {
    destination.dispose();
    access.dispose();
    picking.dispose();
    error.dispose();
  }
}
