import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:veloraug/api/playback_api.dart';
import 'package:veloraug/auth/auth_controller.dart';
import 'package:veloraug/l10n/app_localizations.dart';
import 'package:veloraug/screens/pass_screen.dart';
import 'package:veloraug/screens/player_screen.dart';

import 'support.dart';

/// Answers the fake API's requests without letting the payment checks run.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  late List<Uri> opened;

  setUp(() {
    opened = [];
    BuyPassScreen.openPage = (page) async {
      opened.add(page);
      return true;
    };
    BuyPassScreen.checkEvery = const Duration(seconds: 3);
    BuyPassScreen.checkFor = const Duration(minutes: 15);
  });

  /// Lets the payment page's checks run: one per [BuyPassScreen.checkEvery].
  Future<void> checks(WidgetTester tester, int count) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(BuyPassScreen.checkEvery);
      await settle(tester);
    }
  }

  group('the Account tab', () {
    testWidgets('without a pass offers one', (tester) async {
      await pumpApp(tester, FakeApi(), signedIn: true);
      await goTo(tester, 'Account');

      expect(find.text('Your pass'), findsOneWidget);
      expect(find.text("You don't have a pass."), findsOneWidget);
      expect(find.text('Buy a pass'), findsOneWidget);
    });

    testWidgets('with a pass says until when, and a payment being checked', (
      tester,
    ) async {
      final api = FakeApi()
        ..myPass = {
          'active': true,
          'current_ends_at': '2026-11-20T09:30:00Z',
          'ends_at': '2026-11-27T09:30:00Z',
          'checking': true,
        };
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Account');

      expect(find.textContaining('Your pass runs until '), findsOneWidget);
      expect(
        find.textContaining('With the pass you bought next'),
        findsOneWidget,
      );
      expect(
        find.text(
          'A payment is still being checked. It shows here once it has gone through.',
        ),
        findsOneWidget,
      );
      expect(find.text('Buy another pass'), findsOneWidget);
    });

    testWidgets('signed out, there is no pass section', (tester) async {
      await pumpApp(tester, FakeApi());
      await goTo(tester, 'Account');

      expect(find.text('Your pass'), findsNothing);
    });
  });

  group('buying a pass', () {
    testWidgets('opens Pesapal, waits, and shows the pass ready', (
      tester,
    ) async {
      final api = FakeApi();
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Account');
      await tester.tap(find.text('Buy a pass'));
      await tester.pumpAndSettle();

      expect(find.text('1 day'), findsOneWidget);
      expect(find.text('UGX 2,000'), findsOneWidget);
      expect(find.text('1 week'), findsOneWidget);
      expect(find.text('UGX 8,000'), findsOneWidget);

      await tester.tap(find.text('1 day'));
      await settle(tester);

      expect(api.checkouts.single, {
        'plan_id': 'day',
        'email': 'owner@example.test',
      });
      expect(
        opened.single.toString(),
        'https://cybqa.pesapal.com/iframe/pay-1',
      );
      expect(find.text('Finish paying on Pesapal'), findsOneWidget);

      await checks(tester, 1);
      expect(find.text('Finish paying on Pesapal'), findsOneWidget);
      await checks(tester, 1);

      expect(find.text('Your pass is ready'), findsOneWidget);
      expect(find.textContaining('You can watch until '), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carry on watching'));
      await tester.pumpAndSettle();

      // Back on the Account tab, which shows the new pass.
      expect(find.textContaining('Your pass runs until '), findsOneWidget);
    });

    testWidgets('a failed payment can be tried again on Pesapal, or dropped', (
      tester,
    ) async {
      final api = FakeApi()..paymentStates = ['failed', 'failed', 'completed'];
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Account');
      await tester.tap(find.text('Buy a pass'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 week'));
      await settle(tester);

      await checks(tester, 1);
      expect(find.text("That payment didn't go through"), findsOneWidget);
      await tester.tap(find.text('Open Pesapal again'));
      await settle(tester);
      expect(opened, hasLength(2));

      // The viewer paid another way on the same page.
      await checks(tester, 2);
      expect(find.text('Your pass is ready'), findsOneWidget);
    });

    testWidgets('a payment given up on goes back to the passes', (
      tester,
    ) async {
      final api = FakeApi()..paymentStates = ['abandoned'];
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Account');
      await tester.tap(find.text('Buy a pass'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 day'));
      await settle(tester);
      await checks(tester, 1);

      expect(
        find.text(
          'This payment wasn\'t completed. Choose a pass to try again.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Choose a pass').last);
      await tester.pumpAndSettle();
      expect(find.text('UGX 2,000'), findsOneWidget);
    });

    testWidgets('payments being down is said plainly', (tester) async {
      final api = FakeApi()..checkoutStatus = 503;
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Account');
      await tester.tap(find.text('Buy a pass'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 day'));
      await settle(tester);

      expect(
        find.text(
          "Payments aren't available right now. Try again in a few minutes.",
        ),
        findsOneWidget,
      );
      expect(opened, isEmpty);
    });

    testWidgets('a page that isn\'t Pesapal\'s is never opened', (
      tester,
    ) async {
      final api = FakeApi()..paymentPage = 'https://pesapal.example.net/pay';
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Account');
      await tester.tap(find.text('Buy a pass'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 day'));
      await settle(tester);

      expect(opened, isEmpty);
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    });
  });

  group('the player', () {
    Future<FakeVideo> pumpPlayer(
      WidgetTester tester,
      FakeApi api, {
      String? email = 'viewer@example.test',
      DateTime Function()? clock,
    }) async {
      final auth = fakeAuth(signedIn: true, email: email);
      await auth.restore();
      final video = FakeVideo();
      await tester.pumpWidget(
        AuthScope(
          controller: auth,
          child: PlaybackScope(
            api: api.playback(auth),
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              home: PlayerScreen(
                itemId: 'movie-item',
                title: 'Fast X',
                viewBuilder: video.build,
                clock: clock ?? () => DateTime.utc(2026),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return video;
    }

    testWidgets('without a pass offers one, then plays', (tester) async {
      final api = FakeApi()..grantStatus = 402;
      final video = await pumpPlayer(tester, api);

      expect(find.text('You need a pass to watch'), findsOneWidget);
      expect(
        find.text('Buy a pass to watch everything on VeloraUG.'),
        findsOneWidget,
      );
      expect(video.requests, isEmpty);

      await tester.tap(find.text('Buy a pass'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 day'));
      await settle(tester);
      await checks(tester, 2);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carry on watching'));
      await tester.pumpAndSettle();

      expect(find.text('playing grant-2.sig'), findsOneWidget);
      expect(video.requests.last.startAt, Duration.zero);
    });

    testWidgets('a pass ending mid-film says so, and carries on after', (
      tester,
    ) async {
      final api = FakeApi()..expiresAt = DateTime.utc(2026, 1, 1, 2);
      var now = DateTime.utc(2026, 1, 1, 1);
      final video = await pumpPlayer(tester, api, clock: () => now);
      expect(find.text('playing grant-1.sig'), findsOneWidget);

      // The pass ends; the grant ended with it.
      api.grantStatus = 402;
      now = DateTime.utc(2026, 1, 1, 2, 0, 5);
      video.requests.last.onProgress!(const Duration(minutes: 41));
      video.requests.last.onFailed(const Duration(minutes: 41));
      await tester.pumpAndSettle();

      expect(find.text('Your pass has ended'), findsOneWidget);
      expect(
        find.text('Buy another pass to carry on from where you were.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Buy a pass'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 day'));
      await settle(tester);
      await checks(tester, 2);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carry on watching'));
      await tester.pumpAndSettle();

      expect(find.text('playing grant-3.sig'), findsOneWidget);
      expect(video.requests.last.startAt, const Duration(minutes: 41));
    });

    testWidgets('without an email, Pesapal gets a phone number', (
      tester,
    ) async {
      final api = FakeApi()..grantStatus = 402;
      await pumpPlayer(tester, api, email: null);
      await tester.tap(find.text('Buy a pass'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('1 day'));
      await settle(tester);
      expect(
        find.text('Enter a phone number, such as 0772 123 456.'),
        findsOneWidget,
      );
      expect(api.checkouts, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone number'),
        '0772 123 456',
      );
      await tester.tap(find.text('1 day'));
      await settle(tester);
      expect(api.checkouts.single, {'plan_id': 'day', 'phone': '0772 123 456'});
      await checks(tester, 2);
    });
  });

  group('admin settings', () {
    testWidgets('pass prices are shown, checked and saved', (tester) async {
      final api = FakeApi()..isAdmin = true;
      final saved = <String, Object?>{};
      api.admin.addAll({
        'GET /admins': (_) => json([
          {
            'user_id': 'u1',
            'email': 'owner@example.test',
            'added_by_email': null,
            'added_at': '2026-11-17T10:00:00Z',
          },
        ]),
        'GET /languages': (_) => json([
          {'code': 'lg', 'name': 'Luganda'},
        ]),
        'GET /drafts': (_) => json({'editions': []}),
        'GET /pass-plans': (_) => json([
          {'id': 'day', 'days': 1, 'price_ugx': 2000},
          {'id': 'week', 'days': 7, 'price_ugx': null},
          {'id': 'month', 'days': 30, 'price_ugx': 25000},
        ]),
        'PATCH /pass-plans/week': (request) {
          saved['week'] = jsonBody(request)['price_ugx'];
          return json({'id': 'week', 'days': 7, 'price_ugx': 8000});
        },
        'PATCH /pass-plans/month': (request) {
          saved['month'] = jsonBody(request)['price_ugx'];
          return json({'id': 'month', 'days': 30, 'price_ugx': null});
        },
      });
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Admin');
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      final week = find.widgetWithText(TextFormField, 'Price for 1 week (UGX)');
      final month = find.widgetWithText(
        TextFormField,
        'Price for 1 month (UGX)',
      );
      await tester.ensureVisible(week);
      await tester.enterText(week, '100');
      await tester.ensureVisible(find.text('Save prices'));
      await tester.tap(find.text('Save prices'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Enter a whole number from 500 to 10,000,000, or leave it empty.',
        ),
        findsOneWidget,
      );
      expect(saved, isEmpty);

      await tester.enterText(week, '8,000');
      await tester.enterText(month, '');
      await tester.ensureVisible(find.text('Save prices'));
      await tester.tap(find.text('Save prices'));
      await tester.pumpAndSettle();

      // Only what changed is sent; the day pass isn't.
      expect(saved, {'week': 8000, 'month': null});
      expect(api.adminCalls.where((c) => c.startsWith('PATCH')), hasLength(2));
    });
  });
}

Map<String, Object?> jsonBody(http.Request request) =>
    jsonDecode(request.body) as Map<String, Object?>;
