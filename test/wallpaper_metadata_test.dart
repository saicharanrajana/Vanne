import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:vanne/features/wallpaper_detail/application/wallpaper_metadata.dart';

/// Unit tests for the detail sheet's pure metadata formatters.
void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  Wallpaper wallpaper({
    int width = 0,
    int height = 0,
    String ratio = '',
    int fileSizeBytes = 0,
    DateTime? createdAt,
  }) => Wallpaper(
    id: 'test',
    url: 'https://wallhaven.cc/w/test',
    source: '',
    purity: Purity.sfw,
    category: Category.general,
    width: width,
    height: height,
    resolution: '',
    ratio: ratio,
    fileSizeBytes: fileSizeBytes,
    fileType: '',
    colors: const [],
    views: 0,
    favorites: 0,
    path: '',
    thumbnails: const Thumbnails(),
    createdAt: createdAt,
  );

  group('WallpaperMetadata.fileSize', () {
    test('returns null for missing size', () {
      expect(WallpaperMetadata.fileSize(0, 'en_US'), isNull);
      expect(WallpaperMetadata.fileSize(-5, 'en_US'), isNull);
    });

    test('formats kilobytes', () {
      expect(WallpaperMetadata.fileSize(512 * 1024, 'en_US'), '512 KB');
      expect(WallpaperMetadata.fileSize(1, 'en_US'), '0 KB');
    });

    test('formats megabytes with one decimal', () {
      expect(
        WallpaperMetadata.fileSize((2.1 * 1024 * 1024).round(), 'en_US'),
        '2.1 MB',
      );
      expect(WallpaperMetadata.fileSize(3 * 1024 * 1024, 'en_US'), '3.0 MB');
    });

    test('formats decimal separators per locale', () {
      expect(
        WallpaperMetadata.fileSize((2.1 * 1024 * 1024).round(), 'de_DE'),
        '2,1 MB',
      );
    });
  });

  group('WallpaperMetadata.aspectRatio', () {
    test('reduces pixel dimensions to a fraction', () {
      expect(
        WallpaperMetadata.aspectRatio(wallpaper(width: 1920, height: 1080)),
        '16:9',
      );
      expect(
        WallpaperMetadata.aspectRatio(wallpaper(width: 1080, height: 2400)),
        '9:20',
      );
      expect(
        WallpaperMetadata.aspectRatio(wallpaper(width: 1200, height: 1697)),
        '1200:1697', // coprime — stays as-is
      );
    });

    test('falls back to the wire ratio string when dimensions are missing', () {
      expect(WallpaperMetadata.aspectRatio(wallpaper(ratio: '1.91')), '1.91');
    });

    test('falls back to a dash when nothing usable exists', () {
      expect(WallpaperMetadata.aspectRatio(wallpaper()), '-');
    });
  });

  group('WallpaperMetadata.uploadedDate', () {
    test('formats as "Mon D, YYYY" in en', () {
      expect(
        WallpaperMetadata.uploadedDate(DateTime(2023, 6, 12), 'en_US'),
        'Jun 12, 2023',
      );
      expect(
        WallpaperMetadata.uploadedDate(DateTime(2024, 1, 5), 'en_US'),
        'Jan 5, 2024',
      );
      expect(
        WallpaperMetadata.uploadedDate(DateTime(2025, 12, 31), 'en_US'),
        'Dec 31, 2025',
      );
    });

    test('localizes month names and ordering in de', () {
      expect(
        WallpaperMetadata.uploadedDate(DateTime(2023, 6, 12), 'de_DE'),
        '12. Juni 2023',
      );
    });

    test('returns null for missing timestamps', () {
      expect(WallpaperMetadata.uploadedDate(null, 'en_US'), isNull);
    });
  });

  group('WallpaperMetadata.count', () {
    test('groups digits per locale', () {
      expect(WallpaperMetadata.count(1234567, 'en_US'), '1,234,567');
      expect(WallpaperMetadata.count(1234567, 'de_DE'), '1.234.567');
    });
  });
}
