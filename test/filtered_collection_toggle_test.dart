import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:network_image_mock/network_image_mock.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:vanne/app/dependencies.dart';
import 'package:vanne/app/theme/app_theme.dart';
import 'package:vanne/core/collections/collection_entry.dart';
import 'package:vanne/core/collections/collections_repository.dart';
import 'package:vanne/core/domain/feed_filter.dart';
import 'package:vanne/core/favorites/favorites_repository.dart';
import 'package:vanne/core/storage/settings_store.dart';
import 'package:vanne/core/wallpaper/wallpaper_repository.dart';
import 'package:vanne/features/collections/application/collections_controller.dart';
import 'package:vanne/features/favorites/application/favorites_controller.dart';
import 'package:vanne/features/filtered/presentation/filtered_wallpapers_screen.dart';
import 'package:vanne/features/settings/application/settings_controller.dart';
import 'package:vanne/shared/widgets/app_snack.dart';

/// App-level coverage for the saved-query collection toggle.
///
/// The screen opened from a tag/colour must be able to *remove* its collection
/// again: the icon, the accessible state and the persisted row all have to
/// follow the toggle, not just the appearance.

/// In-memory stand-in for the Hive box — the persistence boundary this test
/// asserts against (the UI must not only repaint, it must write).
final class _MemoryCollectionsRepository implements CollectionsRepository {
  final List<CollectionEntry> rows = <CollectionEntry>[];
  int addCalls = 0;
  int removeCalls = 0;

  /// Set to hold a create/delete open, so a double tap can be raced.
  Completer<void>? gate;

  @override
  Future<void> open() async {}

  @override
  Future<List<CollectionEntry>> getAll() async => List.of(rows);

  @override
  Future<bool> add(CollectionEntry entry) async {
    addCalls++;
    final pending = gate;
    if (pending != null) await pending.future;
    if (rows.any((e) => e.id == entry.id)) return false;
    rows.add(entry);
    return true;
  }

  @override
  Future<void> addAll(List<CollectionEntry> entries) async =>
      rows.addAll(entries);

  @override
  Future<void> removeMany(Set<String> ids) async {
    removeCalls++;
    final pending = gate;
    if (pending != null) await pending.future;
    rows.removeWhere((e) => ids.contains(e.id));
  }
}

final class _StubRepository implements WallpaperRepository {
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
      items: <Wallpaper>[],
      meta: SearchMeta(currentPage: 1, lastPage: 1, perPage: 24),
    ),
    nsfwClamped: false,
  );
}

late _MemoryCollectionsRepository _repo;
late CollectionsController _collections;

Future<void> _registerDependencies() async {
  final repository = _StubRepository();
  _repo = _MemoryCollectionsRepository();
  _collections = CollectionsController(_repo);
  await _collections.restore();
  final favorites = FavoritesController(FavoritesRepository());
  await favorites.restore();
  locator
    ..registerSingleton<WallpaperRepository>(repository)
    ..registerSingleton<CollectionsController>(_collections)
    ..registerSingleton<FavoritesController>(favorites)
    ..registerSingleton<SettingsController>(
      SettingsController(SettingsStore(), repository),
    );
}

