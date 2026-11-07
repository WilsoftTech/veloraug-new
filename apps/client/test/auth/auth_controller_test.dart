import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/auth/auth_controller.dart';
import 'package:veloraug/auth/auth_messages.dart';
import 'package:veloraug/auth/oauth_client.dart';
import 'package:veloraug/auth/oauth_config.dart';
import 'package:veloraug/auth/token_store.dart';

const _issuer = 'https://auth.example.test/neondb/auth';
const _callback = 'https://pages.example.test/auth/callback/android';
const _signOutPage = 'https://pages.example.test/sign-out';

final _config = OAuthConfig(
  issuer: _issuer,
  clientId: 'client-1',
  resource: 'https://api.example.test',
  redirectUri: Uri.parse(_callback),
  signOutPage: Uri.parse(_signOutPage),
);

String _jwt(Map<String, dynamic> payload) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'EdDSA'})}.${part(payload)}.signature';
}

/// A fake Neon Auth server and browser.
class _Neon {
  final List<Map<String, String>> tokenRequests = [];
  final List<Map<String, String>> revokeRequests = [];
  final List<Uri> browserUrls = [];

  bool offline = false;
  bool refuseRefresh = false;
  Completer<void>? holdRefresh;
  int _issued = 0;
  String? _nonce;

  /// What the browser does with a sign-in request. By default it approves.
  Future<String> Function(Uri url)? onSignInPage;

  late final http.Client http_ = MockClient((request) async {
    if (offline) throw http.ClientException('no network');
    final path = request.url.path;
    if (path.endsWith('/.well-known/oauth-authorization-server')) {
      return http.Response(
        jsonEncode({
          'issuer': _issuer,
          'authorization_endpoint': '$_issuer/oauth2/authorize',
          'token_endpoint': '$_issuer/oauth2/token',
          'revocation_endpoint': '$_issuer/oauth2/revoke',
        }),
        200,
      );
    }
    if (path.endsWith('/oauth2/token')) {
      final form = request.bodyFields;
      tokenRequests.add(form);
      if (form['grant_type'] == 'refresh_token') {
        await holdRefresh?.future;
        if (refuseRefresh) {
          return http.Response(jsonEncode({'error': 'invalid_grant'}), 400);
        }
      }
      _issued++;
      return http.Response(
        jsonEncode({
          'access_token': 'ACCESS-$_issued',
          'refresh_token': 'REFRESH-$_issued',
          'expires_in': 3600,
          if (form['grant_type'] == 'authorization_code')
            'id_token': _jwt({'nonce': _nonce, 'email': 'person@example.test'}),
        }),
        200,
      );
    }
    if (path.endsWith('/oauth2/revoke')) {
      revokeRequests.add(request.bodyFields);
      return http.Response('', 200);
    }
    return http.Response('', 404);
  });

  Future<String> browser(Uri url, Uri redirectUri) async {
    browserUrls.add(url);
    if (url.toString().startsWith(_signOutPage)) {
      return '$_callback?signed_out=1';
    }
    final custom = onSignInPage;
    if (custom != null) return custom(url);
    _nonce = url.queryParameters['nonce'];
    return '$_callback?code=CODE-SECRET&state=${url.queryParameters['state']}';
  }

  OAuthClient get client =>
      OAuthClient(config: _config, httpClient: http_, browserStep: browser);
}

class _Clock {
  DateTime now = DateTime.utc(2026, 11, 7, 12);
  DateTime call() => now;
}

StoredSession _session({required DateTime expiresAt}) => StoredSession(
  accessToken: 'ACCESS-OLD',
  refreshToken: 'REFRESH-OLD',
  expiresAt: expiresAt,
  email: 'person@example.test',
);

