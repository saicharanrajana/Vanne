import 'package:test/test.dart';
import 'package:wallhaven_client/wallhaven_client.dart';

void main() {
  group('WallhavenSearchRequest.toQueryParameters', () {
    test('defaults explicitly encode SFW purity', () {
      expect(WallhavenSearchRequest().toQueryParameters(), {'purity': '100'});

      // All categories use the API default and are omitted; purity is always
      // explicit so SFW-only and all-purities requests never share a cache
      // key (an omitted purity would be ambiguous).
      final all = WallhavenSearchRequest(
        categories: WallhavenCategory.values.toSet(),
        purity: WallhavenPurity.values.toSet(),
      ).toQueryParameters();
      expect(all.containsKey('categories'), isFalse);
      expect(all['purity'], '111');
    });

    test('a fully populated request emits every documented parameter', () {
      final params = WallhavenSearchRequest(
        structuredQuery: WallhavenQuery().term('anime').exclude('nsfw'),
        categories: {WallhavenCategory.general},
        // 101 = sfw (4) + nsfw (1): exercises every purity bit, not just the
        // all/none endpoints.
        purity: {WallhavenPurity.sfw, WallhavenPurity.nsfw},
        sorting: WallhavenSorting.toplist,
        order: WallhavenOrder.asc,
        topRange: WallhavenTopRange.months6,
        minResolution: '1920x1080',
        resolutions: ['1920x1080', '2560x1440'],
        ratios: ['16x9', '16x10'],
        colors: {WallhavenColor.blue0066cc, WallhavenColor.whiteFfffff},
        page: 3,
        seed: 'abc123',
      ).toQueryParameters();

      expect(params['q'], 'anime -nsfw');
      expect(params['categories'], '100');
      expect(params['purity'], '101');
      expect(params['sorting'], 'toplist');
      expect(params['order'], 'asc');
      expect(params['topRange'], '6M');
      expect(params['atleast'], '1920x1080');
      expect(params['resolutions'], '1920x1080,2560x1440');
      expect(params['ratios'], '16x9,16x10');
      // Set ordering is unspecified; compare sorted content.
      final colors = params['colors']!.split(',')..sort();
      expect(colors, ['0066cc', 'ffffff']);
      expect(params['page'], '3');
      expect(params['seed'], 'abc123');

      // Page 1 is the API default and stays off the wire.
      expect(
        WallhavenSearchRequest(page: 1).toQueryParameters().containsKey('page'),
        isFalse,
      );
    });
  });

  group('WallhavenSearchRequest validation', () {
    test('rejects malformed combinations and values', () {
      expect(
        () => WallhavenSearchRequest(
          query: 'raw',
          structuredQuery: WallhavenQuery().term('x'),
        ),
        throwsArgumentError,
        reason: 'raw and structured queries are mutually exclusive',
      );
      for (final bad in ['abc12', 'abc1234', 'abc-23!', '']) {
        expect(
          () => WallhavenSearchRequest(seed: bad),
          throwsArgumentError,
          reason: 'seed "$bad" must be rejected',
        );
      }
      // 6 alphanumeric characters pass.
      WallhavenSearchRequest(seed: 'aBc123');

      expect(
        () => WallhavenSearchRequest(minResolution: '1920'),
        throwsArgumentError,
      );
      expect(
        () => WallhavenSearchRequest(resolutions: ['1080p']),
        throwsArgumentError,
      );
      expect(
        () => WallhavenSearchRequest(ratios: ['16-9']),
        throwsArgumentError,
      );
      expect(() => WallhavenSearchRequest(page: 0), throwsArgumentError);
    });
  });
}
