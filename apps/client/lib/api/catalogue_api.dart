import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

/// A movie in a list: enough for a card.
class MovieSummary {
  const MovieSummary({
    required this.id,
    required this.title,
    this.year,
    this.posterUrl,
  });

  final String id;
  final String title;
  final int? year;
  final String? posterUrl;
}

/// One page of movies. [nextOffset] is null on the last page.
class MoviePage {
  const MoviePage({required this.movies, this.nextOffset});

  final List<MovieSummary> movies;
  final int? nextOffset;
}

/// Everything the detail screen shows.
class MovieDetail {
  const MovieDetail({
    required this.id,
    required this.title,
    this.year,
    this.overview,
    this.runtimeMinutes,
    this.genres = const [],
    this.posterUrl,
    this.backdropUrl,
  });

  final String id;
  final String title;
  final int? year;
  final String? overview;
  final int? runtimeMinutes;
  final List<String> genres;
  final String? posterUrl;
  final String? backdropUrl;
}

enum CatalogueFailure {
  /// 404: the movie doesn't exist, or isn't published.
  notFound,

  /// 503: the API, its database, or this movie's details aren't ready.
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

/// Images are shown only from TMDB's image server, over HTTPS. Anything else
/// in an answer is ignored, so a bad answer can't make the app load an
/// address from elsewhere.
String? _imageUrl(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host != 'image.tmdb.org') {
    return null;
  }
  return value;
}

/// Calls the catalogue routes. They need no sign-in, so no token is ever
/// sent, and browsing works the same signed in or out.
class CatalogueApi {
  CatalogueApi({
    required this.baseUrl,
    required this.httpClient,
    this.timeout = const Duration(seconds: 15),
  });

  final Uri baseUrl;
  final http.Client httpClient;

  /// Long enough for a database that has scaled to zero to wake.
  final Duration timeout;

  static const int pageSize = 24;

  /// Published movies, newest first, or those whose title contains [query].
  Future<MoviePage> list({int offset = 0, String? query}) async {
    final params = {
      'limit': '$pageSize',
      if (offset > 0) 'offset': '$offset',
      'q': ?query,
    };
    final json = await _get(
      baseUrl.replace(path: '/api/v1/movies', queryParameters: params),
    );
    final movies = json['movies'];
    final next = json['next_offset'];
    if (movies is! List || (next != null && next is! int)) {
      throw const CatalogueException(CatalogueFailure.unexpected);
    }
    return MoviePage(
      movies: [for (final movie in movies) _summary(movie)],
      nextOffset: next as int?,
    );
  }

  Future<MovieDetail> movie(String id) async {
    final json = await _get(
      baseUrl.replace(path: '/api/v1/movies/${Uri.encodeComponent(id)}'),
    );
    final summary = _summary(json);
    final overview = json['overview'];
    final runtime = json['runtime_minutes'];
    final genres = json['genres'];
    if ((overview != null && overview is! String) ||
        (runtime != null && runtime is! int) ||
        genres is! List ||
        genres.any((genre) => genre is! String)) {
      throw const CatalogueException(CatalogueFailure.unexpected);
    }
    return MovieDetail(
      id: summary.id,
      title: summary.title,
      year: summary.year,
      overview: overview as String?,
      runtimeMinutes: runtime as int?,
      genres: genres.cast<String>(),
      posterUrl: summary.posterUrl,
      backdropUrl: _imageUrl(json['backdrop_url']),
    );
  }

  MovieSummary _summary(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const CatalogueException(CatalogueFailure.unexpected);
    }
    final id = json['id'];
    final title = json['title'];
    final year = json['year'];
    if (id is! String ||
        id.isEmpty ||
        title is! String ||
        title.isEmpty ||
        (year != null && year is! int)) {
      throw const CatalogueException(CatalogueFailure.unexpected);
    }
    return MovieSummary(
      id: id,
      title: title,
      year: year as int?,
      posterUrl: _imageUrl(json['poster_url']),
    );
  }

  Future<Map<String, Object?>> _get(Uri uri) async {
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
        throw const CatalogueException(CatalogueFailure.unexpected);
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const CatalogueException(CatalogueFailure.unexpected);
    }
    if (json is! Map<String, Object?>) {
      throw const CatalogueException(CatalogueFailure.unexpected);
    }
    return json;
  }
}

/// Words for each failure. They never repeat the server's text.
String catalogueFailureMessage(CatalogueFailure failure) => switch (failure) {
  CatalogueFailure.notFound => "This movie isn't available.",
  CatalogueFailure.busy => 'VeloraUG is busy right now. Try again in a moment.',
  CatalogueFailure.unreachable =>
    "Couldn't reach VeloraUG. Check your connection and try again.",
  CatalogueFailure.unexpected => 'Something went wrong. Try again.',
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
