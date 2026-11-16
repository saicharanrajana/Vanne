// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// AutoRouterGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

part of 'app_route.dart';

/// generated route for
/// [ApiKeySettingsPage]
class ApiKeySettingsRoute extends PageRouteInfo<void> {
  const ApiKeySettingsRoute({List<PageRouteInfo>? children})
    : super(ApiKeySettingsRoute.name, initialChildren: children);

  static const String name = 'ApiKeySettingsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const ApiKeySettingsPage();
    },
  );
}

/// generated route for
/// [BlockedTagsPage]
class BlockedTagsRoute extends PageRouteInfo<void> {
  const BlockedTagsRoute({List<PageRouteInfo>? children})
    : super(BlockedTagsRoute.name, initialChildren: children);

  static const String name = 'BlockedTagsRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const BlockedTagsPage();
    },
  );
}

/// generated route for
/// [CollectionExplorePage]
class CollectionExploreRoute extends PageRouteInfo<CollectionExploreRouteArgs> {
  CollectionExploreRoute({
    required String collectionId,
    Key? key,
    List<PageRouteInfo>? children,
  }) : super(
         CollectionExploreRoute.name,
         args: CollectionExploreRouteArgs(collectionId: collectionId, key: key),
         rawPathParams: {'collectionId': collectionId},
         initialChildren: children,
       );

  static const String name = 'CollectionExploreRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<CollectionExploreRouteArgs>(
        orElse: () => CollectionExploreRouteArgs(
          collectionId: pathParams.getString('collectionId'),
        ),
      );
      return CollectionExplorePage(
        collectionId: args.collectionId,
        key: args.key,
      );
    },
  );
}

class CollectionExploreRouteArgs {
  const CollectionExploreRouteArgs({required this.collectionId, this.key});

  final String collectionId;

  final Key? key;

  @override
  String toString() {
    return 'CollectionExploreRouteArgs{collectionId: $collectionId, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! CollectionExploreRouteArgs) return false;
    return collectionId == other.collectionId && key == other.key;
  }

  @override
  int get hashCode => collectionId.hashCode ^ key.hashCode;
}

/// generated route for
/// [CollectionsTabPage]
class CollectionsTabRoute extends PageRouteInfo<void> {
  const CollectionsTabRoute({List<PageRouteInfo>? children})
    : super(CollectionsTabRoute.name, initialChildren: children);

  static const String name = 'CollectionsTabRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const CollectionsTabPage();
    },
  );
}

/// generated route for
/// [DiscoverTabPage]
class DiscoverTabRoute extends PageRouteInfo<void> {
  const DiscoverTabRoute({List<PageRouteInfo>? children})
    : super(DiscoverTabRoute.name, initialChildren: children);

  static const String name = 'DiscoverTabRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const DiscoverTabPage();
    },
  );
}

/// generated route for
/// [FavoritesTabPage]
class FavoritesTabRoute extends PageRouteInfo<void> {
  const FavoritesTabRoute({List<PageRouteInfo>? children})
    : super(FavoritesTabRoute.name, initialChildren: children);

  static const String name = 'FavoritesTabRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const FavoritesTabPage();
    },
  );
}

/// generated route for
/// [FeedFilterSheetPage]
class FeedFilterSheetRoute extends PageRouteInfo<FeedFilterSheetRouteArgs> {
  FeedFilterSheetRoute({
    required FeedFilter initial,
    Key? key,
    List<PageRouteInfo>? children,
  }) : super(
         FeedFilterSheetRoute.name,
         args: FeedFilterSheetRouteArgs(initial: initial, key: key),
         initialChildren: children,
       );

  static const String name = 'FeedFilterSheetRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<FeedFilterSheetRouteArgs>();
      return FeedFilterSheetPage(initial: args.initial, key: args.key);
    },
  );
}

class FeedFilterSheetRouteArgs {
  const FeedFilterSheetRouteArgs({required this.initial, this.key});

  final FeedFilter initial;

  final Key? key;

  @override
  String toString() {
    return 'FeedFilterSheetRouteArgs{initial: $initial, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FeedFilterSheetRouteArgs) return false;
    return initial == other.initial && key == other.key;
  }

  @override
  int get hashCode => initial.hashCode ^ key.hashCode;
}

/// generated route for
/// [FilteredWallpapersPage]
class FilteredWallpapersRoute
    extends PageRouteInfo<FilteredWallpapersRouteArgs> {
  FilteredWallpapersRoute({
    String title = '',
    String query = '',
    String colors = '',
    Key? key,
    List<PageRouteInfo>? children,
  }) : super(
         FilteredWallpapersRoute.name,
         args: FilteredWallpapersRouteArgs(
           title: title,
           query: query,
           colors: colors,
           key: key,
         ),
         rawQueryParams: {'title': title, 'q': query, 'colors': colors},
         initialChildren: children,
       );

  static const String name = 'FilteredWallpapersRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final queryParams = data.queryParams;
      final args = data.argsAs<FilteredWallpapersRouteArgs>(
        orElse: () => FilteredWallpapersRouteArgs(
          title: queryParams.getString('title', ''),
          query: queryParams.getString('q', ''),
          colors: queryParams.getString('colors', ''),
        ),
      );
      return FilteredWallpapersPage(
        title: args.title,
        query: args.query,
        colors: args.colors,
        key: args.key,
      );
    },
  );
}

class FilteredWallpapersRouteArgs {
  const FilteredWallpapersRouteArgs({
    this.title = '',
    this.query = '',
    this.colors = '',
    this.key,
  });

  final String title;

  final String query;

  final String colors;

  final Key? key;

