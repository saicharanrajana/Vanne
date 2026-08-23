// Prefer material_ui over package:flutter widgets/material imports: the app
// runs on the material_ui widget tree.
import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import '../../../../app/dependencies.dart';
import '../../../../app/theme/app_shapes.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/services/url_launcher_service.dart';
import '../../../../shared/widgets/app_snack.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../application/wallpaper_detail_controller.dart';
import 'set_wallpaper_sheet.dart';

/// The detail sheet's cohesive action group:
/// `[ ↓ ] [ Set ] [ ↗ ]` — two large tonal icon buttons flanking
/// a wide filled primary button.
///
/// All three share the same 64 dp height and expressive rounding so they
/// read as one group. Functionality is unchanged: gallery download (with
/// in-place progress), the Set-wallpaper dialog, and opening the
/// wallpaper's Wallhaven page.
final class WallpaperActionBar extends StatelessWidget {
  final WallpaperDetailController controller;

  const WallpaperActionBar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final isBusy = controller.download.value.isBusy;

        return Row(
          children: [
            _ActionButton(
              tooltip: 'Download to gallery',
              onPressed: isBusy ? null : () => _download(context, controller),
              child: isBusy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: M3ECircularWavyProgressIndicator(size: 24),
                    )
                  : const Icon(Icons.download),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: _PrimaryActionButton(
                label: 'Set',
                onPressed: () =>
                    showSetWallpaperPopup(context, controller: controller),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            _ActionButton(
              tooltip: 'Open on Wallhaven',
              onPressed: () => _openSource(context, controller),
              child: const Icon(Icons.open_in_new),
            ),
          ],
        );
      },
    );
  }

  /// Runs the gallery download and reports the terminal outcome. All
  /// failures are caught: anything escaping here would surface as an
  /// unhandled zone error instead of user feedback.
  static Future<void> _download(
    BuildContext context,
    WallpaperDetailController controller,
  ) async {
    try {
      await controller.downloadToGallery();
    } catch (_) {
      // downloadToGallery already maps known failures; this guards against
      // unexpected errors becoming unhandled zone exceptions.
      if (!context.mounted) return;
      AppSnack.show(context, 'Download failed. Please try again.', error: true);
      return;
    }
    final state = controller.download.peek();
    if (!context.mounted) return;
    if (state.done) {
      AppSnack.show(context, 'Wallpaper saved to your gallery');
    } else if (state.error != null) {
      AppSnack.show(context, state.error!, error: true);
    }
  }

  static Future<void> _openSource(
    BuildContext context,
    WallpaperDetailController controller,
  ) async {
    final url = Uri.parse(controller.wallpaper.peek().url);
    final ok = await locator<UrlLauncherService>().openInApp(url);
    if (!ok && context.mounted) {
      AppSnack.show(context, 'No browser available.', error: true);
    }
  }
}

/// Large tonal square button flanking the primary action.
final class _ActionButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback? onPressed;
  final Widget child;

  const _ActionButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShapes.extraLargeIncreased),
    );

    return PressableScale(
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: scheme.secondaryContainer,
          shape: shape,
          child: InkWell(
            onTap: onPressed,
            customBorder: shape,
            child: SizedBox(
              width: 64,
              height: 64,
              child: IconTheme.merge(
                data: IconThemeData(color: scheme.onSecondaryContainer),
                child: Center(child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The wide filled primary "Set wallpaper" button — the group's visual
/// anchor.
final class _PrimaryActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _PrimaryActionButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppShapes.full),
    );

    return PressableScale(
      child: Material(
        color: scheme.primary,
        shape: shape,
        child: InkWell(
          onTap: onPressed,
          customBorder: shape,
          child: SizedBox(
            height: 64,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wallpaper, color: scheme.onPrimary, size: 22),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  label,
                  // Slightly larger/heavier than labelLarge so the short
                  // "Set" label still carries primary-action presence.
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
