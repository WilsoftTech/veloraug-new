import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/admin/uploads/upload_queue.dart';
import 'package:veloraug/api/admin_api.dart';
import 'package:veloraug/api/catalogue_api.dart';
import 'package:veloraug/api/device_store.dart';
import 'package:veloraug/api/playback_api.dart';
import 'package:veloraug/app.dart';
import 'package:veloraug/auth/auth_controller.dart';
import 'package:veloraug/auth/oauth_client.dart';
import 'package:veloraug/auth/oauth_config.dart';
import 'package:veloraug/auth/token_store.dart';
import 'package:veloraug/downloads/downloads.dart';
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
  double? rating,
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
  'rating': rating,
};

/// A title in Home's hero. A movie has its item to play; a series none.
Map<String, Object?> featuredTitle(
  String id, {
  String kind = 'movie',
  String title = 'Fast X',
  String? vj = 'VJ Junior',
  double? rating,
  List<String> genres = const ['Action'],
  bool backdrop = true,
}) => {
  ...card(id, kind: kind, title: title, vj: vj, rating: rating),
  'genres': genres,
  'backdrop_url': backdrop ? 'https://image.tmdb.org/t/p/w1280/$id.jpg' : null,
  'item_id': kind == 'movie' ? 'item-$id' : null,
};

/// A category as GET /api/v1/categories lists it.
Map<String, Object?> category(
  String slug,
  String name, {
  int editions = 3,
  int movies = 3,
}) => {'slug': slug, 'name': name, 'editions': editions, 'movies': movies};

