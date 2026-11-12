/// The shared widget-test harness: the real app wired to temporary storage
/// and fake platform boundaries.
///
/// Why this shape:
/// * Real Hive boxes in a temp directory — persistence bugs (bad rollback,
///   missing restore, seed-on-empty) are observable instead of mocked away.
/// * Real controllers/repositories/screens — taps go through the same code
///   the user runs.
/// * Fake HTTP + platform channels — tests never touch the network, the OS
///   picker, or the wallpaper manager, so they are fast and repeatable.
///
/// The one wrinkle: Hive and `compute()` do real I/O, which the fake-async
/// zone cannot complete. Any action that may persist therefore runs through
/// [TestApp.tap] / [TestApp.act], which dispatch inside `tester.runAsync`.
/// Setup and teardown likewise run inside `runAsync`.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:material_ui/material_ui.dart' hide SearchController;
import 'package:network_image_mock/network_image_mock.dart';
import 'package:vanne/app/app.dart';
import 'package:vanne/app/dependencies.dart';
import 'package:vanne/app/router/tab_scroll_coordinator.dart';
import 'package:vanne/core/collections/collection_entry.dart';
import 'package:vanne/core/collections/collections_repository.dart';
import 'package:vanne/core/collections/seed_collections.dart';
import 'package:vanne/core/downloads/download_destination_controller.dart';
import 'package:vanne/core/downloads/download_service.dart';
import 'package:vanne/core/favorites/favorites_repository.dart';
import 'package:vanne/core/security/api_key_store.dart';
import 'package:vanne/core/services/url_launcher_service.dart';
import 'package:vanne/core/services/wallpaper_applier.dart';
import 'package:vanne/core/storage/settings_store.dart';
import 'package:vanne/core/wallpaper/wallpaper_repository.dart';
import 'package:vanne/features/collections/application/collection_explore_controller.dart';
import 'package:vanne/features/collections/application/collections_controller.dart';
import 'package:vanne/features/discover/application/discover_controller.dart';
import 'package:vanne/features/favorites/application/favorites_controller.dart';
import 'package:vanne/features/search/application/search_controller.dart';
import 'package:vanne/features/settings/application/settings_controller.dart';
import 'package:vanne/features/wallpaper_detail/application/wallpaper_detail_controller.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import 'fake_platform.dart';
import 'fake_wallhaven.dart';

/// One app instance: real services, temporary persisted state, fake
/// external boundaries.
///
/// Why actions run through `tester.runAsync`: Hive and `compute()` do real
/// I/O, which the fake-async zone cannot complete. An action performed inside
/// `runAsync` starts its storage work in the real zone, so it finishes before
/// the next pump — no timeouts, no leaked write locks.
final class TestApp {
  TestApp({
    FakeWallhaven? network,
    FakeDownloadStoragePlatform? storagePlatform,
    FakeWallpaperPlatform? wallpaperPlatform,
    FakeUrlLauncher? urlLauncher,
    Map<String, String>? secureStorage,
  }) : network = network ?? FakeWallhaven(),
       storagePlatform = storagePlatform ?? FakeDownloadStoragePlatform(),
       wallpaperPlatform = wallpaperPlatform ?? FakeWallpaperPlatform(),
       urlLauncher = urlLauncher ?? FakeUrlLauncher(),
       secureStorage = secureStorage ?? <String, String>{};

  final FakeWallhaven network;
  final FakeDownloadStoragePlatform storagePlatform;
  final FakeWallpaperPlatform wallpaperPlatform;
  final FakeUrlLauncher urlLauncher;

  /// Survives [restart], like the device keystore would.
  final Map<String, String> secureStorage;

  Directory? _dataDir;

  late SettingsStore settingsStore;
  late FavoritesRepository favoritesRepository;
  late CollectionsRepository collectionsRepository;
  late WallpaperRepository repository;
  late DownloadDestinationController destination;
  late DownloadService downloader;
  late WallpaperApplier applier;
  late TabScrollCoordinator tabs;
  late SettingsController settings;
  late FavoritesController favorites;
  late CollectionsController collections;

