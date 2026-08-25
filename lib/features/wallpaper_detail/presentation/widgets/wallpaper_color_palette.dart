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
/// Tap opens a filtered wallpapers list for that color; long-press copies
/// Wallhaven's **exact hex string** (leading `#` included) to the clipboard.
final class WallpaperColorPalette extends StatelessWidget {
  final WallpaperDetailController controller;
  final ValueChanged<String>? onColorTap;

  /// Maximum swatches shown; Wallhaven can return more.
  static const int maxSwatches = 4;

  const WallpaperColorPalette({
    super.key,
    required this.controller,
    this.onColorTap,
  });

  @override
  Widget build(BuildContext context) {
    return SignalBuilder(
      builder: (context) {
        final colors = controller.wallpaper.value.colors;
        if (colors.isEmpty) return const SizedBox.shrink();

        final swatches = colors.take(maxSwatches).toList(growable: false);

        return WallpaperSectionCard(
          title: 'Colors',
          child: Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              for (final hex in swatches)
                _Swatch(hex: hex, onTap: onColorTap),
            ],
          ),
        );
      },
    );
  }
}

/// One tappable color swatch. [hex] is Wallhaven's raw string (`#rrggbb`).
final class _Swatch extends StatelessWidget {
  final String hex;
  final ValueChanged<String>? onTap;

  const _Swatch({required this.hex, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: onTap != null ? 'View $hex wallpapers' : 'Copy $hex',
      child: PressableScale(
        child: M3ETooltip(
          message: onTap != null ? 'Tap to view, long-press to copy $hex' : 'Copy $hex',
          child: Material(
            color: parseHexColor(hex) ?? Colors.grey,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                AppShapes.extraLargeIncreased,
              ),
            ),
            child: InkWell(
              onTap: onTap != null ? () => onTap!(hex) : () => _copy(context, hex),
              onLongPress: onTap != null ? () => _copy(context, hex) : null,
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
