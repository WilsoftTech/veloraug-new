import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../l10n/app_localizations.dart';
import 'safe_urls.dart';

enum EditionKind { movie, series }

EditionKind? _kind(Object? value) => switch (value) {
  'movie' => EditionKind.movie,
  'series' => EditionKind.series,
  _ => null,
};

/// One VJ's edition of a movie or series, as a poster card shows it.
class EditionCard {
  const EditionCard({
    required this.id,
    required this.kind,
    required this.title,
    required this.language,
    required this.label,
    this.year,
    this.posterUrl,
    this.vjName,
    this.vjSlug,
    this.rating,
  });

  final String id;
  final EditionKind kind;
  final String title;
  final int? year;
  final String? posterUrl;

  /// Shown in the poster's top-left corner. Null for a test film.
  final String? vjName;
  final String? vjSlug;

  /// A language code, such as `lg`.
  final String language;

  /// "Luganda · VJ Junior", from the API, for the edition's page.
  final String label;

  /// TMDB's score for the source title, out of 10. Null when there is none,
  /// or too few votes for it to mean much: then nothing is shown.
  final double? rating;
}

/// A title in Home's hero. Every one has something to watch.
class FeaturedTitle {
  const FeaturedTitle({
    required this.card,
    this.genres = const [],
    this.backdropUrl,
    this.itemId,
  });

  final EditionCard card;
  final List<String> genres;

  /// Wide artwork for the hero. Null without one: the poster stands in.
  final String? backdropUrl;

  /// A movie's one video, to play. Null for a series.
  final String? itemId;

  String get id => card.id;
  String get title => card.title;
  EditionKind get kind => card.kind;
}

/// A rail of titles to discover on an edition's page.
class EditionRail {
  const EditionRail({required this.key, required this.editions});

  /// `vj`, `recommended`, `popular`, `top_rated`, `recent` or
  /// `new_episodes` from the API, or `because` for Because you watched.
  final String key;
  final List<EditionCard> editions;
}

/// One page of editions. [nextOffset] is null on the last page.
class EditionPage {
  const EditionPage({required this.editions, this.nextOffset});

  final List<EditionCard> editions;
  final int? nextOffset;
}

/// One episode of a series edition.
class Episode {
  const Episode({
    required this.itemId,
    required this.season,
    required this.episode,
    this.title,
    this.playable = false,
  });

  final String itemId;
  final int season;
  final int episode;
  final String? title;
  final bool playable;
}

class Season {
  const Season({required this.season, required this.episodes});

  final int season;
  final List<Episode> episodes;
}

/// Everything an edition's page shows.
class EditionDetail {
  const EditionDetail({
    required this.card,
    required this.sourceTitle,
    this.overview,
    this.runtimeMinutes,
    this.genres = const [],
    this.backdropUrl,
    this.trailerUrl,
    this.vjPhotoUrl,
    this.voteCount,
    this.itemId,
    this.playable = false,
    this.seasons = const [],
  });

  final EditionCard card;

  /// TMDB's title, or the typed-in one. The card's title is the VJ's.
  final String sourceTitle;
  final String? overview;
  final int? runtimeMinutes;
  final List<String> genres;
  final String? backdropUrl;

  /// An official trailer on YouTube, opened outside the app.
  final Uri? trailerUrl;
  final String? vjPhotoUrl;

  /// How many TMDB votes [rating] is from. Null whenever it is.
  final int? voteCount;

  /// A movie's one video. Null for a series.
  final String? itemId;

  /// True when there is something to watch.
  final bool playable;
  final List<Season> seasons;

  String get id => card.id;
  String get title => card.title;
  EditionKind get kind => card.kind;
  double? get rating => card.rating;

  /// The series' episodes in watching order: by season, then number.
  List<Episode> get episodes => [
    for (final season in seasons) ...season.episodes,
  ];
}

