// Prefer material_ui over package:flutter widgets/material imports: the app
// runs on the material_ui widget tree.
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

/// Container behind controls that float above wallpaper imagery.
const Color _overlayScrim = Color(0x80000000);

/// Glyph colour for controls that float above wallpaper imagery.
///
/// Fully opaque: only the container is translucent, never the icon.
const Color _overlayGlyph = Color(0xFFFFFFFF);

/// Pressed/hovered/focused state layer painted over [_overlayScrim].
const Color _overlayStateLayer = Color(0x1FFFFFFF);

/// Styling for an [M3EIconButton] floating above an arbitrary wallpaper.
///
/// A surface-role container (filled or tonal) reads as a detached chip against
/// a photo, and a fully transparent glyph disappears into dark or busy areas.
/// This decoration keeps the standard component and its 48dp target, but pairs
/// a translucent dark scrim with an opaque white glyph. White on that scrim
/// stays above 3:1 on pure black and on pure white imagery, and selection
/// remains legible through the glyph itself (outline versus filled) rather
/// than through an extra container colour.
final M3EIconButtonDecoration imageOverlayIconButtonDecoration =
    M3EIconButtonDecoration(
      backgroundColor: const WidgetStatePropertyAll<Color?>(_overlayScrim),
      foregroundColor: const WidgetStatePropertyAll<Color?>(_overlayGlyph),
      overlayColor: WidgetStateProperty.resolveWith<Color?>(
        (states) =>
            states.contains(WidgetState.pressed) ||
                states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)
            ? _overlayStateLayer
            : null,
      ),
    );
