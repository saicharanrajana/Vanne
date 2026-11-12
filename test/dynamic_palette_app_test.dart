import 'dart:async';
import 'dart:typed_data';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart' hide SearchController;
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:vanne/app/app.dart';
import 'package:vanne/app/dependencies.dart';
import 'package:vanne/app/router/tab_scroll_coordinator.dart';
import 'package:vanne/core/collections/collections_repository.dart';
import 'package:vanne/core/domain/feed_filter.dart';
import 'package:vanne/core/favorites/favorites_repository.dart';
import 'package:vanne/core/storage/settings_store.dart';
import 'package:vanne/core/downloads/download_destination_controller.dart';
import 'package:vanne/core/wallpaper/wallpaper_repository.dart';
import 'package:vanne/features/collections/application/collections_controller.dart';
import 'package:vanne/features/discover/application/discover_controller.dart';
import 'package:vanne/features/favorites/application/favorites_controller.dart';
import 'package:vanne/features/search/application/search_controller.dart';
import 'package:vanne/features/settings/application/settings_controller.dart';
import 'package:vanne/features/settings/presentation/settings_screen.dart';

const _events = 'com.saicharanrajana.vanne/dynamic_palette';
const _codec = StandardMethodCodec();

class _EmptyRepository implements WallpaperRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<SearchOutcome> search({
    String query = '',
    Set<WallhavenColor> colors = const {},
    List<WallhavenCategory> categories = const [],
    FeedFilter filter = const FeedFilter(),
    int page = 1,
    String? seed,
  }) async => const SearchOutcome(
    page: PaginatedResult<Wallpaper>(
      items: [],
      meta: SearchMeta(currentPage: 1, lastPage: 1, perPage: 24),
    ),
    nsfwClamped: false,
  );
}

List<int> _palette(int seed) {
  // The platform plugin's public API still uses CorePalette.
  // ignore: deprecated_member_use
  return Int32List.fromList(CorePalette.of(seed).asList());
}

Future<SettingsController> _registerDependencies() async {
  final repository = _EmptyRepository();
  final favorites = FavoritesController(FavoritesRepository());
  final collections = CollectionsController(CollectionsRepository());
  await favorites.restore();
  await collections.restore();
  final settings = SettingsController(SettingsStore(), repository);
  locator
    ..registerSingleton<SettingsController>(settings)
    ..registerSingleton<FavoritesController>(favorites)
    ..registerSingleton<CollectionsController>(collections)
    ..registerSingleton<TabScrollCoordinator>(
      TabScrollCoordinator(),
      dispose: (value) => value.dispose(),
    )
    ..registerFactory<DiscoverController>(() => DiscoverController(repository))
    ..registerFactory<SearchController>(() => SearchController(repository))
    ..registerSingleton<DownloadDestinationController>(
      DownloadDestinationController(SettingsStore()),
    );
  return settings;
}

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _notify(WidgetTester tester) async {
  tester.binding.channelBuffers.push(
    _events,
    _codec.encodeMethodCall(const MethodCall('changed')),
    (_) {},
  );
  await _flush(tester);
}

