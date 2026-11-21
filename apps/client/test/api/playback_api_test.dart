import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/api/playback_api.dart';
import 'package:veloraug/auth/oauth_client.dart';
import 'package:veloraug/l10n/app_localizations_en.dart';

const _playlist = 'http://127.0.0.1:8787/v1/payload.signature/master.m3u8';

PlaybackApi _api(
  http.Response Function(http.Request request) answer, {
  Future<String?> Function()? token,
}) => PlaybackApi(
  baseUrl: Uri.parse('http://127.0.0.1:8000'),
  mediaBaseUrl: Uri.parse('http://127.0.0.1:8787'),
  httpClient: MockClient((request) async => answer(request)),
  accessToken: token ?? () async => 'ACCESS-SECRET',
);

http.Response _grant({String url = _playlist}) => http.Response(
  jsonEncode({'playlist_url': url, 'expires_at': '2026-11-12T22:00:00Z'}),
  200,
);

Future<PlaybackFailure> _failure(PlaybackApi api) async {
  try {
    await api.grant('item-1');
  } on PlaybackException catch (error) {
    return error.failure;
  }
  fail('no failure');
}

void main() {
  test('asks for a grant with the token, and reads the answer', () async {
    late http.Request sent;
    final grant = await _api((request) {
      sent = request;
      return _grant();
    }).grant('item 1');

    expect(sent.method, 'POST');
    expect(
      sent.url.toString(),
      'http://127.0.0.1:8000/api/v1/items/item%201/playback',
    );
    expect(sent.headers['Authorization'], 'Bearer ACCESS-SECRET');
    expect(grant.playlistUrl.toString(), _playlist);
    expect(grant.expiresAt, DateTime.utc(2026, 11, 12, 22));
  });

  test("an admin's preview asks the admin route", () async {
    late http.Request sent;
    await _api((request) {
      sent = request;
      return _grant();
    }).grant('item-1', preview: true);

    expect(
      sent.url.toString(),
      'http://127.0.0.1:8000/api/v1/admin/items/item-1/preview',
    );
  });

  test('signed out, nothing is sent', () async {
    var sent = false;
    final api = _api((_) {
      sent = true;
      return _grant();
    }, token: () async => null);

    expect(await _failure(api), PlaybackFailure.signedOut);
    expect(sent, isFalse);
  });

  test('a token that needs the network to renew is unreachable', () async {
    final api = _api(
      (_) => _grant(),
      token: () async =>
          throw const OAuthException('offline', OAuthFailure.network),
    );
    expect(await _failure(api), PlaybackFailure.unreachable);
  });

  for (final (status, failure) in [
    (401, PlaybackFailure.refused),
    (403, PlaybackFailure.notAdmin),
    (404, PlaybackFailure.notFound),
    (409, PlaybackFailure.notReady),
    (503, PlaybackFailure.busy),
    (500, PlaybackFailure.unexpected),
  ]) {
    test('$status is ${failure.name}', () async {
      expect(await _failure(_api((_) => http.Response('{}', status))), failure);
    });
  }

  test('no answer is unreachable', () async {
    final api = _api((_) => throw http.ClientException('refused'));
    expect(await _failure(api), PlaybackFailure.unreachable);
  });

  for (final url in [
    'https://evil.example/v1/payload.signature/master.m3u8',
    'http://127.0.0.1:9999/v1/payload.signature/master.m3u8',
    'https://127.0.0.1:8787/v1/payload.signature/master.m3u8',
    'http://127.0.0.1:8787/other/master.m3u8',
    'http://127.0.0.1:8787/v1/payload.signature/master.m3u8?x=1',
    'http://user@127.0.0.1:8787/v1/payload.signature/master.m3u8',
    'not a url at all',
  ]) {
    test('an address off the media gateway is refused: $url', () async {
      expect(
        await _failure(_api((_) => _grant(url: url))),
        PlaybackFailure.unexpected,
      );
    });
  }

  test('a malformed answer is unexpected', () async {
    for (final body in ['[]', 'not json', '{"playlist_url": "$_playlist"}']) {
      expect(
        await _failure(_api((_) => http.Response(body, 200))),
        PlaybackFailure.unexpected,
      );
    }
  });

  test('messages never repeat a token', () {
    for (final failure in PlaybackFailure.values) {
      final message = playbackFailureMessage(AppLocalizationsEn(), failure);
      expect(message, isNot(contains('SECRET')));
      expect(message, isNotEmpty);
    }
  });

  group('Milestone 10', () {
    http.Response refusal(int status, Map<String, Object?> detail) =>
        http.Response(jsonEncode({'detail': detail}), status);

    for (final (status, code, failure) in [
      (409, 'device_limit', PlaybackFailure.deviceLimit),
      (409, 'stream_limit', PlaybackFailure.streamLimit),
      (429, 'device_switch_limit', PlaybackFailure.deviceSwitchLimit),
      (429, null, PlaybackFailure.tooMany),
    ]) {
      test('$status $code is ${failure.name}', () async {
        final api = _api(
          (_) => refusal(status, {'code': ?code, 'message': 'x'}),
        );
        expect(await _failure(api), failure);
      });
    }

    test('a stream limit says what is playing elsewhere', () async {
      final api = _api(
        (_) => refusal(409, {
          'code': 'stream_limit',
          'limit': 2,
          'sessions': [
            {
              'id': 's1',
              'device_label': 'TV',
              'started_at': '2026-11-20T10:00:00Z',
            },
          ],
        }),
      );
      try {
        await api.grant('item-1');
        fail('no failure');
      } on PlaybackException catch (error) {
        expect(error.limit, 2);
        expect(error.sessions.single.deviceLabel, 'TV');
      }
    });

    test('a session grant carries its session and heartbeat', () async {
      final api = _api(
        (_) => http.Response(
          jsonEncode({
            'playlist_url': _playlist,
            'expires_at': '2026-11-12T22:00:00Z',
            'session_id': 'session-1',
            'heartbeat_seconds': 60,
          }),
          200,
        ),
      );
      final grant = await api.grant('item-1');
      expect(grant.sessionId, 'session-1');
      expect(grant.heartbeat, const Duration(seconds: 60));
    });

    test('a malformed device credential is never stored or sent', () async {
      final sent = <String?>[];
      final api = _api((request) {
        sent.add(request.headers['X-Velora-Device']);
        if (request.url.path == '/api/v1/me/devices') {
          return http.Response(jsonEncode({'credential': 'evil'}), 201);
        }
        return refusal(403, {'code': 'device_required'});
      });
      expect(await _failure(api), PlaybackFailure.unexpected);
      expect(await api.deviceStore.read(), isNull);
      expect(sent, everyElement(isNull));
    });

    for (final (status, result) in [
      (200, HeartbeatResult.live),
      (402, HeartbeatResult.passEnded),
      (403, HeartbeatResult.deviceRemoved),
      (410, HeartbeatResult.ended),
      (503, HeartbeatResult.unknown),
    ]) {
      test('a heartbeat answered $status is ${result.name}', () async {
        final api = _api((_) => http.Response('{}', status));
        expect(await api.heartbeat('s1'), result);
      });
    }

    test('a heartbeat with no answer is unknown, never an error', () async {
      final api = _api((_) => throw http.ClientException('offline'));
      expect(await api.heartbeat('s1'), HeartbeatResult.unknown);
    });
  });
}
