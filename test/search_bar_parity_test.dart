import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:vanne/app/theme/app_theme.dart';
import 'package:vanne/shared/widgets/app_search_bar_spec.dart';

/// Discover's collapsed bar and the Search view's editable bar must be the
/// same control: identical height, leading slot, glyph offset and hint offset,
/// in rest and while focused. Only the glyph differs (magnifier vs back).

Widget _host(Widget bar, {double pageInset = 16}) => MaterialApp(
  theme: AppTheme.build(brightness: Brightness.light),
  home: Scaffold(
    body: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(pageInset, 12, pageInset, 12),
          child: SizedBox(width: 400 - pageInset * 2, child: bar),
        ),
      ],
    ),
  ),
);

/// Discover's bar — the exact builder the screen uses.
Widget _discoverBar({VoidCallback? onOpen}) => AppSearchBarSpec.buildBar(
  hintText: 'Search wallpapers',
  glyph: PhosphorIconsBold.magnifyingGlass,
  tooltip: 'Search',
  onLeadingPressed: onOpen ?? () {},
  readOnly: true,
  onTap: onOpen ?? () {},
);

/// The Search view's editable bar — the exact builder the screen uses.
Widget _searchBar(FocusNode node, {VoidCallback? onBack}) =>
    AppSearchBarSpec.buildBar(
      focusNode: node,
      hintText: 'Search wallpapers',
      glyph: PhosphorIconsBold.arrowLeft,
      tooltip: 'Back',
      onLeadingPressed: onBack ?? () {},
      onSubmitted: (_) {},
    );

/// Geometry that must match between the two bars, measured from the bar's own
/// left edge so each screen's page padding stays out of the comparison.
class _BarGeometry {
  const _BarGeometry({
    required this.height,
    required this.iconInset,
    required this.iconSize,
    required this.hintInset,
    required this.targetWidth,
  });

  final double height;
  final double iconInset;
  final double iconSize;
  final double hintInset;
  final double targetWidth;

  @override
  String toString() =>
      'h=$height iconInset=$iconInset iconSize=$iconSize hintInset=$hintInset target=$targetWidth';
}

Future<_BarGeometry> _measure(
  WidgetTester tester, {
  required IconData glyph,
}) async {
  final bar = tester.getRect(find.byType(M3ESearchBar));
  final icon = tester.getRect(find.byIcon(glyph));
  final hint = tester.getRect(find.text('Search wallpapers'));
  final target = tester.getRect(
    find.descendant(
      of: find.byType(M3ESearchBar),
      matching: find.byType(M3EIconButton),
    ),
  );
  return _BarGeometry(
    height: bar.height,
    iconInset: icon.left - bar.left,
    iconSize: icon.width,
    hintInset: hint.left - bar.left,
    targetWidth: target.width,
  );
}

void main() {
  testWidgets('both search bars share one measured geometry', (tester) async {
    await tester.pumpWidget(_host(_discoverBar()));
    await tester.pump(const Duration(milliseconds: 400));
    final discover = await _measure(
      tester,
      glyph: PhosphorIconsBold.magnifyingGlass,
    );

    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(_host(_searchBar(focus)));
    await tester.pump(const Duration(milliseconds: 400));
    final searchRest = await _measure(
      tester,
      glyph: PhosphorIconsBold.arrowLeft,
    );

    focus.requestFocus();
    await tester.pump(const Duration(milliseconds: 400));
    final searchFocused = await _measure(
      tester,
      glyph: PhosphorIconsBold.arrowLeft,
    );

    // The two bars, and the focused variant of the editable one.
    expect(
      searchRest.toString(),
      discover.toString(),
      reason: 'Discover and Search bars drifted: $discover vs $searchRest',
    );
    expect(
      searchFocused.toString(),
      searchRest.toString(),
      reason:
          'focusing the Search field must not move the glyph or the hint: '
          '$searchRest vs $searchFocused',
    );

    // Pin the spec itself, so a future theme bump cannot silently move it.
    expect(discover.height, 56);
    expect(discover.iconInset, 22); // 8dp bar padding + 14dp slot centring
    expect(discover.iconSize, AppSearchBarSpec.leadingIconSize);
    expect(discover.hintInset, 56);
    expect(discover.targetWidth, greaterThanOrEqualTo(48));
  });

  testWidgets('collapsed Discover bar still opens Search from either part', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(_host(_discoverBar(onOpen: () => opened++)));
    await tester.pump(const Duration(milliseconds: 400));

    // The bar itself is tappable…
    await tester.tapAt(tester.getCenter(find.byType(M3ESearchBar)));
    await tester.pump();
    final afterBarTap = opened;
    expect(afterBarTap, greaterThanOrEqualTo(1));

    // …and the magnifier is now a real 48dp action of its own.
    await tester.tap(find.byIcon(PhosphorIconsBold.magnifyingGlass));
    await tester.pump();
    expect(
      opened,
      greaterThan(afterBarTap),
      reason: 'the leading control must stay interactive',
    );
    // Note: material_3_expressive's read-only bar reports a single physical
    // tap twice (bar + internal ink). The router's `openSearch` guards on an
    // existing SearchRoute, so the app stays idempotent; this test therefore
    // asserts "navigation was requested", not an exact count.
  });
}