void main() {
  late _Neon neon;
  late _Clock clock;
  late MemoryTokenStore store;
  late List<String> logged;
  late DebugPrintCallback previousPrint;

  AuthController controller() =>
      AuthController(client: neon.client, store: store, clock: clock.call);

  setUp(() {
    neon = _Neon();
    clock = _Clock();
    store = MemoryTokenStore();
    logged = [];
    previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add('$message');
  });

  tearDown(() {
    debugPrint = previousPrint;
    // No token, refresh token or code ever reaches the log.
    final log = logged.join('\n');
    for (final secret in ['ACCESS-', 'REFRESH-', 'CODE-SECRET']) {
      expect(log, isNot(contains(secret)));
    }
  });

  group('restore', () {
    test('with nothing saved, is signed out', () async {
      final auth = controller();
      await auth.restore();
      expect(auth.status, AuthStatus.signedOut);
      expect(auth.notice, isNull);
    });

    test('with a current session, is signed in without a request', () async {
      store.session = _session(expiresAt: clock.now.add(Duration(hours: 1)));
      final auth = controller();
      await auth.restore();
      expect(auth.status, AuthStatus.signedIn);
      expect(auth.email, 'person@example.test');
      expect(neon.tokenRequests, isEmpty);
    });

    test('with an expired session, renews it', () async {
      store.session = _session(expiresAt: clock.now);
      final auth = controller();
      await auth.restore();
      expect(auth.status, AuthStatus.signedIn);
      expect(neon.tokenRequests.single['refresh_token'], 'REFRESH-OLD');
      expect(store.session!.refreshToken, 'REFRESH-1');
    });

    test('with an expired session that Neon refuses, is signed out', () async {
      store.session = _session(expiresAt: clock.now);
      neon.refuseRefresh = true;
      final auth = controller();
      await auth.restore();
      expect(auth.status, AuthStatus.signedOut);
      expect(auth.notice, sessionEndedMessage);
      expect(store.session, isNull);
    });

    test('with an expired session and no network, stays signed in', () async {
      store.session = _session(expiresAt: clock.now);
      neon.offline = true;
      final auth = controller();
      await auth.restore();
      expect(auth.status, AuthStatus.signedIn);
      expect(store.session, isNotNull);
    });
  });

  group('signIn', () {
    test('saves the session and shows the email', () async {
      final auth = controller();
      await auth.restore();
      await auth.signIn();
      expect(auth.status, AuthStatus.signedIn);
      expect(auth.email, 'person@example.test');
      expect(store.session!.accessToken, 'ACCESS-1');
      expect(store.session!.refreshToken, 'REFRESH-1');
      expect(await auth.accessToken(), 'ACCESS-1');
    });

    Future<AuthController> failWith(
      Future<String> Function(Uri url) page,
    ) async {
      neon.onSignInPage = page;
      final auth = controller();
      await auth.restore();
      await auth.signIn();
      expect(auth.status, AuthStatus.signedOut);
      expect(auth.noticeIsError, isTrue);
      expect(store.session, isNull);
      expect(neon.tokenRequests, isEmpty);
      return auth;
    }

    test('a changed state leaves the person signed out', () async {
      final auth = await failWith(
        (_) async => '$_callback?code=CODE-SECRET&state=forged',
      );
      expect(auth.notice, contains("couldn't be verified"));
    });

    test('a cancelled browser leaves the person signed out', () async {
      final auth = await failWith(
        (_) async => throw PlatformException(
          code: 'CANCELED',
          message: 'User canceled authentication',
          details: '$_callback?code=CODE-SECRET',
        ),
      );
      expect(auth.notice, contains('cancelled'));
    });

    test('a denied consent leaves the person signed out', () async {
      final auth = await failWith(
        (url) async =>
            '$_callback?error=access_denied&state=${url.queryParameters['state']}',
      );
      expect(auth.notice, contains("didn't allow"));
    });

    test('a timed-out request says so', () async {
      final auth = await failWith(
        (url) async =>
            '$_callback?error=login_required&state=${url.queryParameters['state']}',
      );
      expect(auth.notice, contains('timed out'));
    });
  });

  group('accessToken', () {
    test('two calls near expiry cause one refresh only', () async {
      store.session = _session(expiresAt: clock.now.add(Duration(hours: 1)));
      final auth = controller();
      await auth.restore();
      clock.now = clock.now.add(Duration(minutes: 59, seconds: 30));

      neon.holdRefresh = Completer();
      final first = auth.accessToken();
      final second = auth.accessToken();
      neon.holdRefresh!.complete();

      expect(await Future.wait([first, second]), ['ACCESS-1', 'ACCESS-1']);
      expect(neon.tokenRequests, hasLength(1));
      expect(store.session!.refreshToken, 'REFRESH-1');
    });

    test('a refused refresh signs out instead of looping', () async {
      store.session = _session(expiresAt: clock.now.add(Duration(hours: 1)));
      final auth = controller();
      await auth.restore();
      clock.now = clock.now.add(Duration(hours: 2));
      neon.refuseRefresh = true;

      expect(await auth.accessToken(), isNull);
      expect(await auth.accessToken(), isNull);
      expect(neon.tokenRequests, hasLength(1));
      expect(auth.status, AuthStatus.signedOut);
      expect(auth.notice, sessionEndedMessage);
      expect(store.session, isNull);
    });

    test('no network keeps the session and reports it', () async {
      store.session = _session(expiresAt: clock.now.add(Duration(hours: 1)));
      final auth = controller();
      await auth.restore();
      clock.now = clock.now.add(Duration(hours: 2));
      neon.offline = true;

      await expectLater(
        auth.accessToken(),
        throwsA(
          isA<OAuthException>().having(
            (e) => e.kind,
            'kind',
            OAuthFailure.network,
          ),
        ),
      );
      expect(auth.status, AuthStatus.signedIn);
      expect(store.session, isNotNull);
    });
  });

  group('signOut', () {
    Future<AuthController> signedIn() async {
      final auth = controller();
      await auth.restore();
      await auth.signIn();
      neon.browserUrls.clear();
      return auth;
    }

    test('revokes, clears the device and ends the browser session', () async {
      final auth = await signedIn();
      await auth.signOut();

      expect(neon.revokeRequests.single['token'], 'REFRESH-1');
      expect(neon.revokeRequests.single['client_id'], 'client-1');
      expect(store.session, isNull);
      expect(neon.browserUrls.single.toString(), startsWith(_signOutPage));
      expect(auth.status, AuthStatus.signedOut);
      expect(auth.notice, signedOutMessage);
      expect(await auth.accessToken(), isNull);
    });

    test('with no network, still clears the device', () async {
      final auth = await signedIn();
      neon.offline = true;
      await auth.signOut();

      expect(store.session, isNull);
      expect(auth.status, AuthStatus.signedOut);
      expect(auth.notice, signedOutOfflineMessage);
      // The sign-out page couldn't load, so no tab is opened.
      expect(neon.browserUrls, isEmpty);
    });

    test('a closed sign-out tab still leaves the device clear', () async {
      final auth = await signedIn();
      neon.onSignInPage = null;
      final client = OAuthClient(
        config: _config,
        httpClient: neon.http_,
        browserStep: (_, _) async =>
            throw PlatformException(code: 'CANCELED', message: 'x'),
      );
      // Sign in with the normal browser, then sign out with one that closes.
      final closing = AuthController(
        client: client,
        store: store,
        clock: clock.call,
      );
      await closing.restore();
      expect(closing.status, AuthStatus.signedIn);
      await closing.signOut();

      expect(store.session, isNull);
      expect(closing.status, AuthStatus.signedOut);
      expect(closing.notice, signedOutBrowserKeptMessage);
      auth.dispose();
    });
  });
}