/// The episode to offer after [itemId]: the next one in its season, then
/// the first of the next season, in the same edition, so the same VJ.
/// Episodes without a video are skipped. Null after the last one.
Episode? nextEpisode(List<Episode> episodes, String itemId) {
  final at = episodes.indexWhere((episode) => episode.itemId == itemId);
  if (at < 0) return null;
  for (final episode in episodes.skip(at + 1)) {
    if (episode.playable) return episode;
  }
  return null;
}

class VjCard {
  const VjCard({
    required this.id,
    required this.name,
    required this.slug,
    this.photoUrl,
    this.editions = 0,
  });

  final String id;
  final String name;
  final String slug;
  final String? photoUrl;

  /// How many editions they have published.
  final int editions;
}

class VjPage {
  const VjPage({
    required this.vj,
    this.bio,
    this.movies = const [],
    this.series = const [],
  });

  final VjCard vj;
  final String? bio;
  final List<EditionCard> movies;
  final List<EditionCard> series;
}

class Language {
  const Language({required this.code, required this.name, this.editions = 0});

  final String code;
  final String name;
  final int editions;
}

/// A genre with published editions, exactly as the catalogue stores it, so
/// it can be passed back to [CatalogueApi.editions] as `genre`.
class Genre {
  const Genre({required this.name, this.editions = 0});

  final String name;
  final int editions;
}

/// One of VeloraUG's own categories with published editions, such as
/// Indian or Kids. [slug] is passed back to [CatalogueApi.editions] as
/// `category`.
class Category {
  const Category({
    required this.slug,
    required this.name,
    this.editions = 0,
    this.movies = 0,
  });

  /// The category behind the Indian Movies chip.
  static const String indianSlug = 'indian';

  final String slug;
  final String name;
  final int editions;

  /// How many of [editions] are movies.
  final int movies;
}

enum CatalogueFailure {
  /// 404: it doesn't exist, or isn't published.
  notFound,

  /// 503: the API, its database, or these details aren't ready.
  busy,

  /// No answer: no network, the API stopped, a timeout, or CORS.
  unreachable,

  /// Any other answer.
  unexpected,
}

class CatalogueException implements Exception {
  const CatalogueException(this.failure);

  final CatalogueFailure failure;

  @override
  String toString() => 'CatalogueException(${failure.name})';
}

Never _bad() => throw const CatalogueException(CatalogueFailure.unexpected);

T _need<T>(Object? value) => value is T ? value : _bad();

T? _maybe<T>(Object? value) => value == null ? null : _need<T>(value);

/// A rating out of 10. JSON may send 7 for 7.0. Anything else is dropped,
/// not refused: a strange rating mustn't hide the title.
double? _rating(Object? value) =>
    value is num && value >= 0 && value <= 10 ? value.toDouble() : null;

int? _voteCount(Object? value) => value is int && value >= 0 ? value : null;

/// Calls the catalogue routes. They need no sign-in, so no token is ever
/// sent, and browsing works the same signed in or out.
class CatalogueApi {
  CatalogueApi({
    required this.baseUrl,
    required this.httpClient,
    this.mediaBaseUrl,
    this.timeout = const Duration(seconds: 15),
  });

  final Uri baseUrl;
  final http.Client httpClient;

  /// Where uploaded posters and VJ photos come from. Without it, only
  /// TMDB's images are shown.
  final Uri? mediaBaseUrl;

  /// Long enough for a database that has scaled to zero to wake.
  final Duration timeout;

  static const int pageSize = 24;

  /// Published editions, newest first. [vj] and [category] are slugs;
  /// [query] searches titles and VJ names.
  Future<EditionPage> editions({
    int offset = 0,
    int limit = pageSize,
    String? query,
    EditionKind? kind,
    String? vj,
    String? language,
    String? genre,
    String? category,
  }) async {
    final json = await _getObject('/api/v1/editions', {
      'limit': '$limit',
      if (offset > 0) 'offset': '$offset',
      'q': ?query,
      'kind': ?kind?.name,
      'vj': ?vj,
      'language': ?language,
      'genre': ?genre,
      'category': ?category,
    });
    final editions = _need<List<Object?>>(json['editions']);
    return EditionPage(
      editions: [for (final card in editions) _card(card)],
      nextOffset: _maybe<int>(json['next_offset']),
    );
  }

