import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/api/catalogue_api.dart';
import 'package:veloraug/api/playback_api.dart';
import 'package:veloraug/app.dart';
import 'package:veloraug/auth/auth_controller.dart';
import 'package:veloraug/auth/oauth_client.dart';
import 'package:veloraug/auth/oauth_config.dart';
import 'package:veloraug/auth/token_store.dart';
import 'package:veloraug/player/video_view.dart';
import 'package:veloraug/screens/movie_detail_screen.dart';
import 'package:veloraug/screens/player_screen.dart';
import 'package:veloraug/widgets/velora_button.dart';

const _gateway = 'http://127.0.0.1:8787';

AuthController _auth({required bool signedIn}) => AuthController(
  client: OAuthClient(
    config: OAuthConfig(
      issuer: 'https://auth.example.test/neondb/auth',
      clientId: 'client-1',
      resource: 'https://api.example.test',
      redirectUri: Uri.parse('https://pages.example.test/auth/callback'),
      signOutPage: Uri.parse('https://pages.example.test/sign-out'),
    ),
    httpClient: MockClient((_) async => http.Response('', 500)),
    browserStep: (_, _) async => throw UnimplementedError(),
  ),
  store: MemoryTokenStore(
    signedIn
        ? StoredSession(
            accessToken: 'ACCESS-SECRET',
            refreshToken: 'REFRESH-SECRET',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          )
        : null,
  ),
);

/// The API, answering a movie's details and grants.
class _Api {
  bool playable = true;
  int grants = 0;
  int grantStatus = 200;
  DateTime expiresAt = DateTime.utc(2030);

  late final _client = MockClient((request) async {
    if (request.url.path.endsWith('/playback')) {
      grants++;
      if (grantStatus != 200) return http.Response('{}', grantStatus);
      return http.Response(
        jsonEncode({
          'playlist_url': '$_gateway/v1/grant-$grants.sig/master.m3u8',
          'expires_at': expiresAt.toIso8601String(),
        }),
        200,
      );
    }
    return http.Response(
      jsonEncode({
        'id': 'movie-1',
        'title': 'The Matrix',
        'year': 1999,
        'genres': <String>[],
        'playable': playable,
      }),
      200,
    );
  });

  CatalogueApi catalogue() => CatalogueApi(
    baseUrl: Uri.parse('http://127.0.0.1:8000'),
    httpClient: _client,
  );

  PlaybackApi playback(AuthController auth) => PlaybackApi(
    baseUrl: Uri.parse('http://127.0.0.1:8000'),
    mediaBaseUrl: Uri.parse(_gateway),
    httpClient: _client,
    accessToken: auth.accessToken,
  );
}

/// Stands in for the video: records what it was asked to play.
class _Views {
  final requests = <VideoViewRequest>[];

  Widget build(BuildContext context, VideoViewRequest request) {
    requests.add(request);
    return Text('playing ${request.url.pathSegments[1]}');
  }
}

