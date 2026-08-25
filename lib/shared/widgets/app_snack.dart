import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme/app_spacing.dart';

/// The app's single snackbar entry point.
///
/// Polish over raw [ScaffoldMessenger.showSnackBar]:
/// * **No blind stacking** — pending/queued snacks are cleared before a
///   new one shows, so rapid actions can't build a snack backlog.
/// * **Duplicate suppression** — the same message fired again within a
///   short window is dropped instead of re-appearing.
/// * **Theme-native styling** — inverse-surface by default,
///   error-container for failures; nothing hard-coded, so dynamic-color
///   and pitch-black schemes just work.
abstract final class AppSnack {
  /// Installed on the root [MaterialApp] (`scaffoldMessengerKey:`), so
  /// snacks never depend on ambient `ScaffoldMessenger.of(context)`
  /// lookups — those break when the calling context is captured across
  /// async gaps or route transitions (e.g. a download finishing after
  /// navigation). Context remains a fallback for tests/pre-app code.
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>(debugLabel: 'AppSnack.rootMessenger');

  static const Duration _dedupeWindow = Duration(seconds: 2);
  static String? _lastMessage;
  static DateTime _lastShownAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Shows [message], replacing any queued snacks.
  ///
  /// Pass `error: true` for failure feedback; it renders on the scheme's
  /// error container so mistakes read differently from confirmations.
  static void show(BuildContext context, String message, {bool error = false}) {
    _present(message, error, _resolveMessenger(context));
  }

  /// Context-free variant for calls that complete after an async gap, where
  /// the caller's Element may already be defunct. Uses only the root
  /// messenger installed on [MaterialApp].
  static void showRoot(String message, {bool error = false}) {
    _present(message, error, messengerKey.currentState);
  }

  static ScaffoldMessengerState? _resolveMessenger(BuildContext context) =>
      messengerKey.currentState ?? ScaffoldMessenger.maybeOf(context);

  static void _present(
    String message,
    bool error,
    ScaffoldMessengerState? messenger,
  ) {
    if (messenger == null) return;

    final now = DateTime.now();
    final isDuplicate =
        message == _lastMessage && now.difference(_lastShownAt) < _dedupeWindow;
    _lastMessage = message;
    _lastShownAt = now;
    if (isDuplicate) return;

    // Theme is read from the MESSENGER's context, never the caller's: a
    // caller's Element can be unmounted by the time this runs (signal-driven
    // rebuilds, route pops across awaits), and reading through it throws
    // "This widget has been unmounted".
    final scheme = Theme.of(messenger.context).colorScheme;
    // One impact per snack: confirmations tick lightly, failures hit harder.
    // Callers showing a snack should not trigger their own success/error
    // haptic, or the user feels two impacts for one event.
    M3EHaptics.trigger(
      error ? M3EHapticFeedback.medium : M3EHapticFeedback.light,
    );

    if (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(color: scheme.onErrorContainer),
          ),
          backgroundColor: scheme.errorContainer,
          behavior: SnackBarBehavior.floating,
          shape: const StadiumBorder(),
          margin: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
        ),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: TextStyle(color: scheme.onInverseSurface),
        ),
        backgroundColor: scheme.inverseSurface,
        behavior: SnackBarBehavior.floating,
        shape: const StadiumBorder(),
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
      ),
    );
  }
}
