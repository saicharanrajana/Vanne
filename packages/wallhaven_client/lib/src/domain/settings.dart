import 'purity.dart';

/// Authenticated user settings from `/settings`.
///
/// The application must work fully without ever calling this endpoint.
final class UserSettings {
  final String? thumbSize;
  final int? perPage;
  final List<Purity> purities;
  final List<Category> categories;
  final List<String> resolutions;
  final List<String> aspectRatios;
  final String? toplistRange;
  final List<String> tagBlacklist;
  final List<String> userBlacklist;

  const UserSettings({
    this.thumbSize,
    this.perPage,
    this.purities = const [],
    this.categories = const [],
    this.resolutions = const [],
    this.aspectRatios = const [],
    this.toplistRange,
    this.tagBlacklist = const [],
    this.userBlacklist = const [],
  });
}