Future<void> _openDetail(
  WidgetTester tester,
  _Api api,
  AuthController auth,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1600);
  addTearDown(tester.view.reset);
  await auth.restore();
  await tester.pumpWidget(
    VeloraApp(
      authController: auth,
      catalogueApi: api.catalogue(),
      playbackApi: api.playback(auth),
    ),
  );
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(Scaffold).first);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          const MovieDetailScreen(movieId: 'movie-1', title: 'The Matrix'),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpPlayer(
  WidgetTester tester,
  _Api api,
  _Views views, {
  DateTime Function()? clock,
}) async {
  final auth = _auth(signedIn: true);
  await auth.restore();
  await tester.pumpWidget(
    PlaybackScope(
      api: api.playback(auth),
      child: MaterialApp(
        home: PlayerScreen(
          movieId: 'movie-1',
          title: 'The Matrix',
          viewBuilder: views.build,
          clock: clock ?? () => DateTime.utc(2026),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

VeloraButton _button(WidgetTester tester, String label) =>
    tester.widget<VeloraButton>(find.widgetWithText(VeloraButton, label));

void main() {
  group('Watch on a movie', () {
    testWidgets('signed in, it opens the player with a grant', (tester) async {
      final api = _Api();
      final auth = _auth(signedIn: true);
      await _openDetail(tester, api, auth);

      expect(find.text('Coming soon'), findsNothing);
      expect(_button(tester, 'Watch').onPressed, isNotNull);
      await tester.tap(find.text('Watch'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(api.grants, 1);
    });

    testWidgets('signed out, it asks the viewer to sign in', (tester) async {
      final api = _Api();
      await _openDetail(tester, api, _auth(signedIn: false));

      expect(find.text('Watch'), findsNothing);
      expect(_button(tester, 'Sign in to watch').onPressed, isNotNull);
      expect(api.grants, 0);
    });

    testWidgets('with nothing ready, it is Coming soon', (tester) async {
      final api = _Api()..playable = false;
      await _openDetail(tester, api, _auth(signedIn: true));

      expect(find.text('Coming soon'), findsOneWidget);
      expect(_button(tester, 'Watch').onPressed, isNull);
    });
  });

  group('the player', () {
    testWidgets('plays the granted playlist from the start', (tester) async {
      final api = _Api();
      final views = _Views();
      await _pumpPlayer(tester, api, views);

      expect(find.text('playing grant-1.sig'), findsOneWidget);
      expect(
        views.requests.last.url.toString(),
        '$_gateway/v1/grant-1.sig/master.m3u8',
      );
      expect(views.requests.last.startAt, Duration.zero);
    });

    testWidgets('a grant that ran out is renewed, from the same moment', (
      tester,
    ) async {
      final api = _Api()..expiresAt = DateTime.utc(2026, 1, 1, 6);
      final views = _Views();
      var now = DateTime.utc(2026, 1, 1, 1);
      await _pumpPlayer(tester, api, views, clock: () => now);

      now = DateTime.utc(2026, 1, 1, 6, 0, 5);
      views.requests.last.onFailed(const Duration(minutes: 97));
      await tester.pumpAndSettle();

      expect(api.grants, 2);
      expect(find.text('playing grant-2.sig'), findsOneWidget);
      expect(views.requests.last.startAt, const Duration(minutes: 97));
    });

    testWidgets('a renewed grant that fails again stops, without looping', (
      tester,
    ) async {
      final api = _Api()..expiresAt = DateTime.utc(2026, 1, 1, 6);
      final views = _Views();
      final now = DateTime.utc(2026, 1, 1, 7);
      await _pumpPlayer(tester, api, views, clock: () => now);

      views.requests.last.onFailed(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      views.requests.last.onFailed(const Duration(minutes: 1));
      await tester.pumpAndSettle();

      expect(api.grants, 2);
      expect(find.text("Couldn't play this movie"), findsOneWidget);
    });

    testWidgets('any other stop offers Try again, from the same moment', (
      tester,
    ) async {
      final api = _Api();
      final views = _Views();
      await _pumpPlayer(tester, api, views);

      views.requests.last.onFailed(const Duration(seconds: 42));
      await tester.pumpAndSettle();
      expect(find.textContaining('Playback stopped'), findsOneWidget);
      expect(api.grants, 1);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(api.grants, 2);
      expect(views.requests.last.startAt, const Duration(seconds: 42));
    });

    for (final (status, words) in [
      (409, "can't be watched yet"),
      (404, "isn't available"),
      (401, "didn't accept your sign-in"),
      (503, 'busy'),
    ]) {
      testWidgets('a $status grant says so', (tester) async {
        final api = _Api()..grantStatus = status;
        final views = _Views();
        await _pumpPlayer(tester, api, views);

        expect(find.textContaining(words), findsOneWidget);
        expect(views.requests, isEmpty);
      });
    }
  });
}
