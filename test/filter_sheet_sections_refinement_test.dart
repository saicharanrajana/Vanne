import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vanne/app/theme/app_theme.dart';
import 'package:vanne/core/domain/feed_filter.dart';
import 'package:vanne/shared/widgets/feed_filter_sheet.dart';

void main() {
  testWidgets('filter sections use readable case and low-contrast dividers', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1500);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final theme = AppTheme.build(brightness: Brightness.light);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: FeedFilterSheetContent(
            initial: FeedFilter(sorting: FeedSorting.popular),
          ),
        ),
      ),
    );

    expect(find.text('Sort by'), findsOneWidget);
    expect(find.text('Popular time window'), findsOneWidget);
    expect(find.text('Categories'), findsOneWidget);
    expect(find.text('Minimum resolution'), findsOneWidget);
    expect(find.text('SORT BY'), findsNothing);

    final dividers = tester.widgetList<Divider>(find.byType(Divider)).toList();
    expect(dividers, hasLength(3));
    for (final divider in dividers) {
      expect(divider.thickness, 1);
      expect(divider.color, theme.colorScheme.outlineVariant);
      expect(divider.height, greaterThanOrEqualTo(24));
    }
  });

  testWidgets(
    'popular time window hides and returns with its previous choice',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 1500);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(brightness: Brightness.light),
          home: const Scaffold(
            body: FeedFilterSheetContent(
              initial: FeedFilter(
                sorting: FeedSorting.popular,
                topRange: FeedTopRange.week,
              ),
            ),
          ),
        ),
      );

      expect(find.text('This week'), findsOneWidget);
      expect(find.byType(Divider), findsNWidgets(3));

      await tester.tap(find.text('Newest'));
      await tester.pump();
      expect(find.text('Popular time window'), findsNothing);
      expect(find.text('This week'), findsNothing);
      expect(find.byType(Divider), findsNWidgets(2));

      await tester.tap(find.text('Popular'));
      await tester.pump();
      expect(find.text('Popular time window'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
      final weekChip = tester.widget<M3EChip>(
        find.ancestor(
          of: find.text('This week'),
          matching: find.byType(M3EChip),
        ),
      );
      expect(weekChip.selected, isTrue);
    },
  );
}
