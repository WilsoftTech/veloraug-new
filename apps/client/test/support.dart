import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/admin/uploads/upload_queue.dart';
import 'package:veloraug/api/admin_api.dart';
import 'package:veloraug/api/catalogue_api.dart';
import 'package:veloraug/api/playback_api.dart';
import 'package:veloraug/app.dart';
import 'package:veloraug/auth/auth_controller.dart';
import 'package:veloraug/auth/oauth_client.dart';
import 'package:veloraug/auth/oauth_config.dart';
import 'package:veloraug/auth/token_store.dart';
import 'package:veloraug/player/video_view.dart';

const apiBase = 'http://127.0.0.1:8000';
const gateway = 'http://127.0.0.1:8787';

/// A sign-in that never reaches a network.
AuthController fakeAuth({required bool signedIn, String? email}) =>
    AuthController(
      client: OAuthClient(
        config: OAuthConfig(
          issuer: 'https://auth.example.test/neondb/auth',
          clientId: 'client-1',
          resource: 'https://api.example.test',
          redirectUri: Uri.parse('https://pages.example.test/auth/callback'),
          signOutPage: Uri.parse('https://pages.example.test/sign-out'),
        ),
        httpClient: MockClient((_) async => http.Response('', 500)),
        browserStep: (_, _) async => throw Exception('No browser in tests.'),
      ),
      store: MemoryTokenStore(
        signedIn
            ? StoredSession(
                accessToken: 'ACCESS-SECRET',
                refreshToken: 'REFRESH-SECRET',
                expiresAt: DateTime.now().add(const Duration(hours: 1)),
                email: email,
              )
            : null,
      ),
    );

