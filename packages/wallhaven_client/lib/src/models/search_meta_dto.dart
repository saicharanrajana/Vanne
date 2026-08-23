/// Pagination/query metadata attached to listing responses (`meta`).
library;

import 'json_fields.dart';

final class SearchMetaDto {
  final int currentPage;
  final int lastPage;
  final int perPage;

  /// Absent from some listings (e.g. collection listings).
  final int? total;

  /// Either a query string or, for exact-tag searches, an object shaped
  /// `{id: <int>, tag: <String>}`. Kept as decoded JSON here; the mapper
  /// turns it into typed domain values.
  final Object? query;

  /// Seed for random sorting. Pass it between page requests so random
  /// pages do not repeat results.
  final String? seed;

  const SearchMetaDto({
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    this.total,
    this.query,
    this.seed,
  });

  factory SearchMetaDto.fromJson(Map<String, dynamic> json) => SearchMetaDto(
        currentPage: parseIntField(json['current_page']) ?? 1,
        lastPage: parseIntField(json['last_page']) ?? 0,
        perPage: parseIntField(json['per_page']) ?? 24,
        total: parseIntField(json['total']),
        query: json['query'],
        seed: json['seed'] as String?,
      );
}
