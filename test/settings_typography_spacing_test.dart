import 'package:flutter_test/flutter_test.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vanne/app/dependencies.dart';
import 'package:vanne/app/router/tab_scroll_coordinator.dart';
import 'package:vanne/app/theme/app_theme.dart';
import 'package:vanne/core/storage/settings_store.dart';
import 'package:vanne/core/downloads/download_destination_controller.dart';
import 'package:vanne/core/wallpaper/wallpaper_repository.dart';
import 'package:vanne/features/settings/application/settings_controller.dart';
import 'package:vanne/features/settings/presentation/settings_screen.dart';

class _SettingsRepository implements WallpaperRepository {
  @override
  bool get isAuthenticated => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _registerSettingsDependencies() async {
  final repository = _SettingsRepository();
  final settings = SettingsController(SettingsStore(), repository)..restore();
  locator
    ..registerSingleton<SettingsController>(settings)
    ..registerSingleton<TabScrollCoordinator>(TabScrollCoordinator())
    ..registerSingleton<DownloadDestinationController>(
      DownloadDestinationController(SettingsStore()),
    );
}

void main() {
  tearDown(() async => locator.reset());

  test('body and label roles use restrained Material-scale typography', () {
    final theme = AppTheme.build(brightness: Brightness.light);
    final text = theme.textTheme;

    expect(text.bodyLarge!.fontSize, 16);
    expect(text.bodyLarge!.fontWeight, FontWeight.w400);
    expect(text.bodyLarge!.height, 1.5);
    expect(text.bodyMedium!.fontSize, 14);
    expect(text.bodyMedium!.fontWeight, FontWeight.w400);
    expect(text.bodyMedium!.height, closeTo(20 / 14, 0.001));
    expect(text.bodySmall!.fontSize, 12);
    expect(text.bodySmall!.fontWeight, FontWeight.w400);
    expect(text.labelLarge!.fontSize, 14);
    expect(text.labelLarge!.fontWeight, FontWeight.w500);
    expect(text.labelMedium!.fontSize, 12);
    expect(text.labelMedium!.fontWeight, FontWeight.w500);
    expect(text.labelSmall!.fontSize, 11);
    expect(text.labelSmall!.fontWeight, FontWeight.w500);
  });

  test('purposeful screen heading roles retain their larger typography', () {
    final text = AppTheme.build(brightness: Brightness.light).textTheme;
    expect(text.displaySmall!.fontSize, 40);
    expect(text.displaySmall!.fontWeight, FontWeight.w700);
    expect(text.headlineSmall!.fontSize, 28);
    expect(text.headlineSmall!.fontWeight, FontWeight.w600);
    expect(text.titleLarge!.fontSize, 26);
    expect(text.titleLarge!.fontWeight, FontWeight.w600);
  });

  for (final textScale in [1.0, 2.0]) {
    testWidgets(
      'Downloads icon centers on its text block at ${textScale}x text',
      (tester) async {
        await _registerSettingsDependencies();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(brightness: Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: SettingsScreen(onOpenApiKey: () {}, onOpenBlockedTags: () {}),
          ),
        );
        await tester.pumpAndSettle();
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
        await tester.pumpAndSettle();

        final downloadIcon = find.byWidgetPredicate(
          (widget) =>
              widget is Icon && widget.icon == PhosphorIconsFill.downloadSimple,
        );
        final destinationText = find.text(
          locator<DownloadDestinationController>().destination
              .peek()
              .folderPath,
        );
        final textBlock = find
            .ancestor(of: destinationText, matching: find.byType(Column))
            .first;
        final iconCenterY = tester.getCenter(downloadIcon).dy;
        final textBlockCenterY = tester.getCenter(textBlock).dy;
        expect((iconCenterY - textBlockCenterY).abs(), lessThan(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Settings groups API key under Content and Downloads under Storage',
    (tester) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _registerSettingsDependencies();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(brightness: Brightness.light),
          home: SettingsScreen(onOpenApiKey: () {}, onOpenBlockedTags: () {}),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Content'), findsOneWidget);
      expect(find.text('Storage'), findsOneWidget);
      expect(find.text('Wallhaven account'), findsNothing);
      expect(find.text('API key'), findsOneWidget);
      expect(find.text('Show NSFW wallpapers'), findsOneWidget);
      expect(find.text('Blocked tags'), findsOneWidget);
      expect(find.text('Downloads'), findsOneWidget);
      expect(find.text('Clear image cache'), findsOneWidget);

      double yOf(String title) => tester.getTopLeft(find.text(title)).dy;
      expect(yOf('Content'), greaterThan(yOf('Appearance')));
      expect(yOf('Storage'), greaterThan(yOf('Content')));
      expect(yOf('API key'), greaterThan(yOf('Blocked tags')));
      expect(yOf('Downloads'), greaterThan(yOf('Storage')));
      expect(yOf('Clear image cache'), greaterThan(yOf('Downloads')));
      expect(tester.takeException(), isNull);
    },
  );

  for (final appearance in [
    (Brightness.light, false, 'light'),
    (Brightness.dark, false, 'dark'),
    (Brightness.dark, true, 'pitch black'),
  ]) {
    testWidgets(
      'Settings removes About and separates groups in ${appearance.$3}',
      (tester) async {
        await _registerSettingsDependencies();
        final theme = AppTheme.build(
          brightness: appearance.$1,
          pitchBlack: appearance.$2,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: SettingsScreen(onOpenApiKey: () {}, onOpenBlockedTags: () {}),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('ABOUT'), findsNothing);
        expect(find.text('Source'), findsNothing);
        expect(find.text('Open source'), findsNothing);
        expect(find.text('Use dynamic color'), findsOneWidget);
        expect(find.text('Pitch black mode'), findsOneWidget);
        expect(find.text('Show NSFW wallpapers'), findsOneWidget);
        expect(find.text('Blocked tags'), findsOneWidget);
        final settingTitle = tester.widget<Text>(
          find.text('Use dynamic color'),
        );
        expect(settingTitle.style!.fontSize, 16);
        expect(settingTitle.style!.fontWeight, FontWeight.w400);
        final settingSubtitle = tester.widget<Text>(
          find.text('Match app colors to your wallpaper.'),
        );
        expect(settingSubtitle.style!.fontSize, 14);
        expect(settingSubtitle.style!.fontWeight, FontWeight.w400);
        final settingsHeading = tester.widget<Text>(find.text('Settings'));
        expect(settingsHeading.style!.fontSize, 40);
        expect(settingsHeading.style!.fontWeight, FontWeight.w700);
        final dynamicColorRow = find.byWidgetPredicate(
          (widget) =>
              widget is M3EListItem && widget.headline == 'Use dynamic color',
        );
        final pitchBlackRow = find.byWidgetPredicate(
          (widget) =>
              widget is M3EListItem && widget.headline == 'Pitch black mode',
        );
        expect(
          tester.getTopLeft(pitchBlackRow).dy -
              tester.getBottomLeft(dynamicColorRow).dy,
          greaterThanOrEqualTo(12),
        );

        await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
        await tester.pumpAndSettle();
        expect(find.text('Wallhaven account'), findsNothing);
        expect(find.text('API key'), findsOneWidget);
        expect(find.text('Downloads'), findsOneWidget);
        expect(find.text('Storage'), findsOneWidget);
        expect(find.text('Clear image cache'), findsOneWidget);
        expect(find.text('ABOUT'), findsNothing);
        expect(find.text('Source'), findsNothing);
        expect(find.text('Open source'), findsNothing);

        final visibleDividers = tester
            .widgetList<Divider>(find.byType(Divider))
            .toList();
        expect(visibleDividers, isNotEmpty);
        for (final divider in visibleDividers) {
          expect(divider.thickness, 1);
          expect(divider.height, 24);
          expect(divider.color, theme.colorScheme.outlineVariant);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