http.Response json(Object? body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

/// An edition card, as the API lists it.
Map<String, Object?> card(
  String id, {
  String kind = 'movie',
  String title = 'Fast X',
  String? vj = 'VJ Junior',
  String language = 'lg',
  int? year = 2023,
}) => {
  'id': id,
  'kind': kind,
  'title': title,
  'year': year,
  'poster_url': 'https://image.tmdb.org/t/p/w342/$id.jpg',
  'vj_name': vj,
  'vj_slug': vj?.toLowerCase().replaceAll(' ', '-'),
  'language': language,
  'label': vj == null ? 'Test' : 'Luganda · $vj',
};

/// A movie edition's page.
Map<String, Object?> movieDetail(
  String id, {
  String title = 'Fast X',
  String vj = 'VJ Junior',
  bool playable = true,
  String? trailer = 'https://www.youtube.com/watch?v=abc123',
}) => {
  ...card(id, title: title, vj: vj),
  'source_title': title,
  'overview': 'Dom races again.',
  'runtime_minutes': 141,
  'genres': ['Action'],
  'backdrop_url': null,
  'trailer_url': trailer,
  'vj_id': 'vj-1',
  'vj_photo_url': null,
  'item_id': 'item-$id',
  'playable': playable,
  'seasons': <Object>[],
};

Map<String, Object?> episode(
  String id,
  int season,
  int number, {
  bool playable = true,
  String? title,
}) => {
  'item_id': id,
  'season': season,
  'episode': number,
  'title': title,
  'playable': playable,
};

/// A series edition's page with two seasons: S1 E1, S1 E2, S2 E1.
Map<String, Object?> seriesDetail(String id, {String vj = 'VJ Emmy'}) => {
  ...card(id, kind: 'series', title: 'Kabaka', vj: vj),
  'source_title': 'The King',
  'overview': 'A king rises.',
  'runtime_minutes': null,
  'genres': ['Drama'],
  'backdrop_url': null,
  'trailer_url': null,
  'vj_id': 'vj-2',
  'vj_photo_url': null,
  'item_id': null,
  'playable': true,
  'seasons': [
    {
      'season': 1,
      'episodes': [
        episode('e11', 1, 1, title: 'The Crown'),
        episode('e12', 1, 2),
      ],
    },
    {
      'season': 2,
      'episodes': [episode('e21', 2, 1)],
    },
  ],
};

typedef Answer = FutureOr<http.Response> Function(http.Request request);

/// The API: the catalogue from [editions] and [details], grants, and the
/// admin routes from [admin]. Each test sets what it needs, and sees what
/// was asked.
class FakeApi {
  final requests = <http.Request>[];
  final editions = <Map<String, Object?>>[];
  final details = <String, Map<String, Object?>>{};
  final vjs = <Map<String, Object?>>[];
  final vjPages = <String, Map<String, Object?>>{};
  List<Map<String, Object?>> languages = [
    {'code': 'lg', 'name': 'Luganda', 'editions': 1},
  ];

  /// Answers any catalogue request with this status instead, when set.
  int? catalogueStatus;

  int grants = 0;
  int grantStatus = 200;
  DateTime expiresAt = DateTime.utc(2030);
  final granted = <String>[];

  bool isAdmin = false;

  /// Admin answers, by "METHOD /path" after /api/v1/admin.
  final admin = <String, Answer>{};

  List<Uri> get searches => [
    for (final r in requests)
      if (r.url.queryParameters.containsKey('q')) r.url,
  ];

  List<String> get adminCalls => [
    for (final r in requests)
      if (r.url.path.startsWith('/api/v1/admin/') &&
          r.url.path != '/api/v1/admin/me')
        '${r.method} ${r.url.path.substring('/api/v1/admin'.length)}',
  ];

  /// Answers first, when it returns something: to hold a request back.
  Future<http.Response>? Function(http.Request request)? intercept;

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    final held = intercept?.call(request);
    if (held != null) return held;
    return _answer(request);
  });

  FutureOr<http.Response> _answer(http.Request request) {
    final path = request.url.path;
    if (path.startsWith('/api/v1/admin/')) {
      final key = '${request.method} ${path.substring('/api/v1/admin'.length)}';
      if (key == 'GET /me') {
        return isAdmin ? json({'user_id': 'u1', 'admin': true}) : json({}, 403);
      }
      if (!isAdmin) {
        return json({'detail': "This account isn't an admin."}, 403);
      }
      final answer = admin[key];
      if (answer == null) return json({'detail': 'Not found'}, 404);
      return answer(request);
    }
    if (path.endsWith('/playback')) {
      grants++;
      granted.add(request.url.pathSegments[3]);
      if (grantStatus != 200) return json({}, grantStatus);
      return json({
        'playlist_url': '$gateway/v1/grant-$grants.sig/master.m3u8',
        'expires_at': expiresAt.toIso8601String(),
      });
    }
    if (catalogueStatus case final status?) {
      return json({'detail': 'x'}, status);
    }
    if (path == '/api/v1/editions') return _list(request.url.queryParameters);
    if (path.startsWith('/api/v1/editions/')) {
      final detail = details[request.url.pathSegments.last];
      return detail == null
          ? json({'detail': "This isn't available."}, 404)
          : json(detail);
    }
    if (path == '/api/v1/vjs') return json(vjs);
    if (path.startsWith('/api/v1/vjs/')) {
      final page = vjPages[request.url.pathSegments.last];
      return page == null ? json({}, 404) : json(page);
    }
    if (path == '/api/v1/languages') return json(languages);
    return json({}, 404);
  }

  http.Response _list(Map<String, String> query) {
    final q = query['q']?.toLowerCase();
    final matching = [
      for (final e in editions)
        if ((query['kind'] == null || e['kind'] == query['kind']) &&
            (query['vj'] == null || e['vj_slug'] == query['vj']) &&
            (query['language'] == null || e['language'] == query['language']) &&
            (q == null ||
                '${e['title']} ${e['vj_name']}'.toLowerCase().contains(q)))
          e,
    ];
    final offset = int.parse(query['offset'] ?? '0');
    final limit = int.parse(query['limit'] ?? '24');
    final page = matching.skip(offset).take(limit).toList();
    return json({
      'editions': page,
      'next_offset': offset + limit < matching.length ? offset + limit : null,
    });
  }

  CatalogueApi catalogue() => CatalogueApi(
    baseUrl: Uri.parse(apiBase),
    mediaBaseUrl: Uri.parse(gateway),
    httpClient: client,
  );

  PlaybackApi playback(AuthController auth) => PlaybackApi(
    baseUrl: Uri.parse(apiBase),
    mediaBaseUrl: Uri.parse(gateway),
    httpClient: client,
    accessToken: auth.accessToken,
  );

  AdminApi adminApi(AuthController auth) => AdminApi(
    baseUrl: Uri.parse(apiBase),
    mediaBaseUrl: Uri.parse(gateway),
    httpClient: client,
    accessToken: auth.accessToken,
  );
}

/// Pumps the whole app against [api].
Future<AuthController> pumpApp(
  WidgetTester tester,
  FakeApi api, {
  bool signedIn = false,
  bool showAdmin = true,
  Size size = const Size(1200, 1600),
  UploadQueue Function(AuthController auth)? uploads,
  Future<List<PickedVideo>> Function()? pickVideos,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final auth = fakeAuth(signedIn: signedIn, email: 'owner@example.test');
  await auth.restore();
  await tester.pumpWidget(
    VeloraApp(
      authController: auth,
      catalogueApi: api.catalogue(),
      playbackApi: api.playback(auth),
      adminApi: api.adminApi(auth),
      uploadQueue: uploads?.call(auth),
      pickVideos: pickVideos ?? () async => const [],
      showAdmin: showAdmin,
    ),
  );
  await tester.pumpAndSettle();
  return auth;
}

Future<void> goTo(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

/// Stands in for the video: records what it was asked to play.
class FakeVideo {
  final requests = <VideoViewRequest>[];

  Widget build(BuildContext context, VideoViewRequest request) {
    requests.add(request);
    return Text('playing ${request.url.pathSegments[1]}');
  }
}