  @override
  String toString() {
    return 'FilteredWallpapersRouteArgs{title: $title, query: $query, colors: $colors, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FilteredWallpapersRouteArgs) return false;
    return title == other.title &&
        query == other.query &&
        colors == other.colors &&
        key == other.key;
  }

  @override
  int get hashCode =>
      title.hashCode ^ query.hashCode ^ colors.hashCode ^ key.hashCode;
}

/// generated route for
/// [MainShellPage]
class MainShellRoute extends PageRouteInfo<void> {
  const MainShellRoute({List<PageRouteInfo>? children})
    : super(MainShellRoute.name, initialChildren: children);

  static const String name = 'MainShellRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const MainShellPage();
    },
  );
}

/// generated route for
/// [RemoveApiKeyDialogPage]
class RemoveApiKeyDialogRoute extends PageRouteInfo<void> {
  const RemoveApiKeyDialogRoute({List<PageRouteInfo>? children})
    : super(RemoveApiKeyDialogRoute.name, initialChildren: children);

  static const String name = 'RemoveApiKeyDialogRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const RemoveApiKeyDialogPage();
    },
  );
}

/// generated route for
/// [SearchPage]
class SearchRoute extends PageRouteInfo<SearchRouteArgs> {
  SearchRoute({String? query, Key? key, List<PageRouteInfo>? children})
    : super(
        SearchRoute.name,
        args: SearchRouteArgs(query: query, key: key),
        rawQueryParams: {'q': query},
        initialChildren: children,
      );

  static const String name = 'SearchRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final queryParams = data.queryParams;
      final args = data.argsAs<SearchRouteArgs>(
        orElse: () => SearchRouteArgs(query: queryParams.optString('q')),
      );
      return SearchPage(query: args.query, key: args.key);
    },
  );
}

class SearchRouteArgs {
  const SearchRouteArgs({this.query, this.key});

  final String? query;

  final Key? key;

  @override
  String toString() {
    return 'SearchRouteArgs{query: $query, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SearchRouteArgs) return false;
    return query == other.query && key == other.key;
  }

  @override
  int get hashCode => query.hashCode ^ key.hashCode;
}

/// generated route for
/// [SetWallpaperDialogPage]
class SetWallpaperDialogRoute
    extends PageRouteInfo<SetWallpaperDialogRouteArgs> {
  SetWallpaperDialogRoute({
    required WallpaperDetailController controller,
    Key? key,
    List<PageRouteInfo>? children,
  }) : super(
         SetWallpaperDialogRoute.name,
         args: SetWallpaperDialogRouteArgs(controller: controller, key: key),
         initialChildren: children,
       );

  static const String name = 'SetWallpaperDialogRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final args = data.argsAs<SetWallpaperDialogRouteArgs>();
      return SetWallpaperDialogPage(controller: args.controller, key: args.key);
    },
  );
}

class SetWallpaperDialogRouteArgs {
  const SetWallpaperDialogRouteArgs({required this.controller, this.key});

  final WallpaperDetailController controller;

  final Key? key;

  @override
  String toString() {
    return 'SetWallpaperDialogRouteArgs{controller: $controller, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SetWallpaperDialogRouteArgs) return false;
    return controller == other.controller && key == other.key;
  }

  @override
  int get hashCode => controller.hashCode ^ key.hashCode;
}

/// generated route for
/// [SettingsTabPage]
class SettingsTabRoute extends PageRouteInfo<void> {
  const SettingsTabRoute({List<PageRouteInfo>? children})
    : super(SettingsTabRoute.name, initialChildren: children);

  static const String name = 'SettingsTabRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      return const SettingsTabPage();
    },
  );
}

/// generated route for
/// [WallpaperDetailPage]
class WallpaperDetailRoute extends PageRouteInfo<WallpaperDetailRouteArgs> {
  WallpaperDetailRoute({
    required String wallpaperId,
    Wallpaper? initial,
    String heroScope = '',
    Key? key,
    List<PageRouteInfo>? children,
  }) : super(
         WallpaperDetailRoute.name,
         args: WallpaperDetailRouteArgs(
           wallpaperId: wallpaperId,
           initial: initial,
           heroScope: heroScope,
           key: key,
         ),
         rawPathParams: {'wallpaperId': wallpaperId},
         initialChildren: children,
       );

  static const String name = 'WallpaperDetailRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (data) {
      final pathParams = data.inheritedPathParams;
      final args = data.argsAs<WallpaperDetailRouteArgs>(
        orElse: () => WallpaperDetailRouteArgs(
          wallpaperId: pathParams.getString('wallpaperId'),
        ),
      );
      return WallpaperDetailPage(
        wallpaperId: args.wallpaperId,
        initial: args.initial,
        heroScope: args.heroScope,
        key: args.key,
      );
    },
  );
}

class WallpaperDetailRouteArgs {
  const WallpaperDetailRouteArgs({
    required this.wallpaperId,
    this.initial,
    this.heroScope = '',
    this.key,
  });

  final String wallpaperId;

  final Wallpaper? initial;

  final String heroScope;

  final Key? key;

  @override
  String toString() {
    return 'WallpaperDetailRouteArgs{wallpaperId: $wallpaperId, initial: $initial, heroScope: $heroScope, key: $key}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! WallpaperDetailRouteArgs) return false;
    return wallpaperId == other.wallpaperId &&
        initial == other.initial &&
        heroScope == other.heroScope &&
        key == other.key;
  }

  @override
  int get hashCode =>
      wallpaperId.hashCode ^
      initial.hashCode ^
      heroScope.hashCode ^
      key.hashCode;
}
