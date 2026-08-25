import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import '../../../../app/dependencies.dart';
import '../../../../app/theme/app_motion.dart';
import '../../../../app/theme/app_shapes.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/services/wallpaper_applier.dart';
import '../../../../features/settings/application/settings_controller.dart';
import '../../../../shared/widgets/app_snack.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../application/wallpaper_detail_controller.dart';
import '../wallpaper_theme.dart';

/// Opens the "Set wallpaper" dialog — home / lock / both / Set With….
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
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => _SetWallpaperTheme(
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
    await widget.controller.applyAsWallpaper(target);
    final state = widget.controller.apply.peek();
    if (!mounted) return;
    if (state.succeeded) {
      AppSnack.show(context, switch (target) {
        ApplyTarget.home => 'Wallpaper set for your home screen',
        ApplyTarget.lock => 'Wallpaper set for your lock screen',
        ApplyTarget.both => 'Wallpaper set for home and lock screens',
      });
      Navigator.of(context).pop();
    }
    // On failure, error is shown inline; dialog stays open for retry.
  }

  Future<void> _setWith() async {
    await widget.controller.setWithSystemPicker();
    final state = widget.controller.apply.peek();
    if (!mounted) return;
    if (state.succeeded) {
      AppSnack.show(context, 'Opened system wallpaper picker');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Dialog(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppShapes.extraLargeIncreased),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: SignalBuilder(
          builder: (context) {
            final state = widget.controller.apply.value;
            final busy = state.isBusy;

            // Each tile gets its own tonal container role so the wallpaper's
            // palette paints the whole popup. All pairs are Material-3
            // guaranteed contrast pairs.
            // busyTarget tracks which option is currently applying so only
            // that tile shows the inline wavy indicator (like the Set button).
            final busyTarget = state.target;
            final busyPicker = state.isSystemPicker;
            bool isTileBusy(int index) {
              if (!busy) return false;
              return switch (index) {
                0 => busyTarget == ApplyTarget.home,
                1 => busyTarget == ApplyTarget.lock,
                2 => busyTarget == ApplyTarget.both,
                3 => busyPicker,
                _ => false,
              };
            }

            final tiles = <(IconData, String, Color, Color, VoidCallback)>[
              (
                BootstrapIcons.house_fill,
                'Home Screen',
                scheme.primaryContainer,
                scheme.onPrimaryContainer,
                () => _apply(ApplyTarget.home),
              ),
              (
                BootstrapIcons.lock_fill,
                'Lock Screen',
                scheme.primaryContainer,
                scheme.onPrimaryContainer,
                () => _apply(ApplyTarget.lock),
              ),
              (
                BootstrapIcons.layers_fill,
                'Home & Lock Screen',
                scheme.primaryContainer,
                scheme.onPrimaryContainer,
                () => _apply(ApplyTarget.both),
              ),
              (
                BootstrapIcons.grid_fill,
                'Set With…',
                scheme.primaryContainer,
                scheme.onPrimaryContainer,
                _setWith,
              ),
            ];

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Set wallpaper',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: scheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                for (var i = 0; i < tiles.length; i++) ...[
                  _EntranceTile(
                    delay: i * 40,
                    reduceMotion: reduceMotion,
                    child: _PopupTile(
                      icon: tiles[i].$1,
                      title: tiles[i].$2,
                      container: tiles[i].$3,
                      onContainer: tiles[i].$4,
                      enabled: !busy,
                      busy: isTileBusy(i),
                      onTap: tiles[i].$5,
                    ),
                  ),
                  if (i < tiles.length - 1)
                    const SizedBox(height: AppSpacing.lg),
                ],
                if (state.error != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    state.error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.error,
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

/// Staggered entrance: each tile fades and slides up, its motion starting
/// [delay] ms into the animation. Snaps when reduced motion is requested.
final class _EntranceTile extends StatelessWidget {
  final int delay;
  final bool reduceMotion;
  final Widget child;

  const _EntranceTile({
    required this.delay,
    required this.reduceMotion,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (reduceMotion) return child;

    final totalMs = AppMotion.transition.inMilliseconds + delay;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      // Hold still for [delay], then run the arrival curve for the
      // remaining window — a clean stagger without timers.
      curve: Interval(delay / totalMs, 1, curve: AppMotion.arrivalCurve),
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0, 1),
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - value)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

final class _PopupTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color container;
  final Color onContainer;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  const _PopupTile({
    required this.icon,
    required this.title,
    required this.container,
    required this.onContainer,
    required this.enabled,
    this.busy = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    // Busy tile keeps its tonal colors so the wavy indicator remains
    // vibrant; other disabled tiles use neutral + de-emphasized colors.
    final isActive = busy || enabled;
    final tileColor = isActive ? container : scheme.surfaceContainerHigh;
    final contentColor = isActive
        ? onContainer
        : scheme.onSurfaceVariant.withValues(alpha: 0.5);

    return PressableScale(
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : AppMotion.transition,
        decoration: BoxDecoration(
          color: tileColor,
          borderRadius: BorderRadius.circular(AppShapes.largeIncreased),
        ),
        child: Material(
          color: Colors.transparent,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppShapes.largeIncreased),
          ),
          child: InkWell(
            onTap: enabled ? onTap : null,
            child: SizedBox(
              height: 64,
              child: Center(
                child: busy
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: M3EProgressIndicator.circularWavy(
                          size: 24,
                          color: contentColor,
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Tonal icon chip: painted circle in on-container @ 12%.
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: contentColor.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(icon, size: 23, color: contentColor),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            title,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: contentColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