  Future<EditionDetail> edition(String id) async {
    final json = await _getObject(
      '/api/v1/editions/${Uri.encodeComponent(id)}',
    );
    final genres = _need<List<Object?>>(json['genres']);
    final seasons = _need<List<Object?>>(json['seasons'] ?? const []);
    return EditionDetail(
      card: _card(json),
      sourceTitle: _need<String>(json['source_title']),
      overview: _maybe<String>(json['overview']),
      runtimeMinutes: _maybe<int>(json['runtime_minutes']),
      genres: [for (final genre in genres) _need<String>(genre)],
      backdropUrl: safeImageUrl(json['backdrop_url'], gateway: mediaBaseUrl),
      trailerUrl: safeTrailerUrl(json['trailer_url']),
      vjPhotoUrl: safeImageUrl(json['vj_photo_url'], gateway: mediaBaseUrl),
      voteCount: _voteCount(json['vote_count']),
      itemId: _maybe<String>(json['item_id']),
      playable: _need<bool>(json['playable'] ?? false),
      seasons: [for (final season in seasons) _season(season)],
    );
  }

  /// The newest titles with something to watch, for Home's hero: at most
  /// three.
  Future<List<FeaturedTitle>> featured() async {
    final json = await _get('/api/v1/featured');
    return [
      for (final row in _need<List<Object?>>(json))
        if (_need<Map<String, Object?>>(row) case final title)
          FeaturedTitle(
            card: _card(title),
            genres: [
              for (final genre in _need<List<Object?>>(title['genres']))
                _need<String>(genre),
            ],
            backdropUrl: safeImageUrl(
              title['backdrop_url'],
              gateway: mediaBaseUrl,
            ),
            itemId: _maybe<String>(title['item_id']),
          ),
    ];
  }

  /// The rails to show below an edition's details, in order. The API only
  /// sends rails with at least three titles.
  Future<List<EditionRail>> rails(String editionId) async {
    final json = await _getObject(
      '/api/v1/editions/${Uri.encodeComponent(editionId)}/rails',
    );
    return [
      for (final row in _need<List<Object?>>(json['rails']))
        if (_need<Map<String, Object?>>(row) case final rail)
          EditionRail(
            key: _need<String>(rail['key']),
            editions: [
              for (final card in _need<List<Object?>>(rail['editions']))
                _card(card),
            ],
          ),
    ];
  }

  /// VJs with something published, by name.
  Future<List<VjCard>> vjs() async {
    final json = await _get('/api/v1/vjs');
    return [for (final vj in _need<List<Object?>>(json)) _vj(vj)];
  }

  Future<VjPage> vj(String slug) async {
    final json = await _getObject('/api/v1/vjs/${Uri.encodeComponent(slug)}');
    return VjPage(
      vj: _vj(json),
      bio: _maybe<String>(json['bio']),
      movies: [
        for (final card in _need<List<Object?>>(json['movies'])) _card(card),
      ],
      series: [
        for (final card in _need<List<Object?>>(json['series'])) _card(card),
      ],
    );
  }

  /// Languages with published editions, Luganda first.
  Future<List<Language>> languages() async {
    final json = await _get('/api/v1/languages');
    return [
      for (final row in _need<List<Object?>>(json))
        if (_need<Map<String, Object?>>(row) case final language)
          Language(
            code: _need<String>(language['code']),
            name: _need<String>(language['name']),
            editions: _need<int>(language['editions'] ?? 0),
          ),
    ];
  }

  /// Genres with published editions, most editions first.
  Future<List<Genre>> genres() async {
    final json = await _get('/api/v1/genres');
    return [
      for (final row in _need<List<Object?>>(json))
        if (_need<Map<String, Object?>>(row) case final genre)
          Genre(
            name: _need<String>(genre['name']),
            editions: _need<int>(genre['editions'] ?? 0),
          ),
    ];
  }

