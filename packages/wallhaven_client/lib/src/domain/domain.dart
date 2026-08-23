/// Public domain models — what applications consume.
///
/// This barrel is the only file apps should import from `domain/`; it also
/// re-exports the public wire enums so call sites never reach into
/// internals. No JSON types leak past [mappers].
library;

export 'collection.dart';
export 'mappers.dart';
export 'pagination.dart';
export 'purity.dart';
export 'settings.dart';
export 'tag.dart';
export 'wallpaper.dart';

export '../enums/wallhaven_enums.dart'
    show
        WallhavenCategory,
        WallhavenPurity,
        WallhavenSorting,
        WallhavenOrder,
        WallhavenTopRange,
        WallhavenFileType,
        WallhavenColor,
        encodeCategories,
        encodePurities;
