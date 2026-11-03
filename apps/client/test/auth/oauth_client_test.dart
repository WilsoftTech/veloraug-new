import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/auth/oauth_client.dart';
import 'package:veloraug/auth/oauth_config.dart';
import 'package:veloraug/auth/pkce.dart';

const _issuer = 'https://auth.example.test/neondb/auth';
const _callback = 'https://pages.example.test/auth/callback/android';
const _secretCode = 'SECRET-CODE-VALUE';

final _config = OAuthConfig(
  issuer: _issuer,
  clientId: 'client-1',
  resource: 'https://api.example.test',
  redirectUri: Uri.parse(_callback),
  signOutPage: Uri.parse('https://pages.example.test/sign-out'),
);

String _jwt(Map<String, dynamic> payload) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'EdDSA', 'kid': 'k1'})}.${part(payload)}.signature';
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

class _Server {
  final List<http.Request> tokenRequests = [];
  final List<http.Request> revokeRequests = [];
  Map<String, dynamic> metadata = {
    'issuer': _issuer,
    'authorization_endpoint': '$_issuer/oauth2/authorize',
    'token_endpoint': '$_issuer/oauth2/token',
    'revocation_endpoint': '$_issuer/oauth2/revoke',
  };
  http.Response Function(http.Request)? onToken;
  String? idTokenNonce;

  late final MockClient client = MockClient((request) async {
    if (request.url.path.endsWith('/.well-known/oauth-authorization-server')) {
      return _json(metadata);
    }
    if (request.url.path.endsWith('/oauth2/token')) {
      tokenRequests.add(request);
      if (onToken != null) return onToken!(request);
      return _json({
        'access_token': 'access-1',
        'refresh_token': 'refresh-1',
        'expires_in': 3600,
        if (idTokenNonce != null) 'id_token': _jwt({'nonce': idTokenNonce}),
      });
    }
    if (request.url.path.endsWith('/oauth2/revoke')) {
      revokeRequests.add(request);
      return http.Response('', 200);
    }
    return http.Response('', 404);
  });
}

/// A browser step that answers using the request's state and nonce.
BrowserStep _approve(
  _Server server, {
  String Function(Map<String, String> query)? result,
  void Function(Uri url)? onUrl,
}) {
  return (url, redirectUri) async {
    onUrl?.call(url);
    final query = url.queryParameters;
    server.idTokenNonce ??= query['nonce'];
    return result?.call(query) ??
        '$_callback?code=$_secretCode&state=${query['state']}';
  };
}

OAuthClient _client(_Server server, BrowserStep step) =>
    OAuthClient(config: _config, httpClient: server.client, browserStep: step);

