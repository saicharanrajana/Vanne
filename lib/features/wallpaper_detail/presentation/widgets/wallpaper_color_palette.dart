// Prefer material_ui over package:flutter widgets/material imports: the app
// runs on the material_ui widget tree.
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:signals/signals_flutter.dart';

import '../../../../app/theme/app_shapes.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../shared/utils/hex_color.dart';
import '../../../../shared/widgets/app_snack.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../application/wallpaper_detail_controller.dart';
import 'wallpaper_section_card.dart';

/// "Colors" section: up to four dominant colors from Wallhaven as large
/// rounded swatches.
///
/// Tapping a swatch copies Wallhaven's **exact hex string** (leading `#`
/// included) to the clipboard — the raw wire value is used verbatim, never
/// reconstructed through [Color] — and confirms with a snackbar.
final class WallpaperColorPalette extends StatelessWidget {
  final WallpaperDetailController controller;

  /// Maximum swatches shown; Wallhaven can return more.
  static const int maxSwatches = 4;

  const WallpaperColorPalette({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final colors = controller.wallpaper.value.colors;
        if (colors.isEmpty) return const SizedBox.shrink();

        final swatches = colors.take(maxSwatches).toList(growable: false);

        return WallpaperSectionCard(
          title: 'Colors',
          trailing: _CountBadge(count: colors.length),
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [for (final hex in swatches) _Swatch(hex: hex)],
          ),
        );
      },
    );
  }
}

/// Small rounded count pill in the section header.
final class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppShapes.full),
      ),
      child: Text(
        '$count',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// One tappable color swatch. [hex] is Wallhaven's raw string (`#rrggbb`).
final class _Swatch extends StatelessWidget {
  final String hex;

  const _Swatch({required this.hex});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Copy $hex',
      child: PressableScale(
        child: M3ETooltip(
          message: 'Copy $hex',
          child: Material(
            color: parseHexColor(hex) ?? Colors.grey,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                AppShapes.extraLargeIncreased,
              ),
            ),
            child: InkWell(
              onTap: () => _copy(context, hex),
              customBorder: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  AppShapes.extraLargeIncreased,
                ),
              ),
              child: const SizedBox(width: 64, height: 64),
            ),
          ),
        ),
      ),
    );
  }

  static void _copy(BuildContext context, String hex) {
    // Copy the wire value verbatim — `#` included — so what lands on the
    // clipboard is exactly what Wallhaven published.
    Clipboard.setData(ClipboardData(text: hex));
    AppSnack.show(context, '$hex copied to clipboard');
  }
}
