import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:vanne/app/theme/app_theme.dart';
import 'package:vanne/core/downloads/download_service.dart';
import 'package:vanne/core/services/wallpaper_applier.dart';
import 'package:vanne/core/wallpaper/wallpaper_repository.dart';
import 'package:vanne/features/wallpaper_detail/application/wallpaper_detail_controller.dart';
import 'package:vanne/features/wallpaper_detail/presentation/widgets/set_wallpaper_sheet.dart';

/// App-level coverage for the Home/Lock/Both set actions: while one of them is
/// applying, its whole content row must be replaced by a centred wavy
/// indicator sized from the button height — not a small spinner beside the
/// label, and not a change in the button's footprint.

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

final class _DeadRepository implements WallpaperRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _rowHeight = 58.0;
const _expectedLoader = 32.0; // fixed size, independent of the 58dp row

Finder get _loader => find.byType(M3EProgressIndicator);

Finder _choiceFor(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(M3EButton));

Finder _anyChoiceButton() => find.byType(M3EButton);

Future<void> _pump(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  late WallpaperDetailController controller;

  setUp(() {
    controller = WallpaperDetailController(
      initial: _wallpaper(),
      repository: _DeadRepository(),
      downloader: DownloadService(),
      applier: WallpaperApplier(),
    );
  });

  tearDown(() {
    controller.dispose();
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: Brightness.light),
        home: Scaffold(
          body: Center(
            // Pixel 9 logical width: the dialog must lay out the way it does
            // on the real device, not in a narrower synthetic box.
            child: SizedBox(
              width: 411,
              child: SetWallpaperDialog(controller: controller),
            ),
          ),
        ),
      ),
    );
    await _pump(tester);
  }

  testWidgets('idle row shows prefix icon and title, no indicator', (
    tester,
  ) async {
    await pumpDialog(tester);

    expect(find.text('Home Screen'), findsOneWidget);
    expect(find.byIcon(PhosphorIconsFill.house), findsOneWidget);
    expect(_loader, findsNothing);

    final home = tester.getSize(_choiceFor('Home Screen'));
    expect(home.height, moreOrLessEquals(_rowHeight, epsilon: 0.5));
  });

  testWidgets('applying Home replaces icon+title with a centred 60% loader', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpDialog(tester);

    final idleWidth = tester.getSize(_choiceFor('Lock Screen')).width;
    final idleHeight = tester.getSize(_choiceFor('Lock Screen')).height;

    controller.apply.value = const ApplyState.applying(ApplyTarget.home);
    await _pump(tester);

    // The content row is gone: no title and no leading icon beside a spinner.
    expect(find.text('Home Screen'), findsNothing);
    expect(find.byIcon(PhosphorIconsFill.house), findsNothing);
    expect(_loader, findsOneWidget);

    // Diameter = 60% of the real button height, centred inside that button.
    final loaderSize = tester.getSize(_loader);
    expect(loaderSize.width, equals(_expectedLoader)); // exactly 32dp
    expect(loaderSize.height, equals(_expectedLoader));

    final buttons = tester.widgetList<M3EButton>(_anyChoiceButton()).toList();
    final boxes = [
      for (var i = 0; i < buttons.length; i++)
        tester.getRect(_anyChoiceButton().at(i)),
    ];
    final buttonWithLoader = boxes.firstWhere(
      (rect) => rect.contains(tester.getCenter(_loader)),
    );
    final loaderCentre = tester.getCenter(_loader);
    expect(
      loaderCentre.dx,
      moreOrLessEquals(buttonWithLoader.center.dx, epsilon: 1),
      reason: 'indicator must be horizontally centred in the button',
    );
    expect(
      loaderCentre.dy,
      moreOrLessEquals(buttonWithLoader.center.dy, epsilon: 1),
      reason: 'indicator must be vertically centred in the button',
    );

    // Footprint is unchanged: same height as an idle row, same width.
    expect(buttonWithLoader.height, moreOrLessEquals(idleHeight, epsilon: 0.5));
    expect(buttonWithLoader.height, moreOrLessEquals(_rowHeight, epsilon: 0.5));
    expect(buttonWithLoader.width, moreOrLessEquals(idleWidth, epsilon: 0.5));

    // Accessible name survives the content swap, without a fake percentage.
    expect(find.bySemanticsLabel('Home Screen in progress'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'\d+\s?%')), findsNothing);

    // Other rows keep their label and icon.
    expect(find.text('Lock Screen'), findsOneWidget);
    expect(find.byIcon(PhosphorIconsFill.lock), findsOneWidget);
    expect(find.text('Crop and set'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('the pending row is not tappable twice and recovers on idle', (
    tester,
  ) async {
    await pumpDialog(tester);

    controller.apply.value = const ApplyState.applying(ApplyTarget.both);
    await _pump(tester);

    final busyButton = tester.widget<M3EButton>(
      find.ancestor(of: _loader, matching: find.byType(M3EButton)),
    );
    expect(
      busyButton.onPressed,
      isNull,
      reason: 'a second apply must not start while one is running',
    );
    expect(find.text('Home & Lock Screen'), findsNothing);

    controller.apply.value = const ApplyState.idle();
    await _pump(tester);

    expect(_loader, findsNothing);
    expect(find.text('Home & Lock Screen'), findsOneWidget);
    expect(find.text('Home Screen'), findsOneWidget);
  });

  testWidgets('crop-and-set shows the same loader on its own row', (
    tester,
  ) async {
    await pumpDialog(tester);

    controller.apply.value = const ApplyState.applyingSystemPicker();
    await _pump(tester);

    expect(_loader, findsOneWidget);
    expect(find.text('Crop and set'), findsNothing);
    expect(find.text('Home Screen'), findsOneWidget);
    expect(tester.getSize(_loader).width, equals(_expectedLoader));
  });
}
