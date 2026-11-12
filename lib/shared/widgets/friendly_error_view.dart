import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vanne/l10n/generated/app_localizations.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

/// Friendly replacement for Flutter's default build-error surface,
/// installed via `ErrorWidget.builder` in `main()`.
///
/// Release builds show a calm themed message with no technical details;
/// debug builds append the exception and stack trace. A hidden long press
/// copies the diagnostics to the clipboard. Adapts to the space the broken
/// widget occupied: full layout when there is room, icon-only badge in
/// small slots.
final class FriendlyErrorView extends StatefulWidget {
  final FlutterErrorDetails details;

  const FriendlyErrorView({super.key, required this.details});

  @override
  State<FriendlyErrorView> createState() => _FriendlyErrorViewState();
}

final class _FriendlyErrorViewState extends State<FriendlyErrorView> {
  Timer? _timer;
  bool _copied = false;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    M3EHaptics.trigger(M3EHapticFeedback.medium);
    await Clipboard.setData(
      ClipboardData(
        text:
            '${widget.details.exceptionAsString()}\n\n'
            '${widget.details.stack}',
      ),
    );
    if (!mounted) return;
    setState(() => _copied = true);
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // The view can land anywhere in the tree — including where no
    // Directionality exists yet — so it provides its own. The transparent
    // Material prevents missing-Material underline artifacts.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        type: MaterialType.transparency,
        child: Semantics(
          container: true,
          label: 'Something went wrong. Restarting the app should fix it.',
          child: ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPress: _copy,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final full =
                      constraints.maxHeight.isFinite &&
                      constraints.maxHeight >= 320 &&
                      constraints.maxWidth.isFinite &&
                      constraints.maxWidth >= 300;
                  final l10n = AppLocalizations.of(context);
                  return Container(
                    width: constraints.hasBoundedWidth
                        ? constraints.maxWidth
                        : null,
                    height: constraints.hasBoundedHeight
                        ? constraints.maxHeight
                        : null,
                    color: scheme.surface,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(24),
                    child: full
                        ? _FullView(
                            details: widget.details,
                            copied: _copied,
                            message: l10n,
                          )
                        : _CompactView(copied: _copied),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _FullView extends StatelessWidget {
  final FlutterErrorDetails details;
  final bool copied;
  final AppLocalizations? message;

  const _FullView({
    required this.details,
    required this.copied,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(PhosphorIconsFill.wifiSlash, size: 56, color: scheme.onSurfaceVariant),
        const SizedBox(height: 20),
        Text(
          message?.somethingWentWrong ?? 'Something went wrong',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(color: scheme.onSurface),
        ),
        const SizedBox(height: 8),
        Text(
          message?.restartMayFixIt ?? 'Restarting the app should fix it.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 24),
          Text(
            '${details.exceptionAsString()}\n\n${details.stack}',
            maxLines: 12,
            overflow: TextOverflow.fade,
            style: TextStyle(
              fontFamily: 'monospace',
              fontFamilyFallback: const ['Menlo', 'Courier'],
              fontSize: 11,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ],
    );
  }
}

final class _CompactView extends StatelessWidget {
  final bool copied;

  const _CompactView({required this.copied});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Icon(
          PhosphorIconsFill.warningOctagon,
          key: ValueKey(copied),
          size: 40,
          color: copied ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
