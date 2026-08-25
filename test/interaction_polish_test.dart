import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:wallpaper_app/app/theme/app_theme.dart';
import 'package:wallpaper_app/core/downloads/download_service.dart';
import 'package:wallpaper_app/core/services/wallpaper_applier.dart';
import 'package:wallpaper_app/core/wallpaper/wallpaper_repository.dart';
import 'package:wallpaper_app/features/wallpaper_detail/application/wallpaper_detail_controller.dart';
import 'package:wallpaper_app/features/wallpaper_detail/presentation/widgets/set_wallpaper_sheet.dart';
import 'package:wallpaper_app/shared/widgets/favorite_toggle_button.dart';
import 'package:wallpaper_app/shared/widgets/friendly_error_view.dart';

/// Coverage for the interaction-polish pass:
/// * shared favorite toggle states/semantics,
/// * set-wallpaper chooser rendered from M3E list rows,
/// * friendly global error view (full + compact, hidden copy gesture).

TestDefaultBinaryMessengerBinding get _testerBinding =>
    TestDefaultBinaryMessengerBinding.instance;

Wallpaper _wallpaper() => Wallpaper(
  id: 'abc123',
  url: 'https://wallhaven.cc/w/abc123',
  source: '',
  purity: Purity.sfw,
  category: Category.general,
  width: 1920,
  height: 1080,
  resolution: '1920x1080',
  ratio: '1.78',
  fileSizeBytes: 1024,
  fileType: '',
  colors: const ['#3B2A72'],
  views: 0,
  favorites: 0,
  path: '',
  thumbnails: const Thumbnails(),
);

Widget _host(Widget child, {Size size = const Size(400, 800)}) => MaterialApp(
  theme: AppTheme.build(brightness: Brightness.light),
  home: Scaffold(
    body: SizedBox(width: size.width, height: size.height, child: child),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FavoriteToggleButton', () {
    testWidgets('unselected shows save semantics and fires callback', (
      tester,
    ) async {
      var pressed = false;
      await tester.pumpWidget(
        _host(
          FavoriteToggleButton(
            selected: false,
            onPressed: () => pressed = true,
          ),
        ),
      );
      await tester.pump();

      expect(find.bySemanticsLabel('Save to favorites'), findsOneWidget);

      await tester.tap(find.byType(FavoriteToggleButton));
      expect(pressed, isTrue);
    });

    testWidgets('selected shows remove semantics', (tester) async {
      await tester.pumpWidget(
        _host(FavoriteToggleButton(selected: true, onPressed: () {})),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.bySemanticsLabel('Remove from favorites'), findsOneWidget);
    });
  });

  group('SetWallpaperPopup', () {
    testWidgets('renders four destination rows on an M3E dialog', (
      tester,
    ) async {
      final controller = WallpaperDetailController(
        initial: _wallpaper(),
        repository: _DeadRepository(),
        downloader: DownloadService(),
        applier: WallpaperApplier(),
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(_host(const SizedBox.shrink()));
      showSetWallpaperPopup(
        tester.element(find.byType(Scaffold)),
        controller: controller,
      );
      await tester.pumpAndSettle();

      expect(find.text('Set wallpaper'), findsOneWidget);
      expect(find.text('Home Screen'), findsOneWidget);
      expect(find.text('Lock Screen'), findsOneWidget);
      expect(find.text('Home & Lock Screen'), findsOneWidget);
      expect(find.text('Set With…'), findsOneWidget);
    });
  });

  group('FriendlyErrorView', () {
    String? clipboardText;

    setUp(() {
      clipboardText = null;
      _testerBinding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (message) async {
          if (message.method == 'Clipboard.setData') {
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

    FlutterErrorDetails details(String marker) => FlutterErrorDetails(
      exception: StateError('probe-$marker'),
      stack: StackTrace.current,
      library: 'test',
    );

    testWidgets('large slot shows the friendly full layout', (tester) async {
      await tester.pumpWidget(
        _host(
          FriendlyErrorView(details: details('full')),
          size: const Size(400, 500),
        ),
      );
      await tester.pump();

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(
        find.textContaining('Restarting the app should fix it'),
        findsOneWidget,
      );
      // Debug diagnostics are present under kDebugMode.
      expect(find.textContaining('probe-full'), findsOneWidget);
    });

    testWidgets('small slot degrades to a compact badge', (tester) async {
      await tester.pumpWidget(
        _host(
          FriendlyErrorView(details: details('compact')),
          size: const Size(80, 40),
        ),
      );
      await tester.pump();

      expect(find.text('Something went wrong'), findsNothing);
    });

    testWidgets('long press copies diagnostics', (tester) async {
      await tester.pumpWidget(
        _host(
          FriendlyErrorView(details: details('copy')),
          size: const Size(400, 500),
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('Something went wrong'));
      await tester.pump();

      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('probe-copy'));
    });
  });
}

class _DeadRepository implements WallpaperRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