  /// Hydration is real I/O; always call through [launch]/[restart].
  Future<void> start() async {
    await locator.reset();
    FlutterSecureStorage.setMockInitialValues(secureStorage);

    final dir = _dataDir ??= Directory.systemTemp.createTempSync('vanne_');
    _installPathProvider(dir.path);

    Hive.init(dir.path);
    settingsStore = SettingsStore();
    await settingsStore.open();
    favoritesRepository = FavoritesRepository();
    await favoritesRepository.open();
    collectionsRepository = CollectionsRepository();
    await collectionsRepository.open();
    await seedCollectionsOnce(settingsStore, collectionsRepository);

    repository = WallpaperRepository(
      client: WallhavenClient(
        apiKeyManager: ApiKeyManager(),
        dio: network.createDio(),
      ),
      keyStore: SecureApiKeyStore(),
      settingsStore: settingsStore,
    );
    await repository.restoreApiKey();

    destination = DownloadDestinationController(
      settingsStore,
      platform: storagePlatform,
    );
    await destination.restore();
    downloader = DownloadService(
      dio: network.createDownloadDio(),
      destinationController: destination,
      platform: storagePlatform,
    );
    applier = WallpaperApplier(platform: wallpaperPlatform);
    tabs = TabScrollCoordinator();

    settings = SettingsController(settingsStore, repository)..restore();
    favorites = FavoritesController(favoritesRepository);
    await favorites.restore();
    collections = CollectionsController(collectionsRepository);
    await collections.restore();

    // Mirrors `bootstrap()` minus the OS/network-heavy pieces.
    locator
      ..registerSingleton<SettingsStore>(settingsStore)
      ..registerSingleton<DownloadDestinationController>(
        destination,
        dispose: (c) => c.dispose(),
      )
      ..registerSingleton<WallpaperRepository>(repository)
      ..registerSingleton<FavoritesRepository>(favoritesRepository)
      ..registerSingleton<CollectionsRepository>(collectionsRepository)
      ..registerSingleton<DownloadService>(downloader)
      ..registerSingleton<WallpaperApplier>(applier)
      ..registerSingleton<TabScrollCoordinator>(
        tabs,
        dispose: (c) => c.dispose(),
      )
      ..registerSingleton<SettingsController>(settings)
      ..registerSingleton<FavoritesController>(
        favorites,
        dispose: (c) => c.dispose(),
      )
      ..registerSingleton<CollectionsController>(collections)
      ..registerFactory<DiscoverController>(
        () => DiscoverController(locator<WallpaperRepository>()),
      )
      ..registerFactory<SearchController>(
        () => SearchController(locator<WallpaperRepository>()),
      )
      ..registerFactoryParam<CollectionExploreController, CollectionEntry, void>(
        (entry, _) => CollectionExploreController(
          entry,
          repository,
          onCoverAvailable: (url) => collections.ensureCover(entry.id, url),
        ),
      )
      ..registerFactoryParam<WallpaperDetailController, String, Wallpaper?>(
        (id, initial) => WallpaperDetailController(
          initial: initial ?? placeholderWallpaper(id),
          repository: repository,
          downloader: downloader,
          applier: applier,
        ),
      )
      ..registerSingleton<FakeUrlLauncher>(urlLauncher)
      ..registerSingleton<UrlLauncherService>(urlLauncher.service);
  }

  /// Starts services (real async) and mounts the real app.
  Future<void> launch(WidgetTester tester) async {
    await tester.runAsync(start);
    await tester.pumpWidget(const WallpaperApp());
    await pumpFrames(tester, 2);
  }

  /// Simulates an app relaunch: unmount, drop services, reopen the SAME
  /// Hive directory, remount. Proves data survives a restart.
  Future<void> restart(WidgetTester tester) async {
    await _stop(tester);
    await tester.runAsync(start);
    await tester.pumpWidget(const WallpaperApp());
    await pumpFrames(tester, 2);
  }

