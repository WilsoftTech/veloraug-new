import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/app.dart';
import 'package:veloraug/auth/auth_controller.dart';
import 'package:veloraug/auth/oauth_client.dart';
import 'package:veloraug/auth/oauth_config.dart';
import 'package:veloraug/auth/token_store.dart';
import 'package:veloraug/widgets/dev_token_checks.dart';
import 'package:veloraug/widgets/profile_section.dart';

/// Signed in already, from a saved session. No network is used.
AuthController _signedInController() {
  final store = MemoryTokenStore()
    ..session = StoredSession(
      accessToken: 'ACCESS-SECRET',
      refreshToken: 'REFRESH-SECRET',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
      email: 'person@example.test',
    );
  return AuthController(
    client: OAuthClient(
      config: OAuthConfig(
        issuer: _issuer,
        clientId: 'client-1',
        resource: 'https://api.example.test',
        redirectUri: Uri.parse(_callback),
        signOutPage: Uri.parse('https://pages.example.test/sign-out'),
      ),
      httpClient: MockClient((_) async => http.Response('', 500)),
      browserStep: (_, _) async => throw UnimplementedError(),
    ),
    store: store,
  );
}

const _issuer = 'https://auth.example.test/neondb/auth';
const _callback = 'https://pages.example.test/auth/callback/android';

String _jwt(Map<String, dynamic> payload) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'EdDSA'})}.${part(payload)}.signature';
}

void main() {
  testWidgets('shows, changes and keeps the display name', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1400);
    addTearDown(tester.view.reset);

    String? nonce;
    String? displayName;
    final apiAuthorization = <String?>[];
    final httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('oauth-authorization-server')) {
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
        return http.Response(
          jsonEncode({
            'access_token': 'ACCESS-SECRET',
            'refresh_token': 'REFRESH-SECRET',
            'expires_in': 3600,
            'id_token': _jwt({'nonce': nonce, 'email': 'person@example.test'}),
          }),
          200,
        );
      }
      if (path == '/api/v1/me') {
        apiAuthorization.add(request.headers['Authorization']);
        if (request.method == 'PATCH') {
          displayName =
              (jsonDecode(request.body) as Map<String, Object?>)['display_name']
                  as String?;
        }
        return http.Response(
          jsonEncode({'user_id': 'user-1', 'display_name': displayName}),
          200,
        );
      }
      return http.Response('', 200);
    });
    final auth = AuthController(
      client: OAuthClient(
        config: OAuthConfig(
          issuer: _issuer,
          clientId: 'client-1',
          resource: 'https://api.example.test',
          redirectUri: Uri.parse(_callback),
          signOutPage: Uri.parse('https://pages.example.test/sign-out'),
        ),
        httpClient: httpClient,
        browserStep: (url, _) async {
          nonce = url.queryParameters['nonce'];
          return '$_callback?code=c&state=${url.queryParameters['state']}';
        },
      ),
      store: MemoryTokenStore(),
    );
    addTearDown(auth.dispose);
    await auth.restore();
    await auth.signIn();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileSection(auth: auth, httpClient: httpClient),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text("You haven't set a display name yet."), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '  Amara  ');
    await tester.tap(find.text('Save name'));
    await tester.pumpAndSettle();

    expect(find.text('Saved.'), findsOneWidget);
    expect(find.text('Your display name is Amara.'), findsOneWidget);
    expect(displayName, 'Amara');
    expect(apiAuthorization, everyElement('Bearer ACCESS-SECRET'));
    expect(find.textContaining('SECRET'), findsNothing);

    await tester.enterText(find.byType(TextFormField), 'x' * 81);
    await tester.tap(find.text('Save name'));
    await tester.pumpAndSettle();
    expect(find.text('Use 80 characters or fewer.'), findsOneWidget);
    expect(displayName, 'Amara');
  });

  testWidgets('a refused token says to sign in again', (tester) async {
    final auth = _signedInController();
    addTearDown(auth.dispose);
    await auth.restore();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileSection(
            auth: auth,
            httpClient: MockClient(
              (_) async => http.Response('{"detail":"Not signed in."}', 401),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining("didn't accept your sign-in"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a kept token can still be sent after sign-out', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 2400);
    addTearDown(tester.view.reset);
    String? nonce;
    final httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('oauth-authorization-server')) {
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
        return http.Response(
          jsonEncode({
            'access_token': 'ACCESS-SECRET',
            'refresh_token': 'REFRESH-SECRET',
            'expires_in': 3600,
            'id_token': _jwt({'nonce': nonce, 'email': 'person@example.test'}),
          }),
          200,
        );
      }
      return http.Response('', 200);
    });
    final auth = AuthController(
      client: OAuthClient(
        config: OAuthConfig(
          issuer: _issuer,
          clientId: 'client-1',
          resource: 'https://api.example.test',
          redirectUri: Uri.parse(_callback),
          signOutPage: Uri.parse('https://pages.example.test/sign-out'),
        ),
        httpClient: httpClient,
        browserStep: (url, _) async {
          if (url.path == '/sign-out') return '$_callback?signed_out=1';
          nonce = url.queryParameters['nonce'];
          return '$_callback?code=c&state=${url.queryParameters['state']}';
        },
      ),
      store: MemoryTokenStore(),
    );
    addTearDown(auth.dispose);

    await tester.pumpWidget(VeloraApp(authController: auth));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Keep the current token'));
    await tester.pumpAndSettle();
    expect(find.text('Send the kept token'), findsOneWidget);
    final before = tester.state(find.byType(DevTokenChecks));

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(find.text("You're signed out."), findsOneWidget);
    // The card itself isn't rebuilt by signing out.
    expect(tester.state(find.byType(DevTokenChecks)), same(before));
    expect(find.text('Send the kept token'), findsOneWidget);
  });

  testWidgets('signs in and out from the Account screen', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 900);
    addTearDown(tester.view.reset);

    String? nonce;
    final httpClient = MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('oauth-authorization-server')) {
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
        return http.Response(
          jsonEncode({
            'access_token': 'ACCESS-SECRET',
            'refresh_token': 'REFRESH-SECRET',
            'expires_in': 3600,
            'id_token': _jwt({'nonce': nonce, 'email': 'person@example.test'}),
          }),
          200,
        );
      }
      return http.Response('', 200);
    });
    final auth = AuthController(
      client: OAuthClient(
        config: OAuthConfig(
          issuer: _issuer,
          clientId: 'client-1',
          resource: 'https://api.example.test',
          redirectUri: Uri.parse(_callback),
          signOutPage: Uri.parse('https://pages.example.test/sign-out'),
        ),
        httpClient: httpClient,
        browserStep: (url, _) async {
          if (url.path == '/sign-out') return '$_callback?signed_out=1';
          nonce = url.queryParameters['nonce'];
          return '$_callback?code=c&state=${url.queryParameters['state']}';
        },
      ),
      store: MemoryTokenStore(),
    );
    addTearDown(auth.dispose);

    await tester.pumpWidget(VeloraApp(authController: auth));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Account').last);
    await tester.pumpAndSettle();

    expect(find.text("You're signed out"), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text("You're signed in"), findsOneWidget);
    expect(find.text('Signed in as person@example.test.'), findsOneWidget);
    expect(find.textContaining('SECRET'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(find.text("You're signed out"), findsOneWidget);
    expect(find.text("You're signed out."), findsOneWidget);
  });
}
