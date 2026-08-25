import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:wallpaper_app/app/theme/app_theme.dart';
import 'package:wallpaper_app/core/downloads/download_service.dart';
import 'package:wallpaper_app/core/services/wallpaper_applier.dart';
import 'package:wallpaper_app/core/wallpaper/wallpaper_repository.dart';
import 'package:wallpaper_app/features/wallpaper_detail/application/wallpaper_detail_controller.dart';
import 'package:wallpaper_app/features/wallpaper_detail/presentation/widgets/wallpaper_color_palette.dart';
import 'package:wallpaper_app/features/wallpaper_detail/presentation/widgets/wallpaper_tags_section.dart';
import 'package:wallpaper_app/shared/widgets/app_snack.dart';

/// Focused probes for the redesigned detail sheet sections:
/// * color swatch → exact Wallhaven hex on the clipboard + snackbar,
/// * tag count / expansion / collapse, including 0/1/2-tag edge cases.

TestDefaultBinaryMessengerBinding get _testerBinding =>
    TestDefaultBinaryMessengerBinding.instance;

/// The sections under test never fetch, so the repository is a dead stub.
class _StubRepository implements WallpaperRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Wallpaper _wallpaper({List<String> colors = const [], List<Tag>? tags}) =>
    Wallpaper(
      id: 'abc123',
      url: 'https://wallhaven.cc/w/abc123',
      source: '',
      purity: Purity.sfw,
      category: Category.general,
      width: 1920,
      height: 1080,
      resolution: '1920x1080',
      ratio: '1.78',
      fileSizeBytes: 3 * 1024 * 1024,
      fileType: 'image/jpeg',
      colors: colors,
      views: 0,
      favorites: 0,
      path: '',
      thumbnails: const Thumbnails(),
      tags: tags,
    );

WallpaperDetailController _controller(Wallpaper wallpaper) =>
    WallpaperDetailController(
      initial: wallpaper,
      repository: _StubRepository(),
      downloader: DownloadService(),
      applier: WallpaperApplier(),
    );

Widget _host(Widget child) => MaterialApp(
  scaffoldMessengerKey: AppSnack.messengerKey,
  theme: AppTheme.build(brightness: Brightness.light, dynamicScheme: null),
  home: Scaffold(body: child),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String? clipboardText;
  bool? clipboardSetCalled;

  setUp(() {
    clipboardText = null;
    clipboardSetCalled = null;
    _testerBinding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (message) async {
        if (message.method == 'Clipboard.setData') {
          clipboardSetCalled = true;
          clipboardText =
              (message.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
  });

  tearDown(() {
    _testerBinding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });

  group('WallpaperColorPalette', () {
    testWidgets('copies the exact Wallhaven hex (with #) and confirms', (
      tester,
    ) async {
      final controller = _controller(
        _wallpaper(colors: const ['#3B2A72', '#663311', '#AABBCC', '#112233']),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(WallpaperColorPalette(controller: controller)),
      );

      await tester.tap(find.bySemanticsLabel('Copy #3B2A72'));
      await tester.pump();

      expect(clipboardSetCalled, isTrue);
      // The raw wire string must land on the clipboard verbatim — `#`
      // included, no round-trip through Color.
      expect(clipboardText, '#3B2A72');
      expect(find.text('#3B2A72 copied to clipboard'), findsOneWidget);
    });

    testWidgets('shows at most 4 swatches and a count badge', (tester) async {
      final controller = _controller(
        _wallpaper(
          colors: const ['#111111', '#222222', '#333333', '#444444', '#555555'],
        ),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(WallpaperColorPalette(controller: controller)),
      );

      expect(find.bySemanticsLabel('Copy #555555'), findsNothing);
      for (final hex in ['#111111', '#222222', '#333333', '#444444']) {
        expect(find.bySemanticsLabel('Copy $hex'), findsOneWidget);
      }
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('renders nothing when the wallpaper has no colors', (
      tester,
    ) async {
      final controller = _controller(_wallpaper());
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(WallpaperColorPalette(controller: controller)),
      );

      expect(find.text('Colors'), findsNothing);
    });
  });

  group('WallpaperTagsSection', () {
    List<Tag> tagsOf(int count) =>
        List.generate(count, (i) => Tag(id: i, name: 'tag$i'));

    testWidgets('shows 2 chips + "+N" when collapsed, expands to all, '
        'and collapses again', (tester) async {
      final controller = _controller(_wallpaper(tags: tagsOf(5)));
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(WallpaperTagsSection(controller: controller)),
      );

      // Collapsed: first two tags plus the overflow pill only.
      expect(find.text('tag0'), findsOneWidget);
      expect(find.text('tag1'), findsOneWidget);
      expect(find.text('tag2'), findsNothing);
      expect(find.text('+3'), findsOneWidget);

      // Expand via the +N pill.
      await tester.tap(find.text('+3'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 5; i++) {
        expect(find.text('tag$i'), findsOneWidget);
      }
      expect(find.text('+3'), findsNothing);

      // Collapse via the chevron affordance.
      await tester.tap(find.byIcon(BootstrapIcons.caret_down_fill));
      await tester.pumpAndSettle();
      expect(find.text('tag0'), findsOneWidget);
      expect(find.text('tag1'), findsOneWidget);
      expect(find.text('tag2'), findsNothing);
      expect(find.text('+3'), findsOneWidget);
    });

    testWidgets('expands and collapses via the chevron as well', (
      tester,
    ) async {
      final controller = _controller(_wallpaper(tags: tagsOf(4)));
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(WallpaperTagsSection(controller: controller)),
      );

      await tester.tap(find.byIcon(BootstrapIcons.caret_down_fill));
      await tester.pumpAndSettle();
      expect(find.text('tag3'), findsOneWidget);

      await tester.tap(find.byIcon(BootstrapIcons.caret_down_fill));
      await tester.pumpAndSettle();
      expect(find.text('tag3'), findsNothing);
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('1 and 2 tags render without an overflow pill', (tester) async {
      for (final count in [1, 2]) {
        final controller = _controller(_wallpaper(tags: tagsOf(count)));
        addTearDown(controller.dispose);

        await tester.pumpWidget(
          _host(WallpaperTagsSection(controller: controller)),
        );

        expect(find.text('+${count - 1}'), findsNothing);
        for (var i = 0; i < count; i++) {
          expect(find.text('tag$i'), findsOneWidget);
        }
      }
    });

    testWidgets('renders nothing when tags are absent', (tester) async {
      final controller = _controller(_wallpaper());
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        _host(WallpaperTagsSection(controller: controller)),
      );

      expect(find.text('Tags'), findsNothing);
    });
  });
}
