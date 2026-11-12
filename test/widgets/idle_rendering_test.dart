import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vanne/app/theme/app_theme.dart';
import 'package:vanne/shared/widgets/wallpaper_grid.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

/// Why: the wallpaper grid is mounted for the entire life of every feed tab.
/// An always-mounted progress indicator keeps a repeating ticker alive, which
/// makes the app repaint continuously while the user is idle (observed:
/// ~120 fps and ~93% of a core on an idle shell). These tests pin the two
/// halves of that contract: idle feeds must schedule *no* frames, and a
/// genuinely loading feed must still show progress.

Wallpaper _wallpaper(String id) => Wallpaper(
  id: id,
  url: 'https://wallhaven.cc/w/$id',
  source: '',
  purity: Purity.sfw,
  category: Category.general,
  width: 1920,
  height: 1080,
  resolution: '1920x1080',
  ratio: '1.78',
  fileSizeBytes: 1024,
  fileType: 'image/jpeg',
  colors: const [],
  views: 0,
  favorites: 0,
  // Empty image URLs keep the tile on its static placeholder: no network,
  // no image decoding, no fade animation in the frame budget being measured.
  path: '',
  thumbnails: const Thumbnails(),
);

Widget _grid({required bool isLoadingMore, bool hasMore = true}) => MaterialApp(
  theme: AppTheme.build(brightness: Brightness.light),
  home: Scaffold(
    body: WallpaperGrid(
      items: [_wallpaper('aaaaaa')],
      hasMore: hasMore,
      isLoadingMore: isLoadingMore,
      onOpen: (_) {},
    ),
  ),
);

/// True when any ticker/animation is still driving frames.
bool _isAnimating(WidgetTester tester) =>
    tester.binding.transientCallbackCount > 0;

void main() {
  testWidgets('idle grid schedules no frames', (tester) async {
    await tester.pumpWidget(_grid(isLoadingMore: false));
    await tester.pump();

    expect(
      _isAnimating(tester),
      isFalse,
      reason: 'An idle feed must not keep an animation ticker running.',
    );

    // Advancing time must not resurrect the ticker either.
    await tester.pump(const Duration(seconds: 2));
    expect(_isAnimating(tester), isFalse);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('footer shows progress only while a page is loading', (
    tester,
  ) async {
    await tester.pumpWidget(_grid(isLoadingMore: true));
    await tester.pump();

    expect(find.bySemanticsLabel('Loading more wallpapers'), findsOneWidget);
    expect(
      _isAnimating(tester),
      isTrue,
      reason: 'A genuine load-more must animate its progress indicator.',
    );

    // Page arrived: the indicator unmounts and the ticker stops with it.
    await tester.pumpWidget(_grid(isLoadingMore: false));
    await tester.pump();

    expect(find.bySemanticsLabel('Loading more wallpapers'), findsNothing);
    expect(_isAnimating(tester), isFalse);
  });

  testWidgets('exhausted feed shows a static end marker', (tester) async {
    await tester.pumpWidget(_grid(isLoadingMore: false, hasMore: false));
    await tester.pump();

    expect(find.text("You've reached the end"), findsOneWidget);
    expect(_isAnimating(tester), isFalse);
  });
}