  /// A normal user tap, then the animation pumps a screen transition needs.
  ///
  /// Runs in the fake-async zone so any debounce timers the screen starts
  /// (for example Search's 350 ms trailing edge) run on the test clock.
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
  }

  /// A tap that persists through Hive (favorite, settings, collection, API
  /// key, download destination).
  ///
  /// Dispatched inside `runAsync` so the write starts on the real event loop;
  /// Hive writes started in the fake zone leave their lock pending and hang
  /// later storage work.
  Future<void> persistTap(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await _drain();
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
  }

  /// Text entry (no storage on its own, but keeps user actions uniform).
  Future<void> enterText(
    WidgetTester tester,
    Finder finder,
    String text,
  ) async {
    await tester.enterText(finder, text);
    await tester.pump();
  }

  /// Runs arbitrary app interactions in the real zone. Prefer [tap].
  Future<void> act(
    WidgetTester tester,
    Future<void> Function() action,
  ) async {
    await tester.runAsync(() async {
      await action();
      await _drain();
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
  }

  Future<void> _drain() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  /// Lets any remaining real async work finish, then pumps.
  Future<void> settle(WidgetTester tester, {int rounds = 6}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  /// Like [settle], but fails loudly if [done] never becomes true.
  Future<void> settleUntil(
    WidgetTester tester,
    bool Function() done, {
    required String reason,
    int maxRounds = 40,
  }) async {
    for (var i = 0; i < maxRounds; i++) {
      if (done()) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    if (!done()) {
      throw TestFailure('Timed out waiting for: $reason');
    }
  }

  /// Unmounts the app and releases storage. Called by [appTest].
  Future<void> shutdown(WidgetTester tester) => _stop(tester);

  /// Deletes the temp directory; called by [appTest] after [shutdown].
  void deleteData() {
    _clearPathProvider();
    try {
      _dataDir?.deleteSync(recursive: true);
    } on FileSystemException {
      // Temp cleanup is best-effort and must never fail a test.
    }
    _dataDir = null;
  }

  Future<void> _stop(WidgetTester tester) async {
    // Finite animations (route transitions, overscroll springs) must finish
    // before the tree goes away; disposing mid-animation trips Flutter's
    // "notifier used after dispose" assertions.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    // Dialog-driven writes resume in the fake-async zone after a route pops.
    // Alternate real work and pumps so those continuations reach storage and
    // their I/O completes while the tree can still pump.
    await settle(tester, rounds: 12);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(locator.reset);

    // Close Hive while alternating real waits and pumps. Hive's lock may be
    // waiting on a microtask that only a pump can drain, so closing inside a
    // single runAsync would deadlock.
    var closed = false;
    var closeStarted = false;
    for (var i = 0; i < 40 && !closed; i++) {
      await tester.runAsync(() async {
        if (!closeStarted) {
          closeStarted = true;
          unawaited(Hive.close().then((_) => closed = true));
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await tester.pump(const Duration(milliseconds: 16));
    }
    if (!closed) {
      throw StateError('Hive did not close; storage state would leak');
    }
  }
}

/// Minimal cold-deep-link placeholder, matching production.
Wallpaper placeholderWallpaper(String id) => Wallpaper(
  id: id,
  url: 'https://wallhaven.cc/w/$id',
  source: '',
  purity: Purity.sfw,
  category: Category.general,
  width: 0,
  height: 0,
  resolution: '',
  ratio: '',
  fileSizeBytes: 0,
  fileType: '',
  colors: const [],
  views: 0,
  favorites: 0,
  path: '',
  thumbnails: const Thumbnails(),
);

// ---------------------------------------------------------------------------
// Pump helpers
// ---------------------------------------------------------------------------

/// Pumps a fixed number of frames; never waits on wall-clock time.
Future<void> pumpFrames(
  WidgetTester tester, [
  int frames = 5,
  Duration step = const Duration(milliseconds: 50),
]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

/// Pumps until [finder] matches, or fails with [reason] and the visible text.
///
/// Bounded by frames instead of wall-clock so a slow machine cannot turn a
/// passing run into a failure (or hide a hang behind a long timeout).
Future<void> pumpUntil(
  WidgetTester tester,
  Finder finder, {
  required String reason,
  int maxFrames = 60,
}) async {
  for (var i = 0; i < maxFrames; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 16));
  }
  if (finder.evaluate().isEmpty) {
    throw TestFailure(
      'Timed out after $maxFrames frames waiting for: $reason\n'
      'Visible text: ${_visibleTexts(tester)}',
    );
  }
}

String _visibleTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data)
    .whereType<String>()
    .take(30)
    .join(' | ');

// ---------------------------------------------------------------------------
// Path provider channel
// ---------------------------------------------------------------------------

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void _installPathProvider(String root) {
  TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, (call) async {
        if (call.method == 'getTemporaryDirectory') {
          final dir = Directory('$root/tmp')..createSync(recursive: true);
          return dir.path;
        }
        if (call.method == 'getApplicationDocumentsDirectory') {
          return root;
        }
        if (call.method == 'getApplicationSupportDirectory') {
          return root;
        }
        return null;
      });
}

void _clearPathProvider() {
  TestDefaultBinaryMessengerBinding
      .instance
      .defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, null);
}

/// Loads the bundled Outfit font so text lays out with real metrics.
///
/// Flutter's test default (Ahem) gives every glyph a square advance, which
/// makes headings wrap and overflow in ways the real font never would.
Future<void> loadAppFonts() async {
  final loader = FontLoader('Outfit');
  loader.addFont(rootBundle.load('assets/fonts/Outfit-Variable.ttf'));
  await loader.load();
}

/// Registers a [TestApp] for a widget test and guarantees teardown.
///
/// Images are served by a fake HttpClient, so no journey can reach the
/// network. Example:
///
/// ```dart
/// appTest('discover shows the first page', (tester, app) async {
///   await app.launch(tester);
///   await pumpUntil(tester, find.text('Discover'), reason: 'discover header');
/// });
/// ```
void appTest(
  String description,
  Future<void> Function(WidgetTester tester, TestApp app) body, {
  TestApp Function()? create,
}) {
  setUpAll(loadAppFonts);
  testWidgets(description, (tester) async {
    // Phone-shaped surface: journeys should exercise the real narrow layout,
    // where headers stack and controls scroll instead of the 800x600 default.
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final app = create?.call() ?? TestApp();
    addTearDown(app.deleteData);
    // CachedNetworkImage talks to HttpClient directly; serve a fake image so
    // no journey can reach the network or wait on image I/O.
    await mockNetworkImagesFor(() async {
      try {
        await body(tester, app);
      } finally {
        await app.shutdown(tester);
      }
    });
  });
}

/// Exposes the locator as a typed getter for assertions in journeys.
T read<T extends Object>() => GetIt.instance<T>();