  /// Categories with published editions, most editions first.
  Future<List<Category>> categories() async {
    final json = await _get('/api/v1/categories');
    return [
      for (final row in _need<List<Object?>>(json))
        if (_need<Map<String, Object?>>(row) case final category)
          Category(
            slug: _need<String>(category['slug']),
            name: _need<String>(category['name']),
            editions: _need<int>(category['editions'] ?? 0),
            movies: _need<int>(category['movies'] ?? 0),
          ),
    ];
  }

  /// An edition card in another route's answer, such as watch history,
  /// checked as the catalogue's own are.
  EditionCard cardFrom(Object? value) => _card(value);

  EditionCard _card(Object? value) {
    final json = _need<Map<String, Object?>>(value);
    final id = _need<String>(json['id']);
    final title = _need<String>(json['title']);
    if (id.isEmpty || title.isEmpty) _bad();
    return EditionCard(
      id: id,
      kind: _kind(json['kind']) ?? _bad(),
      title: title,
      year: _maybe<int>(json['year']),
      posterUrl: safeImageUrl(json['poster_url'], gateway: mediaBaseUrl),
      vjName: _maybe<String>(json['vj_name']),
      vjSlug: _maybe<String>(json['vj_slug']),
      language: _need<String>(json['language']),
      label: _need<String>(json['label']),
      rating: _rating(json['rating']),
    );
  }

  Season _season(Object? value) {
    final json = _need<Map<String, Object?>>(value);
    final number = _need<int>(json['season']);
    return Season(
      season: number,
      episodes: [
        for (final row in _need<List<Object?>>(json['episodes']))
          if (_need<Map<String, Object?>>(row) case final episode)
            Episode(
              itemId: _need<String>(episode['item_id']),
              season: _need<int>(episode['season']),
              episode: _need<int>(episode['episode']),
              title: _maybe<String>(episode['title']),
              playable: _need<bool>(episode['playable'] ?? false),
            ),
      ],
    );
  }

  VjCard _vj(Object? value) {
    final json = _need<Map<String, Object?>>(value);
    return VjCard(
      id: _need<String>(json['id']),
      name: _need<String>(json['name']),
      slug: _need<String>(json['slug']),
      photoUrl: safeImageUrl(json['photo_url'], gateway: mediaBaseUrl),
      editions: _need<int>(json['editions'] ?? 0),
    );
  }

  Future<Map<String, Object?>> _getObject(
    String path, [
    Map<String, String>? params,
  ]) async => _need<Map<String, Object?>>(await _get(path, params));

  Future<Object?> _get(String path, [Map<String, String>? params]) async {
    final uri = baseUrl.replace(
      path: path,
      queryParameters: params == null || params.isEmpty ? null : params,
    );
    final http.Response response;
    try {
      response = await httpClient.get(uri).timeout(timeout);
    } on TimeoutException {
      throw const CatalogueException(CatalogueFailure.unreachable);
    } on Exception {
      // Includes a browser blocking the reply, which looks the same.
      throw const CatalogueException(CatalogueFailure.unreachable);
    }
    switch (response.statusCode) {
      case 200:
        break;
      case 404:
        throw const CatalogueException(CatalogueFailure.notFound);
      case 503:
        throw const CatalogueException(CatalogueFailure.busy);
      default:
        _bad();
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      _bad();
    }
  }
}

/// Words for each failure. They never repeat the server's text.
String catalogueFailureMessage(AppLocalizations l, CatalogueFailure failure) =>
    switch (failure) {
      CatalogueFailure.notFound => l.notAvailable,
      CatalogueFailure.busy => l.busy,
      CatalogueFailure.unreachable => l.unreachable,
      CatalogueFailure.unexpected => l.somethingWentWrong,
    };

/// Gives the screens below it the catalogue. [api] is null when this build
/// has no usable API address, and the screens say so.
class CatalogueScope extends InheritedWidget {
  const CatalogueScope({super.key, required this.api, required super.child});

  final CatalogueApi? api;

  static CatalogueApi? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CatalogueScope>()?.api;

  @override
  bool updateShouldNotify(CatalogueScope oldWidget) => api != oldWidget.api;
}
