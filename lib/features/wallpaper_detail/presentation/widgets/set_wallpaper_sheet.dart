import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import '../../../../app/theme/app_shapes.dart';
import '../../../../core/services/wallpaper_applier.dart';
import '../../../../shared/widgets/app_snack.dart';
import '../../application/wallpaper_detail_controller.dart';

/// Opens the "Set wallpaper" popup (Dialog) — home / lock / both.
///
/// Previously a smooth_sheets bottom sheet with a preselected `home` and an
/// extra Apply button. Now a lightweight dialog where tapping an option
/// directly applies (no preselect, no extra tap). The controller downloads
/// a local copy; `async_wallpaper` applies it and per-target results drive
/// the snackbar.
Future<void> showSetWallpaperSheet(
  BuildContext context, {
  required WallpaperDetailController controller,
}) {
  return showSetWallpaperPopup(context, controller: controller);
}

Future<void> showSetWallpaperPopup(
  BuildContext context, {
  required WallpaperDetailController controller,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _SetWallpaperDialog(controller: controller),
  );
}

final class _SetWallpaperDialog extends StatefulWidget {
  final WallpaperDetailController controller;

  const _SetWallpaperDialog({required this.controller});

  @override
  State<_SetWallpaperDialog> createState() => _SetWallpaperDialogState();
}

final class _SetWallpaperDialogState extends State<_SetWallpaperDialog> {
  Future<void> _apply(ApplyTarget target) async {
    await widget.controller.applyAsWallpaper(target);
    final state = widget.controller.apply.peek();
    if (!mounted) return;
    if (state.succeeded) {
      AppSnack.show(
        context,
        switch (target) {
          ApplyTarget.home => 'Wallpaper set for your home screen',
          ApplyTarget.lock => 'Wallpaper set for your lock screen',
          ApplyTarget.both => 'Wallpaper set for home and lock screens',
        },
      );
      Navigator.of(context).pop();
    }
    // On failure, error is shown inline; dialog stays open for retry.
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      backgroundColor: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.extraLarge),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: SignalBuilder(
          builder: (context) {
            final state = widget.controller.apply.value;
            final busy = state.isBusy;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Set wallpaper',
                  style: theme.textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose where to apply',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                for (final target in ApplyTarget.values)
                  _PopupTile(
                    icon: switch (target) {
                      ApplyTarget.home => Icons.home_outlined,
                      ApplyTarget.lock => Icons.lock_outline,
                      ApplyTarget.both => Icons.layers_outlined,
                    },
                    title: switch (target) {
                      ApplyTarget.home => 'Home screen',
                      ApplyTarget.lock => 'Lock screen',
                      ApplyTarget.both => 'Home + Lock screen',
                    },
                    enabled: !busy,
                    onTap: () => _apply(target),
                  ),
                if (state.error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    state.error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                if (busy) ...[
                  const SizedBox(height: 16),
                  const Center(
                    child: SizedBox(
                      height: 24,
                      width: 24,
                      child: M3ELinearWavyProgressIndicator(),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

final class _PopupTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool enabled;
  final VoidCallback onTap;

  const _PopupTile({
    required this.icon,
    required this.title,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Accessible pair: secondaryContainer / onSecondaryContainer is a
    // Material-3 guaranteed contrast pair (≥7:1). Using surfaceContainerHighest
    // with onSurfaceVariant was low-contrast and failed a11y.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: enabled
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppShapes.largeIncreased),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 56,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: enabled
                        ? theme.colorScheme.onSecondaryContainer
                        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: enabled
                          ? theme.colorScheme.onSecondaryContainer
                          : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
