import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vanne/app/dependencies.dart';
import 'package:vanne/app/theme/app_theme.dart';
import 'package:vanne/core/collections/collections_repository.dart';
import 'package:vanne/features/collections/application/collections_controller.dart';
import 'package:vanne/features/collections/presentation/widgets/create_collection_dialog.dart';

void main() {
  tearDown(() async {
    await locator.reset();
  });

  testWidgets('new collection dialog opens with its text field', (
    tester,
  ) async {
    locator.registerSingleton<CollectionsController>(
      CollectionsController(CollectionsRepository()),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(brightness: Brightness.light),
        home: const Scaffold(body: CreateCollectionDialogContent()),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('New collection'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
