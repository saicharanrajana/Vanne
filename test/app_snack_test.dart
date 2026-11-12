import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:vanne/app/theme/app_shapes.dart';
import 'package:vanne/app/theme/app_theme.dart';
import 'package:vanne/shared/widgets/app_snack.dart';

Widget _host() => MaterialApp(
  scaffoldMessengerKey: AppSnack.messengerKey,
  theme: AppTheme.build(brightness: Brightness.light),
  home: const Scaffold(body: SizedBox.shrink()),
);

void main() {
  testWidgets('uses the info scheme roles and icon', (tester) async {
    await tester.pumpWidget(_host());
    AppSnack.showRoot('Informational message', type: AppSnackType.info);
    await tester.pump();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    final scheme = AppTheme.build(brightness: Brightness.light).colorScheme;
    expect(snackBar.backgroundColor, scheme.secondaryContainer);
    expect(find.byIcon(PhosphorIconsFill.info), findsOneWidget);
    _expectModerateCorners(snackBar);
  });

  testWidgets('uses the success scheme roles and icon', (tester) async {
    await tester.pumpWidget(_host());
    AppSnack.showRoot('Success message', type: AppSnackType.success);
    await tester.pump();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    final scheme = AppTheme.build(brightness: Brightness.light).colorScheme;
    expect(snackBar.backgroundColor, scheme.primaryContainer);
    expect(find.byIcon(PhosphorIconsFill.checkCircle), findsOneWidget);
  });

  testWidgets('uses the error scheme roles and icon', (tester) async {
    await tester.pumpWidget(_host());
    AppSnack.showRoot('Error message', type: AppSnackType.error);
    await tester.pump();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    final scheme = AppTheme.build(brightness: Brightness.light).colorScheme;
    expect(snackBar.backgroundColor, scheme.errorContainer);
    expect(find.byIcon(PhosphorIconsFill.warningCircle), findsOneWidget);
  });

  testWidgets('uses a short duration', (tester) async {
    await tester.pumpWidget(_host());
    AppSnack.showRoot('Short message', type: AppSnackType.success);
    await tester.pump();

    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.duration, const Duration(milliseconds: 2500));
  });
}

void _expectModerateCorners(SnackBar snackBar) {
  expect(snackBar.shape, isA<RoundedRectangleBorder>());
  final shape = snackBar.shape! as RoundedRectangleBorder;
  expect(shape.borderRadius, BorderRadius.circular(AppShapes.large));
}
