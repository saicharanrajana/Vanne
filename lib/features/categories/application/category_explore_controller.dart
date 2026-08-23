import '../../../core/domain/app_category.dart';
import '../../../core/wallpaper/feed_controller.dart';

/// Owns one category's exploration feed. Created per navigation into
/// `/categories/:id` — cheap, self-contained after construction.
final class CategoryExploreController extends FeedController {
  final AppCategory category;

  CategoryExploreController(this.category, super.repository) {
    // Immediately load page 1 — otherwise the grid would stay in its
    // intentional empty state ("Nothing here yet") forever.
    reload();
  }

  @override
  SearchRequestSpec buildSpec() => SearchRequestSpec(
    query: category.searchTerm,
    categories: category.kinds.map((kind) => kind.wire).toList(),
  );
}
