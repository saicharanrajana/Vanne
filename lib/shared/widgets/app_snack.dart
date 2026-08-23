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
      GlobalKey<ScaffoldMessengerState>(
    debugLabel: 'AppSnack.rootMessenger',
  );

  static const Duration _dedupeWindow = Duration(seconds: 2);
  static String? _lastMessage;
  static DateTime _lastShownAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// Shows [message], replacing any queued snacks.
  ///
  /// Pass `error: true` for failure feedback; it renders on the scheme's
  /// error container so mistakes read differently from confirmations.
  static void show(BuildContext context, String message, {bool error = false}) {
    final messenger =
        messengerKey.currentState ?? ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final now = DateTime.now();
    final isDuplicate =
        message == _lastMessage && now.difference(_lastShownAt) < _dedupeWindow;
    _lastMessage = message;
    _lastShownAt = now;
    if (isDuplicate) return;

    final scheme = Theme.of(context).colorScheme;

    if (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
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
        content: Text(message, style: TextStyle(color: scheme.onInverseSurface)),
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
