import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vanne/app/app_startup.dart';
import 'package:vanne/app/dependencies.dart';

/// Why: startup used to await all storage/service initialization before the
/// first frame, leaving the window blank. These tests pin the replacement
/// contract: a themed surface paints immediately, the real app mounts only
/// after initialization succeeds, and a failure offers a retry that starts
/// from clean service registrations.

class _PartialService {}

class _ReadyApp extends StatelessWidget {
  const _ReadyApp();

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(home: Scaffold(body: Text('app ready')));
}

void main() {
  tearDown(() async {
    if (locator.isRegistered<_PartialService>()) await locator.reset();
  });

  testWidgets('launch surface paints before initialization completes', (
    tester,
  ) async {
    final initialized = Completer<void>();
    await tester.pumpWidget(
      AppStartup(
        initialize: () => initialized.future,
        child: const _ReadyApp(),
      ),
    );

    expect(find.byKey(const ValueKey('startup-surface')), findsOneWidget);
    expect(find.text('app ready'), findsNothing);

    initialized.complete();
    await tester.pumpAndSettle();

    expect(find.text('app ready'), findsOneWidget);
    expect(find.byKey(const ValueKey('startup-surface')), findsNothing);
  });

  testWidgets('failed initialization can be retried from clean services', (
    tester,
  ) async {
    var attempts = 0;
    Future<void> initialize() async {
      attempts++;
      // Mimic bootstrap registering services incrementally before failing.
      locator.registerSingleton<_PartialService>(_PartialService());
      if (attempts == 1) throw StateError('storage unavailable');
    }

    await tester.pumpWidget(
      AppStartup(initialize: initialize, child: const _ReadyApp()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not start'), findsOneWidget);
    expect(find.text('app ready'), findsNothing);
    // The partial registration was released, so retry can register again.
    expect(locator.isRegistered<_PartialService>(), isFalse);

    await tester.tap(find.byKey(const ValueKey('startup-retry')));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('app ready'), findsOneWidget);
    expect(locator.isRegistered<_PartialService>(), isTrue);
  });
}
