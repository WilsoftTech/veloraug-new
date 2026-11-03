import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/auth/oauth_config.dart';
import 'package:veloraug/widgets/dev_auth_proof.dart';

const _issuer = 'https://auth.example.test/neondb/auth';
const _callback = 'https://pages.example.test/auth/callback/android';

void main() {
  testWidgets('without settings it says so, and offers no actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DevAuthProof())),
    );
    expect(find.textContaining('not configured'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('sign-in shows non-secret facts, and no secret values', (
    tester,
  ) async {
    const accessToken = 'OPAQUE-ACCESS-TOKEN-VALUE';
    const refreshToken = 'REFRESH-TOKEN-VALUE';
    const code = 'AUTHORIZATION-CODE-VALUE';
    final client = MockClient((request) async {
      if (request.url.path.endsWith('oauth-authorization-server')) {
        return http.Response(
          jsonEncode({
            'issuer': _issuer,
            'authorization_endpoint': '$_issuer/oauth2/authorize',
            'token_endpoint': '$_issuer/oauth2/token',
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'access_token': accessToken,
          'refresh_token': refreshToken,
          'expires_in': 3600,
        }),
        200,
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DevAuthProof(
              httpClient: client,
              config: OAuthConfig(
                issuer: _issuer,
                clientId: 'client-1',
                resource: 'https://api.example.test',
                redirectUri: Uri.parse(_callback),
                signOutPage: Uri.parse('https://pages.example.test/sign-out'),
              ),
              browserStep: (url, _) async =>
                  '$_callback?code=$code&state=${url.queryParameters['state']}',
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign in'));
    await tester.pumpAndSettle();

    final shown = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(shown, contains('code exchanged'));
    expect(shown, contains('refresh token returned: true'));
    expect(shown, isNot(contains(accessToken)));
    expect(shown, isNot(contains(refreshToken)));
    expect(shown, isNot(contains(code)));
    expect(shown, contains('browser step returned after'));
  });

  testWidgets('a platform failure shows its code, and no secret values', (
    tester,
  ) async {
    const secret = 'https://pages.example.test/cb?code=SECRET-VALUE';
    final logged = <String?>[];
    final previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) => logged.add(message);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DevAuthProof(
              httpClient: MockClient((request) async {
                return http.Response(
                  jsonEncode({
                    'issuer': _issuer,
                    'authorization_endpoint': '$_issuer/oauth2/authorize',
                    'token_endpoint': '$_issuer/oauth2/token',
                  }),
                  200,
                );
              }),
              config: OAuthConfig(
                issuer: _issuer,
                clientId: 'client-1',
                resource: 'https://api.example.test',
                redirectUri: Uri.parse(_callback),
                signOutPage: Uri.parse('https://pages.example.test/sign-out'),
              ),
              browserStep: (url, _) async => throw PlatformException(
                code: 'CANCELED',
                message: 'User canceled authentication',
                details: secret,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign in'));
    await tester.pumpAndSettle();
    debugPrint = previousPrint;

    final shown = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(shown, contains('PlatformException code: CANCELED'));
    expect(shown, contains('browser step failed after'));
    expect(shown, isNot(contains('SECRET-VALUE')));
    expect(logged.join('\n'), contains('CANCELED'));
    expect(logged.join('\n'), isNot(contains('SECRET-VALUE')));
  });
}
