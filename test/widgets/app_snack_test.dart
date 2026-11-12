import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vanne/shared/widgets/app_snack.dart';

/// AppSnack is the app's only snackbar surface. Two behaviours matter and
/// are easy to regress:
/// * duplicate suppression within one session (no snack backlogs),
/// * a fresh app shell gets fresh suppression state (the first confirmation
///   of a new session must never be swallowed by a previous one).
void main() {
  Widget host() => MaterialApp(
    scaffoldMessengerKey: AppSnack.messengerKey,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: () => AppSnack.show(context, 'Saved to Pictures'),
                child: const Text('save'),
              ),
              TextButton(
                onPressed: () => AppSnack.show(context, 'Download failed'),
                child: const Text('fail'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  testWidgets('a repeated message within the window shows once', (tester) async {
    await tester.pumpWidget(host());

    await tester.tap(find.text('save'));
    await tester.pump();
    await tester.tap(find.text('save'));
    await tester.pump();

    expect(find.text('Saved to Pictures'), findsOneWidget);
  });

  testWidgets('a different message is not suppressed', (tester) async {
    await tester.pumpWidget(host());

    await tester.tap(find.text('save'));
    await tester.pump();
    await tester.tap(find.text('fail'));
    await tester.pump();

    expect(find.text('Download failed'), findsOneWidget);
  });

  testWidgets('a new app shell shows the same message again', (tester) async {
    await tester.pumpWidget(host());
    await tester.tap(find.text('save'));
    await tester.pump();
    expect(find.text('Saved to Pictures'), findsOneWidget);

    // Tear the shell down and start a fresh one, like an app relaunch or a
    // second widget test in the same process.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(host());

    await tester.tap(find.text('save'));
    await tester.pump();

    expect(
      find.text('Saved to Pictures'),
      findsOneWidget,
      reason: 'suppression state must not outlive its messenger',
    );
  });
}
