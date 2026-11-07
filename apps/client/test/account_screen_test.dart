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

const _issuer = 'https://auth.example.test/neondb/auth';
const _callback = 'https://pages.example.test/auth/callback/android';

String _jwt(Map<String, dynamic> payload) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'EdDSA'})}.${part(payload)}.signature';
}

void main() {
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