void main() {
  group('signIn', () {
    test('sends PKCE S256, state, nonce and resource, and no secret', () async {
      final server = _Server();
      late Uri authorizeUrl;
      await _client(
        server,
        _approve(server, onUrl: (url) => authorizeUrl = url),
      ).signIn();

      final query = authorizeUrl.queryParameters;
      expect(query['response_type'], 'code');
      expect(query['client_id'], 'client-1');
      expect(query['redirect_uri'], _callback);
      expect(query['code_challenge_method'], 'S256');
      expect(query['resource'], 'https://api.example.test');
      expect(query['scope'], contains('offline_access'));
      expect(query['state'], isNotEmpty);
      expect(query['nonce'], isNotEmpty);

      final form = server.tokenRequests.single.bodyFields;
      expect(form['grant_type'], 'authorization_code');
      expect(form['code'], _secretCode);
      expect(form['redirect_uri'], _callback);
      expect(form['client_id'], 'client-1');
      expect(form['resource'], 'https://api.example.test');
      expect(
        pkceS256Challenge(form['code_verifier']!),
        query['code_challenge'],
      );
      expect(form.containsKey('client_secret'), isFalse);
      expect(
        server.tokenRequests.single.headers.containsKey('Authorization'),
        isFalse,
      );
    });

    test('returns the tokens, and records a matching nonce', () async {
      final server = _Server();
      final tokens = await _client(server, _approve(server)).signIn();
      expect(tokens.accessToken, 'access-1');
      expect(tokens.refreshToken, 'refresh-1');
      expect(tokens.idTokenNonceMatched, isTrue);
    });

    test('refuses an ID token with the wrong nonce', () async {
      final server = _Server()..idTokenNonce = 'another-nonce';
      await expectLater(
        _client(server, _approve(server)).signIn(),
        throwsA(isA<OAuthException>()),
      );
    });

    test('refuses a changed state, without exchanging the code', () async {
      final server = _Server();
      await expectLater(
        _client(
          server,
          _approve(
            server,
            result: (_) => '$_callback?code=$_secretCode&state=forged',
          ),
        ).signIn(),
        throwsA(
          isA<OAuthException>().having(
            (e) => e.message,
            'message',
            contains('state'),
          ),
        ),
      );
      expect(server.tokenRequests, isEmpty);
    });

    test('refuses a callback with a different path or host', () async {
      for (final wrong in [
        'https://pages.example.test/other',
        'https://evil.example.test/auth/callback/android',
      ]) {
        final server = _Server();
        await expectLater(
          _client(
            server,
            _approve(
              server,
              result: (query) =>
                  '$wrong?code=$_secretCode&state=${query['state']}',
            ),
          ).signIn(),
          throwsA(isA<OAuthException>()),
        );
        expect(server.tokenRequests, isEmpty);
      }
    });

    test('refuses a callback naming another issuer', () async {
      final server = _Server();
      await expectLater(
        _client(
          server,
          _approve(
            server,
            result: (query) =>
                '$_callback?code=$_secretCode&state=${query['state']}'
                '&iss=https%3A%2F%2Fother.example.test',
          ),
        ).signIn(),
        throwsA(isA<OAuthException>()),
      );
      expect(server.tokenRequests, isEmpty);
    });

    test('reports a denied consent', () async {
      final server = _Server();
      await expectLater(
        _client(
          server,
          _approve(
            server,
            result: (query) =>
                '$_callback?error=access_denied&state=${query['state']}',
          ),
        ).signIn(),
        throwsA(
          isA<OAuthException>().having(
            (e) => e.message,
            'message',
            contains('access_denied'),
          ),
        ),
      );
    });

    test('refuses discovery that names another issuer', () async {
      final server = _Server()..metadata['issuer'] = 'https://other.test';
      await expectLater(
        _client(server, _approve(server)).signIn(),
        throwsA(isA<OAuthException>()),
      );
    });

    test('a refused exchange never repeats the code or the reply', () async {
      final server = _Server()
        ..onToken = (_) => _json({
          'error': 'invalid_grant',
          'error_description': 'bad code $_secretCode',
        }, 400);
      try {
        await _client(server, _approve(server)).signIn();
        fail('should have thrown');
      } on OAuthException catch (error) {
        expect(error.message, contains('invalid_grant'));
        expect(error.toString(), isNot(contains(_secretCode)));
      }
    });
  });

  group('refresh', () {
    test('sends only the refresh grant, and no secret', () async {
      final server = _Server();
      await _client(server, _approve(server)).refresh('refresh-1');
      final form = server.tokenRequests.single.bodyFields;
      expect(form['grant_type'], 'refresh_token');
      expect(form['refresh_token'], 'refresh-1');
      expect(form['client_id'], 'client-1');
      expect(form.containsKey('client_secret'), isFalse);
    });

    test('calls made at the same time share one request', () async {
      final server = _Server();
      final client = _client(server, _approve(server));
      final results = await Future.wait([
        client.refresh('refresh-1'),
        client.refresh('refresh-1'),
        client.refresh('refresh-1'),
      ]);
      expect(server.tokenRequests, hasLength(1));
      expect(results.map((r) => r.accessToken).toSet(), {'access-1'});
    });

    test('a later call after a failure makes a new request', () async {
      final server = _Server()
        ..onToken = (_) => _json({'error': 'invalid_grant'}, 400);
      final client = _client(server, _approve(server));
      await expectLater(
        client.refresh('refresh-1'),
        throwsA(isA<OAuthException>()),
      );
      await expectLater(
        client.refresh('refresh-1'),
        throwsA(isA<OAuthException>()),
      );
      expect(server.tokenRequests, hasLength(2));
    });
  });

  test('revoke identifies the client, with no secret', () async {
    final server = _Server();
    expect(await _client(server, _approve(server)).revoke('refresh-1'), 200);
    final form = server.revokeRequests.single.bodyFields;
    expect(form['token'], 'refresh-1');
    expect(form['client_id'], 'client-1');
    expect(form.containsKey('client_secret'), isFalse);
  });

  group('describeAccessToken', () {
    test('leaves out the token and the subject', () {
      const subject = '6ca2a1f2-59a5-4a15-b3c8-96f5ad5de7f4';
      final token = _jwt({
        'sub': subject,
        'iss': _issuer,
        'aud': 'https://api.example.test',
        'iat': 1000,
        'exp': 4600,
      });
      final text = describeAccessToken(token).join('\n');
      expect(text, contains('sub is a UUID: true'));
      expect(text, contains('lifetime: 3600 seconds'));
      expect(text, isNot(contains(subject)));
      expect(text, isNot(contains(token)));
    });

    test('recognises an opaque token', () {
      expect(describeAccessToken('opaque').single, contains('opaque'));
    });
  });
}
