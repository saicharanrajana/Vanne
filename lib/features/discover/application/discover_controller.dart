import 'package:signals/signals.dart';

import '../../../core/domain/feed_filter.dart';
import '../../../core/wallpaper/feed_controller.dart';

/// Owns the Discover feed: newest-first by default with a user-tunable
/// filter (sorting, time window, minimum resolution) applied through a
/// bottom sheet.
final class DiscoverController extends FeedController {
  DiscoverController(super.repository) {
    // Kick off page 1; the screen shows the skeleton until it lands.
    reload();
  }

  /// Current feed filter, surfaced on the filter-sheet trigger chip.
  final filter = signal(FeedFilter.discoverDefault);

  @override
  SearchRequestSpec buildSpec() => SearchRequestSpec(filter: filter.value);

  /// Applies [newFilter] and restarts pagination. No-op when unchanged so
  /// dismissing the sheet never refetches.
  Future<void> applyFilter(FeedFilter newFilter) async {
    if (newFilter == filter.value) return;
    filter.set(newFilter);
    await reload();
  }
}
