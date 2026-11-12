import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../../app/theme/app_shapes.dart';
import '../../app/theme/app_spacing.dart';

/// The semantic presentation of an application snackbar.
enum AppSnackType {
  info,
  success,

  /// A successful but destructive outcome, such as removing a saved
  /// collection. Uses the theme's error pair so the removal reads as
  /// destructive, without reusing the wording or icon of a failure.
  removal,

  error,
}

/// The app's single snackbar entry point.
///
/// Polish over raw [ScaffoldMessenger.showSnackBar]:
/// * **No blind stacking** — pending/queued snacks are cleared before a
///   new one shows, so rapid actions can't build a snack backlog.
/// * **Duplicate suppression** — the same message fired again within a
///   short window is dropped instead of re-appearing.
/// * **Theme-native styling** — each status uses a semantic color-container
///   role, so dynamic-color and pitch-black schemes just work.
abstract final class AppSnack {
  /// Installed on the root [MaterialApp] (`scaffoldMessengerKey:`), so
  /// snacks never depend on ambient `ScaffoldMessenger.of(context)`
  /// lookups — those break when the calling context is captured across
  /// async gaps or route transitions (e.g. a download finishing after
  /// navigation). Context remains a fallback for tests/pre-app code.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>(debugLabel: 'AppSnack.rootMessenger');

  static const Duration _dedupeWindow = Duration(seconds: 2);
  static const Duration _duration = Duration(milliseconds: 2500);

  /// Dedupe state is scoped to the messenger that actually showed the snack.
  ///
  /// A process-global "last message" leaked across app lifetimes (tests,
  /// hot restart, a re-created root), suppressing the first snack of a fresh
  /// UI. The messenger is recreated with each app shell, so keying history
  /// off it keeps duplicate suppression for one session without carrying
  /// state into the next.
  static final Expando<_SnackHistory> _history = Expando('AppSnack.history');

  /// Shows [message] using the requested semantic [type].
  static void show(
    BuildContext context,
    String message, {
    AppSnackType type = AppSnackType.info,
  }) {
    _present(message, type, _resolveMessenger(context));
  }

  /// Context-free variant for calls that complete after an async gap, where
  /// the caller's Element may already be defunct. Uses only the root
  /// messenger installed on [MaterialApp].
  static void showRoot(
    String message, {
    AppSnackType type = AppSnackType.info,
  }) {
    _present(message, type, messengerKey.currentState);
  }

  static ScaffoldMessengerState? _resolveMessenger(BuildContext context) =>
      messengerKey.currentState ?? ScaffoldMessenger.maybeOf(context);

  static void _present(
    String message,
    AppSnackType type,
    ScaffoldMessengerState? messenger,
  ) {
    if (messenger == null) return;

    final history = _history[messenger] ??= _SnackHistory();
    final now = DateTime.now();
    final isDuplicate =
        message == history.message &&
        now.difference(history.shownAt) < _dedupeWindow;
    history.message = message;
    history.shownAt = now;
    if (isDuplicate) return;

    // Theme is read from the MESSENGER's context, never the caller's: a
    // caller's Element can be unmounted by the time this runs (signal-driven
    // rebuilds, route pops across awaits), and reading through it throws
    // "This widget has been unmounted".
    final scheme = Theme.of(messenger.context).colorScheme;
    final (backgroundColor, foregroundColor, iconData) = switch (type) {
      AppSnackType.info => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
        PhosphorIconsFill.info,
      ),
      AppSnackType.success => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        PhosphorIconsFill.checkCircle,
      ),
      // `error`/`onError` is the strongest destructive signal the scheme
      // provides and is a contrast-checked pair. The glyph is a minus (not a
      // warning): nothing went wrong, something was taken away.
      AppSnackType.removal => (
        scheme.error,
        scheme.onError,
        PhosphorIconsFill.minusCircle,
      ),
      AppSnackType.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        PhosphorIconsFill.warningCircle,
      ),
    };
    // One impact per snack: confirmations tick lightly, failures hit harder.
    // Callers showing a snack should not trigger their own success/error
    // haptic, or the user feels two impacts for one event.
    M3EHaptics.trigger(
      type == AppSnackType.error
          ? M3EHapticFeedback.medium
          : M3EHapticFeedback.light,
    );

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(iconData, size: 20, color: foregroundColor),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(message, style: TextStyle(color: foregroundColor)),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: _duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShapes.large),
        ),
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
      ),
    );
  }
}

/// Last snack shown by one messenger; see [AppSnack._history].
final class _SnackHistory {
  String? message;
  DateTime shownAt = DateTime.fromMillisecondsSinceEpoch(0);
}
