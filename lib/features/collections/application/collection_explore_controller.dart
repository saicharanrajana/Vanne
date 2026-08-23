import '../../../core/collections/collection_entry.dart';
import '../../../core/wallpaper/feed_controller.dart';

/// Owns one collection’s exploration feed. Created per navigation.
final class CollectionExploreController extends FeedController {
  final CollectionEntry entry;

  CollectionExploreController(this.entry, super.repository) {
    reload();
  }

  @override
  SearchRequestSpec buildSpec() => SearchRequestSpec(
        query: entry.query,
        categories: entry.kinds,
        filter: entry.filter,
      );
}
