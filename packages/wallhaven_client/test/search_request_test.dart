import 'package:test/test.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

void main() {
  group('WallhavenSearchRequest.toQueryParameters', () {
    test('defaults emit only q-less minimal parameters', () {
      // Defaults mirror the API's own defaults, so nothing is emitted.
      expect(WallhavenSearchRequest().toQueryParameters(), isEmpty);
    });

    test('query parameter name is q', () {
      expect(
        WallhavenSearchRequest(query: 'anime').toQueryParameters(),
        {'q': 'anime'},
      );
    });

    test('structuredQuery is used over raw query when only it is set', () {
      expect(
        WallhavenSearchRequest(
          structuredQuery: WallhavenQuery().term('anime').exclude('nsfw'),
        ).toQueryParameters(),
        {'q': 'anime -nsfw'},
      );
    });

    test('passing both query and structuredQuery throws', () {
      expect(
        () => WallhavenSearchRequest(
          query: 'raw',
          structuredQuery: WallhavenQuery().term('x'),
        ),
        throwsArgumentError,
      );
    });

    test('categories bitfield encoding and order', () {
      final params = WallhavenSearchRequest(
        categories: {WallhavenCategory.general},
      ).toQueryParameters();
      expect(params['categories'], '100');
    });

    test('all categories are omitted (API default)', () {
      final params = WallhavenSearchRequest(
        categories: WallhavenCategory.values.toSet(),
        purity: WallhavenPurity.values.toSet(),
      ).toQueryParameters();
      expect(params.containsKey('categories'), isFalse);
      expect(params.containsKey('purity'), isFalse);
    });

    test('purity bitfield encoding includes nsfw position', () {
      final params = WallhavenSearchRequest(
        purity: {WallhavenPurity.sfw, WallhavenPurity.nsfw},
      ).toQueryParameters();
      expect(params['purity'], '101');
    });

    test('sorting/order wire names and non-default emission', () {
      final params = WallhavenSearchRequest(
        sorting: WallhavenSorting.toplist,
        order: WallhavenOrder.asc,
      ).toQueryParameters();
      expect(params['sorting'], 'toplist');
      expect(params['order'], 'asc');
    });

    test('topRange emitted with wire value', () {
      expect(
        WallhavenSearchRequest(topRange: WallhavenTopRange.months6)
            .toQueryParameters()['topRange'],
        '6M',
      );
    });

    test('minResolution maps to atleast', () {
      expect(
        WallhavenSearchRequest(minResolution: '1920x1080')
            .toQueryParameters()['atleast'],
        '1920x1080',
      );
    });

    test('resolutions and ratios comma-join', () {
      final params = WallhavenSearchRequest(
        resolutions: ['1920x1080', '2560x1440'],
        ratios: ['16x9', '16x10'],
      ).toQueryParameters();
      expect(params['resolutions'], '1920x1080,2560x1440');
      expect(params['ratios'], '16x9,16x10');
    });

    test('colors join as bare hex without #', () {
      final params = WallhavenSearchRequest(
        colors: {WallhavenColor.blue0066cc, WallhavenColor.whiteFfffff},
      ).toQueryParameters();
      // Set ordering is unspecified; compare sorted content.
      final colors = params['colors']!.split(',')..sort();
      expect(colors, ['0066cc', 'ffffff']);
    });

    test('page 1 omitted, page 3 emitted', () {
      expect(
        WallhavenSearchRequest(page: 1).toQueryParameters()
            .containsKey('page'),
        isFalse,
      );
      expect(
        WallhavenSearchRequest(page: 3).toQueryParameters()['page'],
        '3',
      );
    });

    test('seed emitted verbatim', () {
      expect(
        WallhavenSearchRequest(seed: 'abc123').toQueryParameters()['seed'],
        'abc123',
      );
    });
  });

  group('WallhavenSearchRequest validation', () {
    test('rejects malformed seed', () {
      for (final bad in ['abc12', 'abc1234', 'abc-23!', '']) {
        expect(
          () => WallhavenSearchRequest(seed: bad),
          throwsArgumentError,
          reason: 'seed "$bad" must be rejected',
        );
      }
      // 6 alphanumeric characters pass.
      WallhavenSearchRequest(seed: 'aBc123');
    });

    test('rejects malformed minResolution/resolutions/ratios', () {
      expect(
        () => WallhavenSearchRequest(minResolution: '1920'),
        throwsArgumentError,
      );
      expect(
        () => WallhavenSearchRequest(resolutions: ['1080p']),
        throwsArgumentError,
      );
      expect(() => WallhavenSearchRequest(ratios: ['16-9']),
          throwsArgumentError);
    });

    test('rejects page < 1', () {
      expect(() => WallhavenSearchRequest(page: 0), throwsArgumentError);
    });
  });

  group('copy helpers', () {
    test('withPage changes page and keeps everything else', () {
      final original = WallhavenSearchRequest(
        query: 'anime',
        sorting: WallhavenSorting.random,
        seed: 'abc123',
      );
      final next = original.withPage(2);
      expect(next.page, 2);
      expect(next.seed, 'abc123');
      expect(next.sorting, WallhavenSorting.random);
      expect(next.query, 'anime');
    });

    test('withSeed replaces the seed', () {
      final updated =
          WallhavenSearchRequest(query: 'a').withSeed('xyz789');
      expect(updated.seed, 'xyz789');
      expect(updated.toQueryParameters()['seed'], 'xyz789');
    });

    test('color normalization validates hex input', () {
      expect(WallhavenColor.normalizeHex('#FF0000'), 'ff0000');
      expect(() => WallhavenColor.normalizeHex('#ff'), throwsArgumentError);
    });
  });
}
