import 'package:get_it/get_it.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

import '../core/collections/collection_entry.dart';
import '../core/collections/collections_repository.dart';
import '../core/collections/seed_collections.dart';
import '../core/downloads/download_destination_controller.dart';
import '../core/downloads/download_service.dart';
import '../core/favorites/favorites_repository.dart';
import '../core/security/api_key_store.dart';
import '../core/services/url_launcher_service.dart';
import '../core/services/wallpaper_applier.dart';
import '../core/storage/settings_store.dart';
import '../core/wallpaper/wallpaper_repository.dart';
import '../features/collections/application/collection_explore_controller.dart';
import '../features/collections/application/collections_controller.dart';
import '../features/discover/application/discover_controller.dart';
import '../features/favorites/application/favorites_controller.dart';
import '../features/search/application/search_controller.dart';
import '../features/wallpaper_detail/application/wallpaper_detail_controller.dart';
import '../features/settings/application/settings_controller.dart';
import 'router/tab_scroll_coordinator.dart';

/// Global service locator. Registered once in [bootstrap]; everything is
/// concrete — interfaces exist only where a real seam (platform, secure
/// storage) justifies them.
final locator = GetIt.instance;

/// Registers application services and controllers.
Future<void> bootstrap() async {
  // TODO(guard): verify Android overrides are applied at startup (debug
  //  builds only). Call a `verifyOverrides` MethodChannel method on
  //  system_wallpaper (see TODO in SystemWallpaperPlugin.kt) and log/surface
  //  a warning if the cached engine is missing — that means
  //  `tool/apply_android_overrides.sh` was never run after recreating
  //  android/, and Crop and set will restart the app on wallpaper RRO changes.
  //  Details: ARCHITECTURE.md → "App-level Android overrides".
  await Hive.initFlutter();

  final settingsStore = SettingsStore();
  await settingsStore.open();

  final favoritesRepository = FavoritesRepository();
  await favoritesRepository.open();

  final collectionsRepository = CollectionsRepository();
  await collectionsRepository.open();
  if ((await collectionsRepository.getAll()).isEmpty) {
    await collectionsRepository.addAll(seedCollections);
  }

  final repository = WallpaperRepository(
    client: WallhavenClient(apiKeyManager: ApiKeyManager()),
    keyStore: SecureApiKeyStore(),
    settingsStore: settingsStore,
  );
  await repository.restoreApiKey();

  // Download destination: persisted parent-folder grant, re-validated on
  // startup so a revoked folder is visible in Settings instead of failing
  // silently at download time.
  final downloadDestination = DownloadDestinationController(settingsStore);
  await downloadDestination.restore();

  locator
    ..registerSingleton<SettingsStore>(settingsStore)
    ..registerSingleton<DownloadDestinationController>(
      downloadDestination,
      dispose: (controller) => controller.dispose(),
    )
    ..registerSingleton<WallpaperRepository>(repository)
    ..registerSingleton<FavoritesRepository>(favoritesRepository)
    ..registerSingleton<CollectionsRepository>(collectionsRepository)
    ..registerLazySingleton<DownloadService>(
      () => DownloadService(
        destinationController: locator<DownloadDestinationController>(),
      ),
    )
    ..registerLazySingleton<WallpaperApplier>(WallpaperApplier.new)
    ..registerLazySingleton<UrlLauncherService>(UrlLauncherService.new)
    ..registerSingleton<TabScrollCoordinator>(
      TabScrollCoordinator(),
      dispose: (coordinator) => coordinator.dispose(),
    );

  // Controllers owning app-wide reactive state.
  final settingsController = SettingsController(settingsStore, repository)
    ..restore();
  locator.registerSingleton<SettingsController>(settingsController);

  final favoritesController = FavoritesController(favoritesRepository);
  await favoritesController.restore();
  locator.registerSingleton<FavoritesController>(favoritesController);

  final collectionsController = CollectionsController(collectionsRepository);
  await collectionsController.restore();
  locator.registerSingleton<CollectionsController>(collectionsController);

  locator
    ..registerFactory<DiscoverController>(
      () => DiscoverController(locator<WallpaperRepository>()),
    )
    ..registerFactory<SearchController>(
      () => SearchController(locator<WallpaperRepository>()),
    )
    ..registerFactoryParam<CollectionExploreController, CollectionEntry, void>(
      (entry, _) => CollectionExploreController(entry, repository),
    )
    // Detail controllers are per-screen instances; [initial] carries the
    // listing entry for an instant Hero, or null on cold deep links.
    ..registerFactoryParam<WallpaperDetailController, String, Wallpaper?>(
      (id, initial) => WallpaperDetailController(
        initial: initial ?? _placeholderWallpaper(id),
        repository: repository,
        downloader: locator<DownloadService>(),
        applier: locator<WallpaperApplier>(),
      ),
    );
}

/// Minimal placeholder for cold deep links; [loadDetails] fills it in.
Wallpaper _placeholderWallpaper(String id) => Wallpaper(
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
