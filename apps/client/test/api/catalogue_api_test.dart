import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/api/catalogue_api.dart';
import 'package:veloraug/api/safe_urls.dart';
import 'package:veloraug/l10n/app_localizations_en.dart';

const _gateway = 'http://127.0.0.1:8787';

Map<String, Object?> card(
  String id, {
  String kind = 'movie',
  String title = 'Fast X',
  String? vj = 'VJ Junior',
  String? poster = 'https://image.tmdb.org/t/p/w342/p.jpg',
}) => {
  'id': id,
  'kind': kind,
  'title': title,
  'year': 2023,
  'poster_url': poster,
  'vj_name': vj,
  'vj_slug': vj?.toLowerCase().replaceAll(' ', '-'),
  'language': 'lg',
  'label': vj == null ? 'Test' : 'Luganda · $vj',
};

Map<String, Object?> seriesDetail() => {
  ...card('s1', kind: 'series', title: 'Kabaka', vj: 'VJ Emmy'),
  'source_title': 'The King',
  'overview': 'A king.',
  'runtime_minutes': null,
  'genres': ['Drama'],
  'backdrop_url': 'https://image.tmdb.org/t/p/w780/b.jpg',
  'trailer_url': 'https://www.youtube.com/watch?v=abc123',
  'vj_id': 'vj-1',
  'vj_photo_url': '$_gateway/i/vjs/x/photo.jpg',
  'item_id': null,
  'playable': true,
  'seasons': [
    {
      'season': 1,
      'episodes': [
        {
          'item_id': 'e11',
          'season': 1,
          'episode': 1,
          'title': 'Pilot',
          'playable': true,
        },
        {
          'item_id': 'e12',
          'season': 1,
          'episode': 2,
          'title': null,
          'playable': false,
        },
      ],
    },
    {
      'season': 2,
      'episodes': [
        {
          'item_id': 'e21',
          'season': 2,
          'episode': 1,
          'title': null,
          'playable': true,
        },
      ],
    },
  ],
};

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

CatalogueApi _api(http.Response Function(Uri url) answer, [List<Uri>? asked]) =>
    CatalogueApi(
      baseUrl: Uri.parse('http://127.0.0.1:8000'),
      mediaBaseUrl: Uri.parse(_gateway),
      httpClient: MockClient((request) async {
        asked?.add(request.url);
        return answer(request.url);
      }),
    );

Future<CatalogueFailure> _failure(Future<Object?> Function() call) async {
  try {
    await call();
  } on CatalogueException catch (error) {
    return error.failure;
  }
  fail('no failure');
}

