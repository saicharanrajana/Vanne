import '../enums/wallhaven_enums.dart';

/// One token of Wallhaven's `q` search syntax.
///
/// The operator prefix is stored verbatim in [text] (e.g. `+anime`,
/// `-nsfw`, `@username`, `id:123`); no percent-encoding ever happens here.
sealed class _QueryToken {
  const _QueryToken();

  /// The raw, unencoded token text as it appears in the `q` parameter.
  String get text;
}

final class _Term extends _QueryToken {
  const _Term(this.word);
  final String word;

  @override
  String get text => word;
}

final class _Excluded extends _QueryToken {
  const _Excluded(this.word);
  final String word;

  @override
  String get text => '-$word';
}

final class _Required extends _QueryToken {
  const _Required(this.word);
  final String word;

  @override
  String get text => '+$word';
}

final class _UserUploads extends _QueryToken {
  const _UserUploads(this.username);
  final String username;

  @override
  String get text => '@$username';
}

final class _ExactTag extends _QueryToken {
  const _ExactTag(this.id);
  final int id;

  @override
  String get text => 'id:$id';
}

final class _FileTypeToken extends _QueryToken {
  const _FileTypeToken(this.fileType);
  final WallhavenFileType fileType;

  @override
  String get text => 'type:${fileType.wireName}';
}

final class _SimilarTo extends _QueryToken {
  const _SimilarTo(this.wallpaperId);
  final String wallpaperId;

  @override
  String get text => 'like:$wallpaperId';
}

/// An immutable, structured builder for Wallhaven's special `q` syntax:
///
/// - plain tags:            `anime`
/// - excluded tags:         `-nsfw`
/// - required tags:         `+anime +cyberpunk`
/// - user uploads:          `@username`
/// - exact tag lookup:      `id:123`
/// - file type filter:      `type:png`
/// - similar wallpapers:    `like:wallpaperId`
///
/// All builder methods return a new instance; tokens are immutable.
///
/// Encoding contract: [build] returns the literal query string with
/// operators intact. Percent-encoding happens exactly once later, when the
/// string is placed into a URL query parameter by dio/`Uri`. Never encode
/// before calling dio — that would double-encode (`%2B` → `%252B`).
final class WallhavenQuery {
  const WallhavenQuery() : _tokens = const [];

  const WallhavenQuery._(this._tokens);

  final List<_QueryToken> _tokens;

  /// Whether any token has been added.
  bool get isEmpty => _tokens.isEmpty;

  /// Parses an existing raw query string back into structured tokens,
  /// enabling round-tripping (e.g. re-hydrating a saved search).
  ///
  /// Unrecognized prefixes are kept as plain terms so parsing never loses
  /// information.
  factory WallhavenQuery.parse(String raw) {
    final tokens = <_QueryToken>[];
    for (final part in raw.trim().split(RegExp(r'\s+'))) {
      if (part.isEmpty) continue;
      if (part.startsWith('+') && part.length > 1) {
        tokens.add(_Required(part.substring(1)));
      } else if (part.startsWith('-') && part.length > 1) {
        tokens.add(_Excluded(part.substring(1)));
      } else if (part.startsWith('@') && part.length > 1) {
        tokens.add(_UserUploads(part.substring(1)));
      } else if (part.startsWith('id:')) {
        final id = int.tryParse(part.substring(3));
        if (id != null) {
          tokens.add(_ExactTag(id));
          continue;
        }
        tokens.add(_Term(part));
      } else if (part.startsWith('type:')) {
        final value = part.substring(5);
        final fileType = WallhavenFileType.values
            .where((t) => t.wireName == value)
            .firstOrNull;
        if (fileType != null) {
          tokens.add(_FileTypeToken(fileType));
          continue;
        }
        tokens.add(_Term(part));
      } else if (part.startsWith('like:')) {
        tokens.add(_SimilarTo(part.substring(5)));
      } else {
        tokens.add(_Term(part));
      }
    }
    return WallhavenQuery._(List.unmodifiable(tokens));
  }

  /// Adds a plain (fuzzy) tag/keyword term.
  WallhavenQuery term(String tag) =>
      WallhavenQuery._([..._tokens, _Term(tag)]);

  /// Excludes a tag: `-tag`.
  WallhavenQuery exclude(String tag) =>
      WallhavenQuery._([..._tokens, _Excluded(tag)]);

  /// Requires a tag: `+tag`.
  WallhavenQuery require(String tag) =>
      WallhavenQuery._([..._tokens, _Required(tag)]);

  /// Restricts results to a user's uploads: `@username`.
  WallhavenQuery fromUser(String username) =>
      WallhavenQuery._([..._tokens, _UserUploads(username)]);

  /// Exact tag-id search: `id:123`. Cannot be combined with other terms
  /// server-side; the API resolves it alone.
  WallhavenQuery exactTag(int id) =>
      WallhavenQuery._([..._tokens, _ExactTag(id)]);

  /// Filters by file type: `type:png`.
  WallhavenQuery withFileType(WallhavenFileType fileType) =>
      WallhavenQuery._([..._tokens, _FileTypeToken(fileType)]);

  /// Finds wallpapers with similar tags: `like:wallpaperId`.
  WallhavenQuery similarTo(String wallpaperId) =>
      WallhavenQuery._([..._tokens, _SimilarTo(wallpaperId)]);

  /// Builds the literal `q` string. Operators and spaces are preserved
  /// verbatim; encoding is the transport layer's job (exactly once).
  String build() => _tokens.map((t) => t.text).join(' ');

  @override
  String toString() => 'WallhavenQuery(${build()})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is WallhavenQuery && other.build() == build();

  @override
  int get hashCode => build().hashCode;
}
