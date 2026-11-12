import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import '../l10n/generated/app_localizations.dart';
import 'dependencies.dart';
import 'launch_background.dart';
import 'theme/app_theme.dart';

/// Runs app-wide initialization *after* the first frame has been painted.
///
/// `main()` used to `await bootstrap()` before `runApp()`, so the window was
/// blank for the whole serial chain of disk, secure-storage and repository
/// work. Mounting this widget first means the user sees the themed launch
/// surface immediately, while [initialize] runs off the first-frame path.
///
/// Failure handling is explicit:
/// * [child] is never mounted until [initialize] succeeds, so no screen can
///   observe partially registered services.
/// * A failed initialize releases anything registered so far and shows a
///   retry surface instead of leaving a permanent blank window.
final class AppStartup extends StatefulWidget {
  const AppStartup({super.key, required this.initialize, required this.child});

  /// One-shot app initialization. Must be safe to call again after a
  /// failure (services are reset in between).
  final Future<void> Function() initialize;

  /// The real application, built only once [initialize] completes.
  final Widget child;

  @override
  State<AppStartup> createState() => _AppStartupState();
}

final class _AppStartupState extends State<AppStartup> {
  bool _ready = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      await widget.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (error, stack) {
      debugPrint('App startup failed: $error\n$stack');
      await _releasePartialServices();
      if (!mounted) return;
      setState(() {
        _ready = false;
        _error = error;
      });
    }
  }

  /// Bootstrap registers services incrementally; a failure halfway through
  /// would otherwise make every retry fail on duplicate registration.
  Future<void> _releasePartialServices() async {
    try {
      await locator.reset();
    } catch (error) {
      debugPrint('Failed to reset partially registered services: $error');
    }
  }

  void _retry() {
    setState(() => _error = null);
    _run();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) return widget.child;
    return _StartupSurface(
      error: _error,
      onRetry: _error == null ? null : _retry,
    );
  }
}

/// Launch/error surface shown before [AppStartup] completes.
///
/// The healthy state is a plain screen in [LaunchBackground], the same colour
/// Android paints behind its splash icon. The system splash icon therefore
/// fades out into an identical background instead of flashing a second,
/// unrelated mark before the first screen appears.
///
/// Deliberately static: no ticker, no network, no font fetch. It is the first
/// frame the user sees, so it must be cheap and must not keep animating if
/// initialization is slow.
final class _StartupSurface extends StatelessWidget {
  const _StartupSurface({required this.error, required this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.build(brightness: Brightness.light),
      darkTheme: AppTheme.build(brightness: Brightness.dark),
      // `Builder` so the surface can read the theme MaterialApp resolved
      // (the platform brightness, since no user preference is loaded yet).
      home: Builder(
        builder: (context) => Scaffold(
          key: const ValueKey('startup-surface'),
          backgroundColor: LaunchBackground.of(Theme.of(context).brightness),
          body: error == null
              ? const SizedBox.expand()
              : SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: _StartupError(onRetry: onRetry),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

final class _StartupError extends StatelessWidget {
  const _StartupError({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        M3EShapeContainer.cookie9Sided(
          width: 80,
          height: 80,
          color: scheme.errorContainer,
          child: Icon(
            PhosphorIconsFill.warningCircle,
            size: 34,
            color: scheme.onErrorContainer,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          l10n.startupErrorTitle,
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          l10n.startupErrorMessage,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        M3EButton(
          key: const ValueKey('startup-retry'),
          style: M3EButtonStyle.filled,
          onPressed: onRetry,
          size: M3EButtonSize.md,
          child: Text(l10n.tryAgain),
        ),
      ],
    );
  }
}
