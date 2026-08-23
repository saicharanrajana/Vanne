import 'package:flutter_test/flutter_test.dart';
import 'package:wallhaven_client/wallhaven_client.dart';
import 'package:wallpaper_app/features/wallpaper_detail/application/wallpaper_metadata.dart';

/// Unit tests for the detail sheet's pure metadata formatters.
void main() {
  Wallpaper wallpaper({
    int width = 0,
    int height = 0,
    String ratio = '',
    int fileSizeBytes = 0,
    DateTime? createdAt,
  }) =>
      Wallpaper(
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
      expect(WallpaperMetadata.fileSize(0), isNull);
      expect(WallpaperMetadata.fileSize(-5), isNull);
    });

    test('formats kilobytes', () {
      expect(WallpaperMetadata.fileSize(512 * 1024), '512 KB');
      expect(WallpaperMetadata.fileSize(1), '0 KB');
    });

    test('formats megabytes with one decimal', () {
      expect(
        WallpaperMetadata.fileSize((2.1 * 1024 * 1024).round()),
        '2.1 MB',
      );
      expect(WallpaperMetadata.fileSize(3 * 1024 * 1024), '3.0 MB');
    });
  });

  group('WallpaperMetadata.aspectRatio', () {
    test('reduces pixel dimensions to a fraction', () {
      expect(
        WallpaperMetadata.aspectRatio(
          wallpaper(width: 1920, height: 1080),
        ),
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
      expect(
        WallpaperMetadata.aspectRatio(wallpaper(ratio: '1.91')),
        '1.91',
      );
    });

    test('falls back to an em dash when nothing usable exists', () {
      expect(WallpaperMetadata.aspectRatio(wallpaper()), '—');
    });
  });

  group('WallpaperMetadata.uploadedDate', () {
    test('formats as "Mon D, YYYY"', () {
      expect(
        WallpaperMetadata.uploadedDate(DateTime(2023, 6, 12)),
        'Jun 12, 2023',
      );
      expect(
        WallpaperMetadata.uploadedDate(DateTime(2024, 1, 5)),
        'Jan 5, 2024',
      );
      expect(
        WallpaperMetadata.uploadedDate(DateTime(2025, 12, 31)),
        'Dec 31, 2025',
      );
    });

    test('returns null for missing timestamps', () {
      expect(WallpaperMetadata.uploadedDate(null), isNull);
    });
  });
}
