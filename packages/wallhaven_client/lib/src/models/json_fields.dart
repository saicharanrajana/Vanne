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
  if (value is num) return value.toInt();
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
