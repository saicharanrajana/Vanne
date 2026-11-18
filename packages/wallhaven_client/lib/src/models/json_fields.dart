/// Shared JSON field-parsing helpers for DTOs.
///
/// Wallhaven's API is loose about scalar types: numbers sometimes arrive as
/// strings, booleans as 0/1, timestamps without a timezone. These helpers
/// absorb those quirks in one place so each `fromJson` stays readable.
library;

import 'package:meta/meta.dart';

/// Parses an int that Wallhaven may deliver as int or numeric string.
@internal
int? parseIntField(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// Parses a bool delivered as bool, 0/1 number, or '0'/'1' string.
@internal
bool? parseBoolField(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    if (value == '1') return true;
    if (value == '0') return false;
  }
  return null;
}

/// Parses Wallhaven timestamps like `"2018-10-31 01:23:10"`.
///
/// The API omits timezone information; we interpret values as UTC for
/// stable ordering. Returns `null` for missing/unparseable input.
@internal
DateTime? parseTimestamp(Object? value) {
  if (value is! String || value.isEmpty) return null;
  // Convert "2018-10-31 01:23:10" into the ISO-8601 form DateTime.parse
  // accepts, then pin it to UTC.
  final normalized = '${value.replaceFirst(' ', 'T')}Z';
  return DateTime.tryParse(normalized)?.toUtc();
}

/// Parses a string, returning `null` for any other JSON type.
///
/// A stray number or object where a string is documented must degrade to the
/// field's default. An untyped cast would throw `TypeError` out of `fromJson`,
/// which escapes the client's typed-error contract and strands callers that
/// only handle `WallhavenException`.
@internal
String? parseStringField(Object? value) => value is String ? value : null;

/// Parses a list of strings, skipping entries that are not strings.
@internal
List<String> parseStringListField(Object? value) => value is List<dynamic>
    ? <String>[
        for (final item in value)
          if (item is String) item,
      ]
    : const <String>[];

/// Parses an object field, returning `null` when absent or not an object.
@internal
Map<String, dynamic>? parseObjectField(Object? value) =>
    value is Map<String, dynamic> ? value : null;

/// Parses a list of JSON objects, skipping entries that are not objects.
@internal
List<Map<String, dynamic>> parseObjectListField(Object? value) =>
    value is List<dynamic>
    ? <Map<String, dynamic>>[
        for (final item in value)
          if (item is Map<String, dynamic>) item,
      ]
    : const <Map<String, dynamic>>[];
