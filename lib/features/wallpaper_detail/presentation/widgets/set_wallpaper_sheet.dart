import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_3_expressive/components/buttons/enums/m3e_button_enums.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import '../../../../app/dependencies.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/services/wallpaper_applier.dart';
import '../../../../features/settings/application/settings_controller.dart';
import '../../../../shared/widgets/app_snack.dart';
import '../../application/wallpaper_detail_controller.dart';
import '../wallpaper_theme.dart';

/// Opens the "Set wallpaper" dialog — home / lock / both / Crop and Set.
///
/// Rendered on the root navigator, so the ambient app theme would win;
/// the dialog re-derives the wallpaper scheme (same helper the detail
/// screen uses) and wraps itself in it — every color comes from the
/// wallpaper's palette, honoring pitch-black mode.
///
/// Flow: caller should [WallpaperDetailController.prepareForSet] (wavy
/// indicator) before opening so the file is ready; the sheet then applies
/// instantly without re-download.
Future<void> showSetWallpaperPopup(
  BuildContext context, {
  required WallpaperDetailController controller,
}) {
  return M3EDialog.show<void>(
    context,
    barrierDismissible: true,
    dialog: _SetWallpaperTheme(
      controller: controller,
      child: _SetWallpaperDialog(controller: controller),
    ),
  );
}

/// Rebuilds the wallpaper-derived theme when the palette signal changes
/// (e.g. deep-linked wallpaper whose colors arrive late), cross-fading
/// just like the detail screen's [AnimatedTheme].
final class _SetWallpaperTheme extends StatefulWidget {
  final WallpaperDetailController controller;
  final Widget child;

  const _SetWallpaperTheme({required this.controller, required this.child});

  @override
  State<_SetWallpaperTheme> createState() => _SetWallpaperThemeState();
}

final class _SetWallpaperThemeState extends State<_SetWallpaperTheme> {
  ColorScheme? _cachedScheme;
  Object? _schemeKey;

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final brightness = baseTheme.brightness;

    return SignalBuilder(
      builder: (context) {
        final wallpaper = widget.controller.wallpaper.value;
        final settings = locator.isRegistered<SettingsController>()
            ? locator<SettingsController>()
            : null;
        final pitchBlack =
            (settings?.pitchBlack.value ?? false) &&
            brightness == Brightness.dark;
        final key = Object.hash(
          wallpaper.id,
          brightness,
          wallpaper.colors,
          pitchBlack,
        );
        if (key != _schemeKey || _cachedScheme == null) {
          _cachedScheme = wallpaperScheme(
            wallpaper,
            brightness,
            baseTheme.colorScheme,
            pitchBlack,
          );
          _schemeKey = key;
        }
        final theme = wallpaperThemeData(_cachedScheme!, baseTheme);
        return AnimatedTheme(
          data: theme,
          duration: AppMotion.transition,
          curve: AppMotion.arrivalCurve,
          child: Theme(data: theme, child: widget.child),
        );
      },
    );
  }
}

final class _SetWallpaperDialog extends StatefulWidget {
  final WallpaperDetailController controller;

  const _SetWallpaperDialog({required this.controller});

  @override
  State<_SetWallpaperDialog> createState() => _SetWallpaperDialogState();
}

final class _SetWallpaperDialogState extends State<_SetWallpaperDialog> {
  Future<void> _apply(ApplyTarget target) async {
    M3EHaptics.trigger(M3EHapticFeedback.light);
    await widget.controller.applyAsWallpaper(target);
    final state = widget.controller.apply.peek();
    if (!mounted) return;
    if (state.succeeded) {
      AppSnack.showRoot(switch (target) {
        ApplyTarget.home => 'Wallpaper set for your home screen',
        ApplyTarget.lock => 'Wallpaper set for your lock screen',
        ApplyTarget.both => 'Wallpaper set for home and lock screens',
      });
      Navigator.of(context).pop();
    }
    // On failure, error is shown inline; dialog stays open for retry.
  }

  Future<void> _setWith() async {
    M3EHaptics.trigger(M3EHapticFeedback.light);
    await widget.controller.setWithSystemPicker();
    final state = widget.controller.apply.peek();
    if (!mounted) return;
    if (state.succeeded) {
      AppSnack.showRoot('Opened system wallpaper picker');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final state = widget.controller.apply.value;
        final busy = state.isBusy;

        // busyTarget tracks which option is currently applying so only
        // that row shows the inline wavy indicator (like the Set button).
        final busyTarget = state.target;
        final busyPicker = state.isSystemPicker;
        bool isRowBusy(int index) {
          if (!busy) return false;
          return switch (index) {
            0 => busyTarget == ApplyTarget.home,
            1 => busyTarget == ApplyTarget.lock,
            2 => busyTarget == ApplyTarget.both,
            3 => busyPicker,
            _ => false,
          };
        }

        return M3EDialog(
          // Supplying an icon centers the title above the content, matching
          // the create-collection dialog's language.
          icon: const Icon(PhosphorIconsFill.image),
          title: 'Set wallpaper',
          // The package's content padding is horizontal-only when no
          // dividers are used — this restores bottom breathing room below
          // the last choice button.
          contentPadding: const EdgeInsets.only(
            left: 24,
            right: 24,
            bottom: 24,
          ),
          content: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ChoiceButton(
                  icon: PhosphorIconsFill.house,
                  label: 'Home Screen',
                  enabled: !busy,
                  busy: isRowBusy(0),
                  onTap: () => _apply(ApplyTarget.home),
                ),
                const SizedBox(height: AppSpacing.md),
                _ChoiceButton(
                  icon: PhosphorIconsFill.lock,
                  label: 'Lock Screen',
                  enabled: !busy,
                  busy: isRowBusy(1),
                  onTap: () => _apply(ApplyTarget.lock),
                ),
                const SizedBox(height: AppSpacing.md),
                _ChoiceButton(
                  icon: PhosphorIconsFill.copy,
                  label: 'Home & Lock Screen',
                  enabled: !busy,
                  busy: isRowBusy(2),
                  onTap: () => _apply(ApplyTarget.both),
                ),
                const SizedBox(height: AppSpacing.md),
                _ChoiceButton(
                  icon: PhosphorIconsFill.crop,
                  label: 'Crop and set',
                  enabled: !busy,
                  busy: isRowBusy(3),
                  onTap: _setWith,
                ),
                if (state.error != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    state.error!,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// One destination choice rendered as a full-width expressive tonal button.
/// The M3E button owns press motion, disabled de-emphasis, and hit target;
/// only the inline busy indicator is custom.
final class _ChoiceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  const _ChoiceButton({
    required this.icon,
    required this.label,
    required this.enabled,
    this.busy = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contentColor = theme.colorScheme.onSecondaryContainer;
    return M3EButton.tonal(
      size: M3EButtonSize.custom(height: 58),
      onPressed: enabled ? onTap : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (busy)
            M3EProgressIndicator.circularWavy(size: 22, color: contentColor)
          else
            Icon(icon, size: 22, color: contentColor),
          const SizedBox(width: AppSpacing.md),
          Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: contentColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