/// A movie edition's page.
Map<String, Object?> movieDetail(
  String id, {
  String title = 'Fast X',
  String vj = 'VJ Junior',
  bool playable = true,
  String? trailer = 'https://www.youtube.com/watch?v=abc123',
  double? rating,
  int? votes,
}) => {
  ...card(id, title: title, vj: vj, rating: rating),
  'vote_count': votes,
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

  /// Home's hero, as GET /api/v1/featured lists it. Empty by default, so
  /// Home keeps its welcome panel.
  final featured = <Map<String, Object?>>[];
  int featuredStatus = 200;

  /// An edition page's rails, by edition ID, as {key: cards}. None by
  /// default.
  final rails = <String, Map<String, List<Map<String, Object?>>>>{};
  int railsStatus = 200;

  /// Because you watched, by edition ID: (watched title, cards).
  final because = <String, (String, List<Map<String, Object?>>)>{};
  List<Map<String, Object?>> languages = [
    {'code': 'lg', 'name': 'Luganda', 'editions': 1},
  ];

  /// Genres as GET /api/v1/genres lists them. An edition matches a genre
  /// when its `genres` holds exactly that value.
  List<Map<String, Object?>> genres = [];

  /// Categories as GET /api/v1/categories lists them. An edition matches a
  /// category when its `categories` holds that slug.
  List<Map<String, Object?>> categories = [];
  int categoriesStatus = 200;

  /// Answers any catalogue request with this status instead, when set.
  int? catalogueStatus;

  /// The account hub: watch history, the notification inbox and deletion.
  List<Map<String, Object?>> history = [];
  final watchList = <String, Map<String, Object?>>{};
  final watchListItems = <String, Map<String, Object?>>{};
  int historyStatus = 200;
  final positions = <Map<String, Object?>>[];
  Map<String, Object?> inbox = {'notifications': <Object>[], 'unread': 0};
  int inboxStatus = 200;
  int markReadStatus = 204;
  final markedRead = <Object?>[];
  Map<String, Object?> deletion = {
    'available': false,
    'state': 'none',
    'requested_at': null,
  };
  int deletionStatusCode = 200;

  /// POST /me/deletion's answer: status and body. Null: completed.
  (int, Object?)? deletionAnswer;
  int deletions = 0;

  int grants = 0;
  int grantStatus = 200;
  DateTime expiresAt = DateTime.utc(2030);
  final granted = <String>[];

  bool isAdmin = false;

  /// Passes, Step 10C: what's for sale, the viewer's pass, and the states a
  /// payment goes through as it's checked. The last state repeats.
  List<Map<String, Object?>> passPlans = [
    plan('velora_start', 'Velora Start', 6000, 7, 1),
    plan('velora_prime', 'Velora Prime', 18000, 30, 1, featured: true),
    plan('velora_max', 'Velora Max', 150000, 365, 3),
  ];
  Map<String, Object?> myPass = {
    'active': false,
    'current_ends_at': null,
    'ends_at': null,
    'checking': false,
  };
  int checkoutStatus = 201;
  String paymentPage = 'https://cybqa.pesapal.com/iframe/pay-1';
  List<String> paymentStates = ['pending', 'completed'];
  DateTime passEndsAt = DateTime.utc(2026, 11, 20, 9, 30);
  int paymentChecks = 0;
  final checkouts = <Map<String, Object?>>[];

  /// Milestone 10: the viewer's devices, payments, what is playing, and
  /// what the grant route says about this device.
  List<Map<String, Object?>> devices = [];
  int devicesAllowed = 1;
  bool devicesOverLimit = false;
  List<Map<String, Object?>> payments = [];
  List<Map<String, Object?>> playing = [];
  final deviceRegistrations = <http.Request>[];
  final removedDevices = <String>[];
  final stoppedSessions = <String>[];

  /// The grant route's body when it refuses, such as a device_limit.
  Map<String, Object?>? grantRefusal;

  /// With passes required: grants carry a session and a heartbeat.
  bool sessions = false;
  int heartbeatStatus = 200;
  int heartbeats = 0;

  /// The device header sent with each grant request.
  final grantDevices = <String?>[];

  /// The master playlist the media gateway serves for every grant.
  String masterPlaylist = '''
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-STREAM-INF:BANDWIDTH=1088017,RESOLUTION=640x266
360p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1854833,RESOLUTION=854x356
480p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3582027,RESOLUTION=1280x534
720p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3829844,RESOLUTION=1920x800
1080p/index.m3u8
''';

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
    if (request.url.host == '127.0.0.1' &&
        request.url.port == 8787 &&
        path.endsWith('/master.m3u8')) {
      return http.Response(masterPlaylist, 200);
    }
    if (path == '/api/v1/passes/plans') return json(passPlans);
    if (path == '/api/v1/me/payments') return json(payments);
    if (path == '/api/v1/me/devices' && request.method == 'GET') {
      return json({
        'devices': devices,
        'allowed': devicesAllowed,
        'streams_allowed': devicesAllowed,
        'over_limit': devicesOverLimit,
      });
    }
    if (path == '/api/v1/me/devices' && request.method == 'POST') {
      deviceRegistrations.add(request);
      return json({
        'device': {'id': deviceId, 'label': 'Phone', 'current': true},
        'credential': deviceCredential,
      }, 201);
    }
    if (path.startsWith('/api/v1/me/devices/') && request.method == 'DELETE') {
      removedDevices.add(request.url.pathSegments.last);
      devices.removeWhere((d) => d['id'] == request.url.pathSegments.last);
      return http.Response('', 204);
    }
    if (path.endsWith('/heartbeat')) {
      heartbeats++;
      return json({'live': heartbeatStatus == 200}, heartbeatStatus);
    }
    if (path == '/api/v1/me/playback-sessions') return json(playing);
    if (path.startsWith('/api/v1/me/playback-sessions/') &&
        request.method == 'DELETE') {
      stoppedSessions.add(request.url.pathSegments.last);
      grantRefusal = null;
      return http.Response('', 204);
    }
    if (path == '/api/v1/me/pass') return json(myPass);
    if (path == '/api/v1/me/history') {
      return historyStatus == 200
          ? json(history)
          : json({'detail': 'x'}, historyStatus);
    }
    if (path.startsWith('/api/v1/me/because-you-watched/')) {
      final found = because[request.url.pathSegments.last];
      return json(
        found == null
            ? null
            : {
                'watched_id': 'watched',
                'watched_title': found.$1,
                'editions': found.$2,
              },
      );
    }
    if (path == '/api/v1/me/watch-list') {
      return json(watchList.values.toList());
    }
    if (path.startsWith('/api/v1/me/watch-list/editions/')) {
      final editionId = request.url.pathSegments.last;
      return json([
        for (final entry in watchList.entries)
          if ((entry.value['edition'] as Map)['id'] == editionId) entry.key,
      ]);
    }
    if (path.startsWith('/api/v1/me/watch-list/')) {
      final id = request.url.pathSegments.last;
      if (request.method == 'DELETE') {
        watchList.remove(id);
      } else if (watchListItems[id] case final item?) {
        watchList[id] = item;
      } else {
        return json({}, 404);
      }
      return http.Response('', 204);
    }
    if (path.startsWith('/api/v1/me/history/') && request.method == 'PUT') {
      positions.add({
        'item': request.url.pathSegments[4],
        ...jsonDecode(request.body) as Map<String, Object?>,
      });
      return http.Response('', 204);
    }
    if (path == '/api/v1/me/notifications') {
      return inboxStatus == 200
          ? json(inbox)
          : json({'detail': 'x'}, inboxStatus);
    }
    if (path == '/api/v1/me/notifications/read') {
      markedRead.add(jsonDecode(request.body));
      if (markReadStatus != 204) return json({'detail': 'x'}, markReadStatus);
      final body = jsonDecode(request.body) as Map<String, Object?>;
      final ids = (body['ids'] as List?)?.cast<String>() ?? const [];
      final rows = [
        for (final n in (inbox['notifications'] as List).cast<Map>())
          {
            ...n,
            if (body['all'] == true || ids.contains(n['id'])) 'read': true,
          },
      ];
      inbox = {
        'notifications': rows,
        'unread': rows.where((n) => n['read'] != true).length,
      };
      return http.Response('', 204);
    }
    if (path == '/api/v1/me/deletion' && request.method == 'GET') {
      return deletionStatusCode == 200
          ? json(deletion)
          : json({'detail': 'x'}, deletionStatusCode);
    }
    if (path == '/api/v1/me/deletion' && request.method == 'POST') {
      deletions++;
      final (status, body) =
          deletionAnswer ??
          (
            200,
            {'available': true, 'state': 'completed', 'requested_at': null},
          );
      return json(body, status);
    }
    if (path == '/api/v1/passes/checkout') {
      checkouts.add(jsonDecode(request.body) as Map<String, Object?>);
      if (checkoutStatus != 201) return json({'detail': 'x'}, checkoutStatus);
      return json({'payment_id': 'pay-1', 'redirect_url': paymentPage}, 201);
    }
    if (path == '/api/v1/passes/payments/pay-1') {
      final state =
          paymentStates[paymentChecks.clamp(0, paymentStates.length - 1)];
      paymentChecks++;
      final done = state == 'completed';
      if (done) {
        // The pass now lets the viewer watch.
        grantStatus = 200;
        myPass = {
          'active': true,
          'current_ends_at': passEndsAt.toIso8601String(),
          'ends_at': passEndsAt.toIso8601String(),
          'checking': false,
        };
      }
      return json({
        'id': 'pay-1',
        'plan_id': 'velora_start',
        'plan_name': 'Velora Start',
        'amount_ugx': 6000,
        'state': state,
        'pass_ends_at': done ? passEndsAt.toIso8601String() : null,
      });
    }
    if (path.endsWith('/playback')) {
      grants++;
      granted.add(request.url.pathSegments[3]);
      grantDevices.add(request.headers['X-Velora-Device']);
      if (grantRefusal case final refusal?) {
        return json(refusal, grantStatus);
      }
      if (grantStatus != 200) return json({}, grantStatus);
      return json({
        'playlist_url': '$gateway/v1/grant-$grants.sig/master.m3u8',
        'expires_at': expiresAt.toIso8601String(),
        if (sessions) 'session_id': 'session-$grants',
        if (sessions) 'heartbeat_seconds': 60,
      });
    }
    if (catalogueStatus case final status?) {
      return json({'detail': 'x'}, status);
    }
    if (path == '/api/v1/featured') {
      return featuredStatus == 200
          ? json(featured)
          : json({'detail': 'x'}, featuredStatus);
    }
    if (path == '/api/v1/editions') return _list(request.url.queryParameters);
    if (path.startsWith('/api/v1/editions/') && path.endsWith('/rails')) {
      if (railsStatus != 200) return json({'detail': 'x'}, railsStatus);
      final found = rails[request.url.pathSegments[3]] ?? const {};
      return json({
        'rails': [
          for (final MapEntry(:key, :value) in found.entries)
            {'key': key, 'editions': value},
        ],
      });
    }
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
    if (path == '/api/v1/genres') return json(genres);
    if (path == '/api/v1/categories') {
      return categoriesStatus == 200
          ? json(categories)
          : json({'detail': 'Busy'}, categoriesStatus);
    }
    return json({}, 404);
  }

  http.Response _list(Map<String, String> query) {
    final q = query['q']?.toLowerCase();
    final matching = [
      for (final e in editions)
        if ((query['kind'] == null || e['kind'] == query['kind']) &&
            (query['vj'] == null || e['vj_slug'] == query['vj']) &&
            (query['language'] == null || e['language'] == query['language']) &&
            (query['genre'] == null ||
                ((e['genres'] as List?) ?? const []).contains(
                  query['genre'],
                )) &&
            (query['category'] == null ||
                ((e['categories'] as List?) ?? const []).contains(
                  query['category'],
                )) &&
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

  /// This test's device credential, kept between screens.
  final deviceStore = MemoryDeviceStore();

  PlaybackApi playback(AuthController auth) => PlaybackApi(
    baseUrl: Uri.parse(apiBase),
    mediaBaseUrl: Uri.parse(gateway),
    httpClient: client,
    accessToken: auth.accessToken,
    deviceStore: deviceStore,
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
  Downloads? downloads,

  /// False when something keeps moving, such as Home's hero: the app is
  /// pumped for a second instead of until it settles.
  bool settle = true,
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
      downloads: downloads,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
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

/// One plan as GET /api/v1/passes/plans answers it.
Map<String, Object?> plan(
  String id,
  String name,
  int price,
  int days,
  int devices, {
  bool featured = false,
}) => {
  'id': id,
  'display_name': name,
  'description': null,
  'price_ugx': price,
  'days': days,
  'max_devices': devices,
  'max_streams': devices,
  'featured': featured,
};

const deviceId = '3c9e0d4f-1b2a-4c5d-8e6f-7a8b9c0d1e2f';
const deviceCredential =
    '$deviceId.AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
