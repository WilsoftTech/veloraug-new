import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/api/profile_api.dart';
import 'package:veloraug/auth/oauth_client.dart';

const _user = '5f0c2b1e-8a4d-4c1e-9b2f-3d6a7e8f9a0b';

ProfileApi _api(
  MockClient client, {
  Future<String?> Function()? token,
  Duration timeout = const Duration(seconds: 15),
}) => ProfileApi(
  baseUrl: Uri.parse('http://127.0.0.1:8000'),
  httpClient: client,
  accessToken: token ?? () async => 'ACCESS-SECRET',
  timeout: timeout,
);

http.Response _profile(String? name) =>
    http.Response(jsonEncode({'user_id': _user, 'display_name': name}), 200);

void main() {
  test('fetch sends the token as a Bearer header to /api/v1/me', () async {
    late http.Request seen;
    final api = _api(
      MockClient((request) async {
        seen = request;
        return _profile('Amara');
      }),
    );

    final profile = await api.fetch();

    expect(seen.method, 'GET');
    expect(seen.url.toString(), 'http://127.0.0.1:8000/api/v1/me');
    expect(seen.headers['Authorization'], 'Bearer ACCESS-SECRET');
    expect(profile.userId, _user);
    expect(profile.displayName, 'Amara');
  });

  test('updateDisplayName sends PATCH with JSON, and null clears', () async {
    final bodies = <Object?>[];
    final api = _api(
      MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.headers['Content-Type'], startsWith('application/json'));
        final body = jsonDecode(request.body) as Map<String, Object?>;
        bodies.add(body['display_name']);
        return _profile(body['display_name'] as String?);
      }),
    );

    expect((await api.updateDisplayName('Amara')).displayName, 'Amara');
    expect((await api.updateDisplayName(null)).displayName, isNull);
    expect(bodies, ['Amara', null]);
  });

  test('signed out, nothing is sent', () async {
    var sent = 0;
    final api = _api(
      MockClient((_) async {
        sent++;
        return _profile(null);
      }),
      token: () async => null,
    );

    await expectLater(
      api.fetch(),
      throwsA(
        isA<ProfileException>().having(
          (e) => e.failure,
          'failure',
          ProfileFailure.signedOut,
        ),
      ),
    );
    expect(sent, 0);
  });

  final statuses = {
    401: ProfileFailure.refused,
    422: ProfileFailure.invalidName,
    503: ProfileFailure.busy,
    500: ProfileFailure.unexpected,
  };
  for (final MapEntry(key: status, value: failure) in statuses.entries) {
    test('HTTP $status is ${failure.name}', () async {
      final api = _api(MockClient((_) async => http.Response('{}', status)));

      await expectLater(
        api.fetch(),
        throwsA(
          isA<ProfileException>().having((e) => e.failure, 'failure', failure),
        ),
      );
    });
  }

  test('no network, a timeout, or a failed renewal is unreachable', () async {
    Matcher unreachable = throwsA(
      isA<ProfileException>().having(
        (e) => e.failure,
        'failure',
        ProfileFailure.unreachable,
      ),
    );
    await expectLater(
      _api(MockClient((_) async => throw http.ClientException('down'))).fetch(),
      unreachable,
    );
    await expectLater(
      _api(
        MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 10),
      ).fetch(),
      unreachable,
    );
    await expectLater(
      _api(
        MockClient((_) async => _profile(null)),
        token: () async =>
            throw const OAuthException('offline', OAuthFailure.network),
      ).fetch(),
      unreachable,
    );
  });

  test('a reply that is not a profile is unexpected', () async {
    for (final body in ['not json', '[]', '{"user_id": 1}']) {
      final api = _api(MockClient((_) async => http.Response(body, 200)));
      await expectLater(api.fetch(), throwsA(isA<ProfileException>()));
    }
  });

  test('statusFor sends exactly the given header, or none', () async {
    final headers = <String?>[];
    final api = _api(
      MockClient((request) async {
        headers.add(request.headers['Authorization']);
        return http.Response('{"detail":"Not signed in."}', 401);
      }),
    );

    expect(await api.statusFor(), 401);
    expect(await api.statusFor(authorization: 'Bearer changed'), 401);
    expect(headers, [null, 'Bearer changed']);
  });

  test('failure messages never quote a token', () {
    for (final failure in ProfileFailure.values) {
      expect(profileFailureMessage(failure), isNot(contains('SECRET')));
      expect(profileFailureMessage(failure), isNotEmpty);
    }
  });
}
