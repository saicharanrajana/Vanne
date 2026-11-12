/// Deterministic Wallhaven JSON fixtures for app-level tests.
///
/// Tests speak the same wire format the real client parses, so a DTO or
/// transport regression surfaces here too. Ids are stable and descriptive;
/// finders use them (e.g. `wallpaper-tile-alpha`).
library;

/// One wallpaper as returned by `GET /search` (no uploader/tags).
Map<String, dynamic> wallpaperJson(
  String id, {
  String category = 'general',
  int width = 1080,
  int height = 1920,
  String fileType = 'image/jpeg',
  List<String> colors = const ['#123456', '#abcdef'],
}) {
  final ext = switch (fileType) {
    'image/png' => 'png',
    _ => 'jpg',
  };
  return {
    'id': id,
    'url': 'https://wallhaven.cc/w/$id',
    'short_url': 'https://whvn.cc/$id',
    'views': 10,
    'favorites': 2,
    'source': '',
    'purity': 'sfw',
    'category': category,
    'dimension_x': width,
    'dimension_y': height,
    'resolution': '${width}x$height',
    'ratio': (width / height).toStringAsFixed(2),
    'file_size': 1024,
    'file_type': fileType,
    'created_at': '2025-01-02 03:04:05',
    'colors': colors,
    'path': 'https://images.test/$id.$ext',
    'thumbs': {
      'large': 'https://thumbs.test/lg/$id.jpg',
      'original': 'https://thumbs.test/orig/$id.jpg',
      'small': 'https://thumbs.test/small/$id.jpg',
    },
  };
}

/// `GET /search` envelope. [lastPage] defaults to 1 so a default feed is
/// finite and its footer settles — no perpetual loading animation.
Map<String, dynamic> searchPageJson(
  List<String> ids, {
  int currentPage = 1,
  int lastPage = 1,
  String? seed,
}) => {
  'data': [for (final id in ids) wallpaperJson(id)],
  'meta': {
    'current_page': currentPage,
    'last_page': lastPage,
    'per_page': 24,
    'total': ids.length,
    'query': '',
    'seed': ?seed,
  },
};

/// `GET /w/{id}` envelope: listing fields plus uploader and tags.
Map<String, dynamic> wallpaperDetailsJson(
  String id, {
  String category = 'general',
  String uploader = 'fixture-user',
  List<String> tags = const ['landscape', 'minimal'],
}) {
  final wallpaper = wallpaperJson(id, category: category);
  return {
    'data': {
      ...wallpaper,
      'uploader': {
        'username': uploader,
        'group': 'User',
        'avatar': const <String, dynamic>{},
      },
      'tags': [
        for (var i = 0; i < tags.length; i++)
          {
            'id': i + 1,
            'name': tags[i],
            'alias': null,
            'category_id': 2,
            'category': 'General',
            'purity': 'sfw',
            'created_at': '2025-01-01 00:00:00',
          },
      ],
    },
  };
}
