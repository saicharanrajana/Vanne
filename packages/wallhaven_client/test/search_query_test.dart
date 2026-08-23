import 'package:test/test.dart';

import 'helpers.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

void main() {
  group('WallhavenQuery.build', () {
    test('plain tag', () {
      expect(WallhavenQuery().term('anime').build(), 'anime');
    });

    test('multiple plain tags join with spaces', () {
      expect(
        WallhavenQuery().term('anime').term('cyberpunk').build(),
        'anime cyberpunk',
      );
    });

    test('required tags use + prefix', () {
      expect(
        WallhavenQuery().require('anime').require('cyberpunk').build(),
        '+anime +cyberpunk',
      );
    });

    test('mixed include/exclude', () {
      expect(WallhavenQuery().term('anime').exclude('nsfw').build(),
          'anime -nsfw');
    });

    test('user uploads use @ prefix', () {
      expect(WallhavenQuery().fromUser('username').build(), '@username');
    });

    test('exact tag uses id: prefix', () {
      expect(WallhavenQuery().exactTag(123).build(), 'id:123');
    });

    test('file type uses type: prefix', () {
      expect(WallhavenQuery().withFileType(WallhavenFileType.png).build(),
          'type:png');
    });

    test('similar-to uses like: prefix', () {
      expect(WallhavenQuery().similarTo('abc123').build(), 'like:abc123');
    });

    test('combined operators preserve order and prefixes', () {
      final query = WallhavenQuery()
          .require('anime')
          .exclude('nsfw')
          .fromUser('alice')
          .exactTag(123)
          .withFileType(WallhavenFileType.png)
          .similarTo('abc123');
      expect(query.build(),
          '+anime -nsfw @alice id:123 type:png like:abc123');
    });
  });

  group('WallhavenQuery.parse round-trip', () {
    test('parses every documented operator', () {
      const raw = '+anime -nsfw @alice id:123 type:png like:abc123';
      expect(WallhavenQuery.parse(raw).build(), raw);
    });

    test('keeps unknown prefixes as plain terms', () {
      expect(WallhavenQuery.parse('?weird').build(), '?weird');
    });

    test('empty string yields empty query', () {
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
