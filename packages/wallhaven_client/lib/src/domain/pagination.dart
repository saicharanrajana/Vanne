/// Pagination metadata models for listing endpoints.
library;

/// One page of paginated results with explicit pagination metadata.
///
/// Pagination is always explicit in this client: callers request pages via
/// [currentPage]/[hasNextPage]; nothing ever crawls ahead automatically.
class PaginatedResult<T> {
  final List<T> items;
  final int currentPage;
  final int lastPage;
  final int perPage;
  final int? total;

  /// Full metadata, including any random-search seed.
  final SearchMeta meta;

  const PaginatedResult({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    this.total,
    required this.meta,
  });

  /// Whether another page can be requested. An empty result set is always
  /// terminal regardless of metadata.
  bool get hasNextPage => currentPage < lastPage && items.isNotEmpty;

  @override
  String toString() =>
      'PaginatedResult<T>(page $currentPage/$lastPage, ${items.length} items)';
}

/// Query metadata echoed by listing endpoints.
final class SearchMeta {
  final int currentPage;
  final int lastPage;
  final int perPage;

  /// Absent from collection listings.
  final int? total;

  /// Free-text query echo, when applicable.
  final String? query;

  /// Structured echo of an exact-tag search (`id:123`).
  final ExactTagQuery? exactTagQuery;

  /// Seed to pass between pages of a random-sorted search so results do
  /// not repeat across pages. Null unless sorting was random.
  final String? seed;

  const SearchMeta({
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    this.total,
    this.query,
    this.exactTagQuery,
    this.seed,
  });
}

/// Structured echo of an exact-tag search: `{id: 123}` resolves to a tag.
final class ExactTagQuery {
  final int id;
  final String tag;

  const ExactTagQuery({required this.id, required this.tag});
}
