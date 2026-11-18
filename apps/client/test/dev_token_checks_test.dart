import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/auth/auth_controller.dart';
import 'package:veloraug/auth/oauth_client.dart';
import 'package:veloraug/auth/oauth_config.dart';
import 'package:veloraug/auth/token_store.dart';
import 'package:veloraug/widgets/dev_token_checks.dart';
import 'package:veloraug/l10n/app_localizations.dart';

String _jwt(Map<String, Object?> payload, String signature) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'EdDSA'})}.${part(payload)}.$signature';
}

void main() {
  final issued = DateTime.utc(2026, 11, 7, 12);
  final token = _jwt({
    'exp': issued.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
  }, 'SIGNATUREPARTSECRET');

  late DateTime now;
  late List<String?> sent;

  /// A fake API that accepts only the real token, and only before it expires.
  MockClient api() => MockClient((request) async {
    final authorization = request.headers['Authorization'];
    sent.add(authorization);
    final valid =
        authorization == 'Bearer $token' &&
        now.isBefore(issued.add(const Duration(hours: 1)));
    return http.Response('{}', valid ? 200 : 401);
  });

  Future<AuthController> signedIn() async {
    final store = MemoryTokenStore()
      ..session = StoredSession(
        accessToken: token,
        refreshToken: 'REFRESH',
        expiresAt: issued.add(const Duration(hours: 1)),
        email: 'person@example.test',
      );
    final auth = AuthController(
      client: OAuthClient(
        config: OAuthConfig(
          issuer: 'https://auth.example.test/neondb/auth',
          clientId: 'client-1',
          resource: 'https://api.example.test',
          redirectUri: Uri.parse('https://pages.example.test/cb'),
          signOutPage: Uri.parse('https://pages.example.test/sign-out'),
        ),
        httpClient: MockClient((_) async => http.Response('', 500)),
        browserStep: (_, _) async => throw UnimplementedError(),
      ),
      store: store,
      clock: () => now,
    );
    await auth.restore();
    return auth;
  }

  setUp(() {
    now = issued.add(const Duration(minutes: 5));
    sent = [];
  });

  Future<void> pump(WidgetTester tester, AuthController auth) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(500, 1200);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(
          body: SingleChildScrollView(
            child: DevTokenChecks(
              auth: auth,
              httpClient: api(),
              clock: () => now,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> press(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('no token and a changed token are both refused', (tester) async {
    final auth = await signedIn();
    addTearDown(auth.dispose);
    await pump(tester, auth);

    await press(tester, 'Send no token');
    await press(tester, 'Send a changed token');

    expect(sent[0], isNull);
    expect(sent[1], startsWith('Bearer '));
    expect(sent[1], isNot('Bearer $token'));
    expect(sent[1]!.length, 'Bearer $token'.length);
    expect(find.textContaining('answered 401. As expected.'), findsNWidgets(2));
    expect(find.textContaining('SECRET'), findsNothing);
  });

  testWidgets('a kept token works before expiry, even after sign-out, and '
      'is refused after', (tester) async {
    final auth = await signedIn();
    addTearDown(auth.dispose);
    await pump(tester, auth);

    await press(tester, 'Keep the current token');
    expect(find.textContaining('It expires at'), findsOneWidget);

    now = now.add(const Duration(minutes: 20));
    await press(tester, 'Send the kept token');
    expect(
      find.textContaining(
        '20 min old, before its expiry: the API answered 200',
      ),
      findsOneWidget,
    );

    now = now.add(const Duration(minutes: 40));
    await press(tester, 'Send the kept token');
    expect(
      find.textContaining(
        '60 min old, past its expiry: the API answered 401. '
        'As expected.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('SECRET'), findsNothing);
  });

  testWidgets('without sign-in settings, the buttons do nothing', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Scaffold(body: DevTokenChecks(auth: null)),
      ),
    );

    final button = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Send no token'),
    );
    expect(button.onPressed, isNull);
  });
}
