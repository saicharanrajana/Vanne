import 'package:test/test.dart';

import 'helpers.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

void main() {
  group('WallhavenQuery.build', () {
    test('emits every operator with its documented prefix and order', () {
      // Plain terms and multiple plain terms first: they are the common path
      // and must not be lost among the prefix operators.
      expect(WallhavenQuery().term('anime').build(), 'anime');
      expect(
        WallhavenQuery().term('anime').term('cyberpunk').build(),
        'anime cyberpunk',
      );

      final query = WallhavenQuery()
          .term('landscape')
          .require('anime')
          .require('cyberpunk')
          .exclude('nsfw')
          .fromUser('alice')
          .exactTag(123)
          .withFileType(WallhavenFileType.png)
          .similarTo('abc123');
      expect(
        query.build(),
        'landscape +anime +cyberpunk -nsfw @alice id:123 type:png '
        'like:abc123',
      );
    });
  });

  group('WallhavenQuery.parse round-trip', () {
    test('round-trips operators and keeps unknown or empty input', () {
      const raw = '+anime -nsfw @alice id:123 type:png like:abc123';
      expect(WallhavenQuery.parse(raw).build(), raw);
      expect(WallhavenQuery.parse('?weird').build(), '?weird');
      expect(WallhavenQuery.parse('').isEmpty, isTrue);
    });
  });

  group('single encoding through transport', () {
    test('dio encodes operators exactly once in the request URL', () async {
      final adapter = FakeWallhavenAdapter.json(fixture('search_response.json'));
      final client = buildTestClient(adapter: adapter);
      addTearDown(client.close);

      await client.search(
        WallhavenSearchRequest(
          structuredQuery: WallhavenQuery().require('anime').exclude('nsfw'),
        ),
      );

      final url = adapter.lastRequest.uri;
      // `+` must appear percent-encoded exactly once — never `%252B`.
      expect(url.query, contains('%2Banime'));
      expect(url.query, contains('-nsfw'));
      expect(url.query, isNot(contains('%25')));
      // Decoding recovers the literal syntax ('+' as space, %2B as plus).
      expect(Uri.decodeQueryComponent(url.query), contains('+anime -nsfw'));
    });
  });
}
