/// Raw JSON DTOs mirroring Wallhaven's wire format.
///
/// One file per aggregate. These types exist only to absorb JSON shape
/// (snake_case keys, string numbers, nullability quirks); they are internal
/// to the package — the public surface exposes the domain models.
library;

export 'collection_dto.dart';
export 'search_meta_dto.dart';
export 'settings_dto.dart';
export 'tag_dto.dart';
export 'thumbs_dto.dart';
export 'uploader_dto.dart';
export 'wallpaper_dto.dart';
