import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/api/catalogue_api.dart';

const _id = '8012ee98-8bcf-4d15-aa5c-ccb3596d4fab';
const _poster = 'https://image.tmdb.org/t/p/w342/poster.jpg';

CatalogueApi _api(
  MockClient client, {
  Duration timeout = const Duration(seconds: 15),
}) => CatalogueApi(
  baseUrl: Uri.parse('http://127.0.0.1:8000'),
  httpClient: client,
  timeout: timeout,
);

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

Map<String, Object?> _summary({Object? poster = _poster}) => {
  'id': _id,
  'title': 'Interstellar',
  'year': 2014,
  'poster_url': poster,
};

void main() {
  test('list asks for a page, and sends no token', () async {
    late http.Request seen;
    final api = _api(
      MockClient((request) async {
        seen = request;
        return _json({
          'movies': [_summary()],
          'next_offset': 24,
        });
      }),
    );

    final page = await api.list();

    expect(seen.method, 'GET');
    expect(seen.url.toString(), 'http://127.0.0.1:8000/api/v1/movies?limit=24');
    expect(seen.headers.containsKey('Authorization'), isFalse);
    expect(page.nextOffset, 24);
    final movie = page.movies.single;
    expect(movie.id, _id);
    expect(movie.title, 'Interstellar');
    expect(movie.year, 2014);
    expect(movie.posterUrl, _poster);
  });

  test('list sends the search and the offset', () async {
    late Uri seen;
    final api = _api(
      MockClient((request) async {
        seen = request.url;
        return _json({'movies': [], 'next_offset': null});
      }),
    );

    final page = await api.list(offset: 24, query: 'star wars & co');

    expect(seen.queryParameters, {
      'limit': '24',
      'offset': '24',
      'q': 'star wars & co',
    });
    expect(page.movies, isEmpty);
    expect(page.nextOffset, isNull);
  });

  test('movie reads every field', () async {
    late Uri seen;
    final api = _api(
      MockClient((request) async {
        seen = request.url;
        return _json({
          ..._summary(),
          'overview': 'Explorers travel through a wormhole.',
          'runtime_minutes': 169,
          'genres': ['Adventure', 'Drama'],
          'backdrop_url': 'https://image.tmdb.org/t/p/w780/back.jpg',
        });
      }),
    );

    final movie = await api.movie(_id);

    expect(seen.path, '/api/v1/movies/$_id');
    expect(movie.title, 'Interstellar');
    expect(movie.overview, 'Explorers travel through a wormhole.');
    expect(movie.runtimeMinutes, 169);
    expect(movie.genres, ['Adventure', 'Drama']);
    expect(movie.backdropUrl, 'https://image.tmdb.org/t/p/w780/back.jpg');
  });

  test('missing optional fields become null', () async {
    final api = _api(
      MockClient(
        (request) async => _json({
          'id': _id,
          'title': 'Plain',
          'year': null,
          'poster_url': null,
          'overview': null,
          'runtime_minutes': null,
          'genres': <String>[],
          'backdrop_url': null,
        }),
      ),
    );

    final movie = await api.movie(_id);

    expect(movie.year, isNull);
    expect(movie.posterUrl, isNull);
    expect(movie.overview, isNull);
    expect(movie.genres, isEmpty);
  });

  for (final poster in [
    'http://image.tmdb.org/t/p/w342/a.jpg',
    'https://evil.example/a.jpg',
    'https://image.tmdb.org.evil.example/a.jpg',
    'javascript:alert(1)',
    42,
  ]) {
    test(
      'an image address not on TMDB over HTTPS is ignored: $poster',
      () async {
        final api = _api(
          MockClient(
            (request) async => _json({
              'movies': [_summary(poster: poster)],
              'next_offset': null,
            }),
          ),
        );

        expect((await api.list()).movies.single.posterUrl, isNull);
      },
    );
  }

  for (final (status, failure) in [
    (404, CatalogueFailure.notFound),
    (503, CatalogueFailure.busy),
    (500, CatalogueFailure.unexpected),
    (422, CatalogueFailure.unexpected),
  ]) {
    test('HTTP $status is $failure', () async {
      final api = _api(
        MockClient((request) async => _json({'detail': 'x'}, status)),
      );

      await expectLater(
        api.movie(_id),
        throwsA(
          isA<CatalogueException>().having(
            (e) => e.failure,
            'failure',
            failure,
          ),
        ),
      );
    });
  }

  test('no answer is unreachable', () async {
    final api = _api(
      MockClient((request) async => throw http.ClientException('blocked')),
    );

    await expectLater(
      api.list(),
      throwsA(
        isA<CatalogueException>().having(
          (e) => e.failure,
          'failure',
          CatalogueFailure.unreachable,
        ),
      ),
    );
  });

  test('a slow answer is unreachable', () async {
    final api = _api(
      MockClient((request) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 10),
    );

    await expectLater(
      api.list(),
      throwsA(
        isA<CatalogueException>().having(
          (e) => e.failure,
          'failure',
          CatalogueFailure.unreachable,
        ),
      ),
    );
  });

  for (final body in [
    'not json',
    '[]',
    '{"movies": "x", "next_offset": null}',
    '{"movies": [{"id": "", "title": "x"}], "next_offset": null}',
    '{"movies": [{"id": "a", "title": 3}], "next_offset": null}',
    '{"movies": [], "next_offset": "24"}',
  ]) {
    test('a malformed list is unexpected: $body', () async {
      final api = _api(MockClient((request) async => http.Response(body, 200)));

      await expectLater(
        api.list(),
        throwsA(
          isA<CatalogueException>().having(
            (e) => e.failure,
            'failure',
            CatalogueFailure.unexpected,
          ),
        ),
      );
    });
  }

  test('failure messages never repeat the server', () {
    for (final failure in CatalogueFailure.values) {
      expect(catalogueFailureMessage(failure), isNotEmpty);
    }
    expect(
      catalogueFailureMessage(CatalogueFailure.notFound),
      "This movie isn't available.",
    );
  });
}