MaterialApp _app(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('system palette events update the live app without remounting', (
    tester,
  ) async {
    final settings = await _registerDependencies();
    final messenger = tester.binding.defaultBinaryMessenger;
    var current = _palette(0xff3366cc);
    var reads = 0;
    Completer<List<int>>? pending;
    var fail = false;
    var unavailable = false;
    messenger.setMockMethodCallHandler(DynamicColorPlugin.channel, (_) async {
      reads++;
      if (fail) throw PlatformException(code: 'temporarily_unavailable');
      if (unavailable) return null;
      return pending == null ? current : await pending.future;
    });

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await _flush(tester);
      messenger.setMockMethodCallHandler(DynamicColorPlugin.channel, null);
      messenger.setMockMethodCallHandler(const MethodChannel(_events), null);
      await locator.reset();
    });

    await tester.pumpWidget(const WallpaperApp());
    await _flush(tester);
    expect(reads, 1);
    expect(
      _app(tester).theme!.colorScheme.primary,
      // ignore: deprecated_member_use
      CorePalette.fromList(current).toColorScheme().harmonized().primary,
    );
    final initialPrimary = _app(tester).theme!.colorScheme.primary;
    final router = _app(tester).routerConfig;
    await tester.tap(find.text('Settings').last);
    await _flush(tester);
    final settingsElement = tester.element(find.byType(SettingsScreen));

    // Identical platform values must not publish a new theme.
    final unchangedTheme = _app(tester).theme;
    await _notify(tester);
    expect(identical(_app(tester).theme, unchangedTheme), isTrue);

    current = _palette(0xffee6600);
    await _notify(tester);
    final updatedPrimary = _app(tester).theme!.colorScheme.primary;
    expect(updatedPrimary, isNot(initialPrimary));
    expect(identical(_app(tester).routerConfig, router), isTrue);
    expect(tester.element(find.byType(SettingsScreen)), same(settingsElement));
    expect(Theme.of(settingsElement).colorScheme.primary, updatedPrimary);

    // An event during a read requires one follow-up read, not concurrent reads.
    final beforeBurst = reads;
    final delayed = Completer<List<int>>();
    pending = delayed;
    await _notify(tester);
    expect(_app(tester).theme!.colorScheme.primary, updatedPrimary);
    await _notify(tester);
    await _notify(tester);
    expect(reads, beforeBurst + 1);
    current = _palette(0xff009955);
    pending = null;
    delayed.complete(_palette(0xffbb2244));
    await _flush(tester);
    expect(reads, beforeBurst + 2);
    final latestPrimary = _app(tester).theme!.colorScheme.primary;
    expect(latestPrimary, isNot(updatedPrimary));
    expect(
      latestPrimary,
      // ignore: deprecated_member_use
      CorePalette.fromList(current).toColorScheme().harmonized().primary,
    );

    fail = true;
    await _notify(tester);
    expect(_app(tester).theme!.colorScheme.primary, latestPrimary);
    fail = false;
    unavailable = true;
    await _notify(tester);
    expect(_app(tester).theme!.colorScheme.primary, latestPrimary);
    unavailable = false;

    settings.dynamicColor.value = false;
    await _flush(tester);
    final fixedPrimary = _app(tester).theme!.colorScheme.primary;
    current = _palette(0xff9955dd);
    await _notify(tester);
    expect(_app(tester).theme!.colorScheme.primary, fixedPrimary);
    settings.dynamicColor.value = true;
    settings.pitchBlack.value = true;
    settings.themeMode.value = AppThemeMode.dark;
    await _flush(tester);
    expect(_app(tester).theme!.colorScheme.primary, isNot(fixedPrimary));
    expect(
      _app(tester).darkTheme!.colorScheme.surface,
      const Color(0xff000000),
    );
    expect(identical(_app(tester).routerConfig, router), isTrue);
    expect(
      Theme.of(settingsElement).colorScheme.surface,
      const Color(0xff000000),
    );

    // A pending platform read must not publish after the app is disposed.
    final lastRead = Completer<List<int>>();
    pending = lastRead;
    await _notify(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    lastRead.complete(_palette(0xffcc4488));
    await _flush(tester);
    final afterDispose = reads;
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await _flush(tester);
    expect(reads, afterDispose);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resume reconciles external palette changes without an event', (
    tester,
  ) async {
    await _registerDependencies();
    final messenger = tester.binding.defaultBinaryMessenger;
    var current = _palette(0xff3366cc);
    messenger.setMockMethodCallHandler(
      DynamicColorPlugin.channel,
      (_) async => current,
    );
    // No platform notifications are sent in this journey.
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await _flush(tester);
      messenger.setMockMethodCallHandler(DynamicColorPlugin.channel, null);
      messenger.setMockMethodCallHandler(const MethodChannel(_events), null);
      await locator.reset();
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const WallpaperApp());
    await _flush(tester);
    final primary = _app(tester).theme!.colorScheme.primary;
    final router = _app(tester).routerConfig;
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    current = _palette(0xffee6600);
    for (final state in [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await _flush(tester);
    expect(_app(tester).theme!.colorScheme.primary, isNot(primary));
    expect(identical(_app(tester).routerConfig, router), isTrue);
    expect(tester.takeException(), isNull);
  });
}