Widget _host(Widget child) => MaterialApp(
  theme: AppTheme.build(brightness: Brightness.light),
  scaffoldMessengerKey: AppSnack.messengerKey,
  home: child,
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _toggle(String label) => find.byWidgetPredicate(
  (widget) => widget is M3EIconButton && widget.tooltip == label,
  description: 'collection toggle with tooltip "$label"',
);

final _saveButton = _toggle('Save to Collections');
final _removeButton = _toggle('Remove from Collections');

/// The single app-bar collection action, whatever state it is in. Persistence
/// is optimistic, so the label may already have flipped when a tap is pending.
final _collectionToggle = find.byWidgetPredicate(
  (widget) =>
      widget is M3EIconButton &&
      (widget.tooltip == 'Save to Collections' ||
          widget.tooltip == 'Remove from Collections'),
  description: 'collection toggle in either state',
);

void main() {
  tearDown(() async {
    _repo.gate = null;
    await locator.reset();
  });

  testWidgets('tag query saves, removes and re-saves its collection', (
    tester,
  ) async {
    await _registerDependencies();

    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(
        _host(
          FilteredWallpapersScreen(
            title: 'nature',
            query: 'nature',
            onOpenWallpaper: (_) {},
            onBack: () {},
          ),
        ),
      );
      await _settle(tester);

      // 1. Unsaved: outline bookmark, announced as "Save".
      expect(_saveButton, findsOneWidget);
      var button = tester.widget<M3EIconButton>(_saveButton);
      expect(button.isSelected, isFalse);
      expect((button.icon as Icon).icon, PhosphorIconsBold.bookmarkSimple);
      expect(
        (button.selectedIcon as Icon).icon,
        PhosphorIconsFill.bookmarkSimple,
      );
      // Touch target is unchanged by the toggle work.
      final idleSize = tester.getSize(_saveButton);
      expect(idleSize.width, greaterThanOrEqualTo(48));
      expect(idleSize.height, greaterThanOrEqualTo(48));
      expect(_repo.rows, isEmpty);

      // 2. Save, held open by the repo gate to prove taps cannot race.
      _repo.gate = Completer<void>();
      await tester.tap(_saveButton);
      await tester.pump();
      expect(
        tester.widget<M3EIconButton>(_collectionToggle).onPressed,
        isNull,
        reason: 'the toggle must disable itself while persisting',
      );
      // Second tap lands on the disabled control while the write is pending.
      await tester.tap(_collectionToggle);
      await tester.pump();
      _repo.gate!.complete();
      _repo.gate = null;
      await _settle(tester);

      expect(
        _repo.addCalls,
        1,
        reason: 'a second tap must not create a second row',
      );
      expect(_repo.rows, hasLength(1));
      expect(_repo.rows.single.name, 'Nature');
      expect(_repo.rows.single.query, 'nature');
      expect(_removeButton, findsOneWidget);
      button = tester.widget<M3EIconButton>(_removeButton);
      expect(button.isSelected, isTrue);
      expect(tester.getSize(_collectionToggle).width, idleSize.width);
      expect(find.text('Added to Collections'), findsOneWidget);
      // Addition keeps the ordinary success presentation.
      final addedScheme = AppTheme.build(brightness: Brightness.light)
          .colorScheme;
      final addedBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(addedBar.backgroundColor, addedScheme.primaryContainer);
      expect(
        tester.widget<Icon>(find.byIcon(PhosphorIconsFill.checkCircle)).color,
        addedScheme.onPrimaryContainer,
      );

      // 3. Remove: the row is really deleted, not just greyed out.
      await tester.tap(_removeButton);
      await _settle(tester);
      expect(_repo.removeCalls, 1);
      expect(_repo.rows, isEmpty);
      expect(_saveButton, findsOneWidget);
      expect(tester.widget<M3EIconButton>(_saveButton).isSelected, isFalse);
      expect(find.text('Removed from Collections'), findsOneWidget);
      // Removal is its own presentation: destructive colour pair + minus glyph,
      // distinct from both the success snack and real error messages.
      final scheme = AppTheme.build(brightness: Brightness.light).colorScheme;
      final removalBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(removalBar.backgroundColor, scheme.error);
      final removalIcon = tester.widget<Icon>(
        find.byIcon(PhosphorIconsFill.minusCircle),
      );
      expect(removalIcon.color, scheme.onError);
      expect(find.byIcon(PhosphorIconsFill.checkCircle), findsNothing);
      expect(find.byIcon(PhosphorIconsFill.warningCircle), findsNothing);

      // 4. Save again, and prove the row reached the persistence boundary.
      await tester.tap(_saveButton);
      await _settle(tester);
      expect(_repo.rows, hasLength(1));

      final reloaded = CollectionsController(_repo);
      await reloaded.restore();
      expect(reloaded.entries.value.single.name, 'Nature');
      expect(reloaded.entries.value.single.query, 'nature');
    });
  });

  testWidgets('a colour query toggles the same way and survives remount', (
    tester,
  ) async {
    await _registerDependencies();

    Widget screen() => _host(
      FilteredWallpapersScreen(
        title: '#aabbcc',
        query: '',
        colorHexes: const ['#aabbcc'],
        onOpenWallpaper: (_) {},
        onBack: () {},
      ),
    );

    await mockNetworkImagesFor(() async {
      await tester.pumpWidget(screen());
      await _settle(tester);
      await tester.tap(_saveButton);
      await _settle(tester);
      expect(_repo.rows.single.name, '#AABBCC');
      expect(_repo.rows.single.colors, ['#aabbcc']);

      // A freshly mounted screen reads the saved state back from storage.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(screen());
      await _settle(tester);
      expect(_removeButton, findsOneWidget);
      expect(tester.widget<M3EIconButton>(_removeButton).isSelected, isTrue);

      await tester.tap(_removeButton);
      await _settle(tester);
      expect(_repo.rows, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(screen());
      await _settle(tester);
      expect(_saveButton, findsOneWidget);
    });
  });
}
