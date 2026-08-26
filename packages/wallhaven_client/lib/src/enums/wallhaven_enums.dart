/// Wire-format enums for Wallhaven search parameters.
///
/// Each enum carries the exact string Wallhaven's API expects so that
/// call sites never hard-code wire values.
library;


/// Wallpaper categories. Encoded as a fixed-order bitfield string
/// ordered [general, anime, people] (see [encodeCategories]).
enum WallhavenCategory {
  general(0),
  anime(1),
  people(2);

  const WallhavenCategory(this.bitIndex);

  /// Position of this member within the bitfield string.
  final int bitIndex;
}

/// Content purities. Encoded as a fixed-order bitfield string
/// ordered [sfw, sketchy, nsfw] (see [encodePurities]).
///
/// Note: `nsfw` requires an authenticated request server-side.
enum WallhavenPurity {
  sfw(0),
  sketchy(1),
  nsfw(2);

  const WallhavenPurity(this.bitIndex);

  /// Position of this member within the bitfield string.
  final int bitIndex;
}

/// Encodes a category set as Wallhaven's fixed-order bitfield string
/// (`general|anime|people` → e.g. `100`, `111`).
String encodeCategories(Set<WallhavenCategory> categories) =>
    _encodeBitfield(WallhavenCategory.values, categories);

/// Encodes a purity set as Wallhaven's fixed-order bitfield string
/// (`sfw|sketchy|nsfw` → e.g. `100`, `110`, `111`).
String encodePurities(Set<WallhavenPurity> purities) =>
    _encodeBitfield(WallhavenPurity.values, purities);

// The bitfield is positional, not numeric: each character is '1' when the
// corresponding category/purity is enabled, in the documented order.
String _encodeBitfield<T extends Enum>(List<T> all, Set<T> selected) =>
    List<String>.generate(
      all.length,
      (i) => selected.contains(all[i]) ? '1' : '0',
    ).join();

/// Result sorting methods supported by `/search`.
enum WallhavenSorting {
  dateAdded('date_added'),
  relevance('relevance'),
  random('random'),
  views('views'),
  favorites('favorites'),
  toplist('toplist'),
  hot('hot');

  const WallhavenSorting(this.wireName);

  /// Value sent over the wire.
  final String wireName;
}

/// Sort direction.
enum WallhavenOrder {
  asc('asc'),
  desc('desc');

  const WallhavenOrder(this.wireName);

  /// Value sent over the wire.
  final String wireName;
}

/// Time windows for `sorting: toplist` (`topRange` parameter).
enum WallhavenTopRange {
  day1('1d'),
  days3('3d'),
  week1('1w'),
  month1('1M'),
  months3('3M'),
  months6('6M'),
  year1('1y');

  const WallhavenTopRange(this.wireName);

  /// Value sent over the wire.
  final String wireName;
}

/// Image file types filterable via `type:` in queries.
enum WallhavenFileType {
  png('png'),
  jpg('jpg');

  const WallhavenFileType(this.wireName);

  /// Value sent over the wire. Wallhaven treats `jpg` as covering jpeg.
  final String wireName;
}

/// The 29 documented search colors (6-digit hex, no leading `#`).
enum WallhavenColor {
  maroon660000('660000'),
  darkRed990000('990000'),
  redCc0000('cc0000'),
  paleRedCc3333('cc3333'),
  pinkEa4c88('ea4c88'),
  purple993399('993399'),
  deepPurple663399('663399'),
  navy333399('333399'),
  blue0066cc('0066cc'),
  skyBlue0099cc('0099cc'),
  teal66cccc('66cccc'),
  green77cc33('77cc33'),
  oliveGreen669900('669900'),
  forestGreen336600('336600'),
  darkOlive666600('666600'),
  yellowGreen999900('999900'),
  khakiCccc33('cccc33'),
  yellowFfff00('ffff00'),
  amberFfcc33('ffcc33'),
  orangeFf9900('ff9900'),
  tangerineFf6600('ff6600'),
  burntOrangeCc6633('cc6633'),
  brown996633('996633'),
  darkBrown663300('663300'),
  black000000('000000'),
  gray999999('999999'),
  silverCccccc('cccccc'),
  whiteFfffff('ffffff'),
  slate424153('424153');

  const WallhavenColor(this.hex);

  /// 6-digit hex without `#`.
  final String hex;
}
