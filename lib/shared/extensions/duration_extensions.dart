/// Human-readable duration formatting shared by cards, sheets and
/// progress surfaces.
extension DurationX on Duration {
  /// Compact remaining-time label, e.g. `42s`, `3m 05s`, `1h 12m`.
  ///
  /// Hours and minutes are space-separated; seconds are zero-padded so
  /// countdowns don't jitter horizontally. Negative durations clamp to
  /// zero. Useful for download ETA and any "time left" readout.
  String get remainingLabel {
    if (isNegative || inMilliseconds == 0) return '0s';
    final total = inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
    return '${s}s';
  }
}
