import 'package:flutter_test/flutter_test.dart';
import 'package:vanne/shared/utils/display_title.dart';

void main() {
  test('formats words as title case and collapses whitespace', () {
    expect(formatDisplayTitle('  dARK   minimal  '), 'Dark Minimal');
  });

  test('preserves hex colors as uppercase values', () {
    expect(formatDisplayTitle('#ff00aB'), '#FF00AB');
  });
}
