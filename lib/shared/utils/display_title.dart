/// Formats a user-facing title in title case while preserving hex colors.
String formatDisplayTitle(String value) {
  if (value.startsWith('#')) return value.toUpperCase();
  return value
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
      .join(' ');
}
