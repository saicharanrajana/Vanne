/// Readers for values out of a persisted JSON row.
///
/// Local storage is untrusted input: a row can be hand-edited, restored from a
/// backup, or written by a build with a different schema. Every field that is
/// not the row's identity is therefore read defensively — a wrongly typed
/// value falls back to the documented default instead of throwing, so a user
/// does not lose a favorite or a saved collection over one bad field.
library;

/// [value] when it is text, else `null`.
String? readString(Object? value) => value is String ? value : null;

/// [value] as a whole number; also accepts JSON doubles such as `1920.0`.
int readInt(Object? value) =>
    value is num && value.isFinite ? value.toInt() : 0;

/// [value] when it is a JSON object, else an empty one.
Map<String, dynamic> readObject(Object? value) =>
    value is Map<String, dynamic> ? value : const {};

/// [value] when it is a JSON array, else an empty one.
List<dynamic> readList(Object? value) => value is List ? value : const [];