void main() {
  group('editions', () {
    test('lists cards with their VJ, and sends the filters', () async {
      final asked = <Uri>[];
      final page =
          await _api(
            (_) => _json({
              'editions': [card('m1'), card('t1', vj: null)],
              'next_offset': 24,
            }),
            asked,
          ).editions(
            offset: 24,
            kind: EditionKind.series,
            vj: 'vj-emmy',
            query: 'kab',
          );

      expect(asked.single.path, '/api/v1/editions');
      expect(asked.single.queryParameters, {
        'limit': '24',
        'offset': '24',
        'q': 'kab',
        'kind': 'series',
        'vj': 'vj-emmy',
      });
      expect(page.nextOffset, 24);
      expect(page.editions.first.vjName, 'VJ Junior');
      expect(page.editions.first.label, 'Luganda · VJ Junior');
      expect(page.editions.last.vjName, isNull);
    });

    test('a rating is read as a number out of 10, or dropped', () async {
      final page = await _api(
        (_) => _json({
          'editions': [
            {...card('a'), 'rating': 7.4},
            {...card('b'), 'rating': 7},
            {...card('c'), 'rating': null},
            {...card('d'), 'rating': '7.4'},
            {...card('e'), 'rating': 11},
            {...card('f'), 'rating': -1},
            card('g'),
          ],
          'next_offset': null,
        }),
      ).editions();

      expect(
        [for (final e in page.editions) e.rating],
        [7.4, 7.0, null, null, null, null, null],
      );
    });

    test("an edition's page has its rating and vote count", () async {
      final rated = await _api(
        (_) => _json({...seriesDetail(), 'rating': 8.1, 'vote_count': 1234}),
      ).edition('s1');
      final unrated = await _api((_) => _json(seriesDetail())).edition('s1');
      final strange = await _api(
        (_) => _json({...seriesDetail(), 'rating': 8.1, 'vote_count': -3}),
      ).edition('s1');

      expect((rated.rating, rated.voteCount), (8.1, 1234));
      expect((unrated.rating, unrated.voteCount), (null, null));
      expect(strange.voteCount, isNull);
    });

    test('a series has its seasons in order, and its trailer', () async {
      final edition = await _api((_) => _json(seriesDetail())).edition('s1');

      expect(edition.kind, EditionKind.series);
      expect(edition.itemId, isNull);
      expect(edition.episodes.map((e) => e.itemId), ['e11', 'e12', 'e21']);
      expect(
        edition.trailerUrl.toString(),
        'https://www.youtube.com/watch?v=abc123',
      );
      expect(edition.vjPhotoUrl, '$_gateway/i/vjs/x/photo.jpg');
    });

    test('a malformed answer is unexpected', () async {
      final api = _api(
        (_) => _json({
          'editions': [
            {...card('m1'), 'kind': 'film'},
          ],
          'next_offset': null,
        }),
      );
      expect(await _failure(api.editions), CatalogueFailure.unexpected);
    });

    for (final (status, failure) in [
      (404, CatalogueFailure.notFound),
      (503, CatalogueFailure.busy),
      (500, CatalogueFailure.unexpected),
    ]) {
      test('$status is ${failure.name}', () async {
        final api = _api((_) => _json({}, status));
        expect(await _failure(() => api.edition('x')), failure);
      });
    }

    test('no answer is unreachable', () async {
      final api = CatalogueApi(
        baseUrl: Uri.parse('http://127.0.0.1:8000'),
        httpClient: MockClient((_) => throw http.ClientException('down')),
      );
      expect(await _failure(api.vjs), CatalogueFailure.unreachable);
    });
  });

  test('VJs, a VJ page and languages', () async {
    final api = _api(
      (url) => switch (url.path) {
        '/api/v1/vjs' => _json([
          {
            'id': 'v1',
            'name': 'VJ Emmy',
            'slug': 'vj-emmy',
            'photo_url': null,
            'editions': 1,
          },
        ]),
        '/api/v1/vjs/vj-emmy' => _json({
          'id': 'v1',
          'name': 'VJ Emmy',
          'slug': 'vj-emmy',
          'photo_url': '$_gateway/i/vjs/v1/a.jpg',
          'editions': 1,
          'bio': 'About Emmy.',
          'movies': [],
          'series': [card('s1', kind: 'series', vj: 'VJ Emmy')],
        }),
        _ => _json([
          {'code': 'lg', 'name': 'Luganda', 'editions': 2},
        ]),
      },
    );

    expect((await api.vjs()).single.slug, 'vj-emmy');
    final page = await api.vj('vj-emmy');
    expect(page.bio, 'About Emmy.');
    expect(page.series.single.kind, EditionKind.series);
    expect((await api.languages()).single.name, 'Luganda');
  });

  group('next episode', () {
    const episodes = [
      Episode(itemId: 'a', season: 1, episode: 1, playable: true),
      Episode(itemId: 'b', season: 1, episode: 2, playable: false),
      Episode(itemId: 'c', season: 1, episode: 3, playable: true),
      Episode(itemId: 'd', season: 2, episode: 1, playable: true),
    ];

    test('is the next in the season, skipping one with no video', () {
      expect(nextEpisode(episodes, 'a')?.itemId, 'c');
    });

    test('then the first of the next season', () {
      expect(nextEpisode(episodes, 'c')?.itemId, 'd');
    });

    test('is none after the last, or for an unknown item', () {
      expect(nextEpisode(episodes, 'd'), isNull);
      expect(nextEpisode(episodes, 'zzz'), isNull);
    });
  });

  group('addresses from answers', () {
    final gateway = Uri.parse(_gateway);

    test('images come only from TMDB or the gateway', () {
      expect(safeImageUrl('https://image.tmdb.org/t/p/w342/p.jpg'), isNotNull);
      expect(
        safeImageUrl('$_gateway/i/posters/x/p.jpg', gateway: gateway),
        isNotNull,
      );
      for (final bad in [
        'http://image.tmdb.org/t/p/w342/p.jpg',
        'https://evil.example/p.jpg',
        '$_gateway/v1/grant/master.m3u8',
        '$_gateway/i/posters/x/p.jpg?x=1',
        'https://user@image.tmdb.org/p.jpg',
        42,
      ]) {
        expect(safeImageUrl(bad, gateway: gateway), isNull, reason: '$bad');
      }
      expect(safeImageUrl('$_gateway/i/posters/x/p.jpg'), isNull);
    });

    test('trailers are YouTube watch pages only', () {
      expect(
        safeTrailerUrl('https://www.youtube.com/watch?v=abc123'),
        isNotNull,
      );
      for (final bad in [
        'http://www.youtube.com/watch?v=abc123',
        'https://youtube.evil.example/watch?v=abc123',
        'https://www.youtube.com/redirect?q=https://evil.example',
        'https://www.youtube.com/watch?v=abc123&next=x',
        'https://www.youtube.com/watch?v=<script>',
      ]) {
        expect(safeTrailerUrl(bad), isNull, reason: bad);
      }
    });
  });

  test('messages never repeat the server', () {
    for (final failure in CatalogueFailure.values) {
      expect(
        catalogueFailureMessage(AppLocalizationsEn(), failure),
        isNotEmpty,
      );
    }
  });
}
