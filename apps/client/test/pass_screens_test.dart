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

Finder payButton(String price) => find.text('Pay UGX $price');

void main() {
  late List<Uri> opened;
  late List<Uri> shown;
  VoidCallback? returnFromPesapal;
  var browserOpens = true;

  setUp(() {
    opened = [];
    shown = [];
    returnFromPesapal = null;
    browserOpens = true;
    BuyPassScreen.openPage = (page) async {
      opened.add(page);
      return browserOpens;
    };
    // Pesapal's page inside the app, without a real web view.
    BuyPassScreen.paymentView = (context, page, onReturned) {
      if (shown.isEmpty || shown.last != page) shown.add(page);
      returnFromPesapal = onReturned;
      return Text('Pesapal form: $page');
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

  /// Opens one of the account hub's rows.
  Future<void> openRow(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).first);
    await tester.tap(find.text(label).first);
    await tester.pumpAndSettle();
  }

  Future<void> openPlans(WidgetTester tester) async {
    if (find.text('Choose a plan').evaluate().isEmpty) {
      await openRow(tester, 'Plans & membership');
    }
    await tester.ensureVisible(find.text('Choose a plan').first);
    await tester.tap(find.text('Choose a plan').first);
    await tester.pumpAndSettle();
  }

  Future<void> pay(WidgetTester tester, String price) async {
    await tester.ensureVisible(payButton(price));
    await tester.tap(payButton(price));
    await settle(tester);
  }

  group('the Account tab', () {
    testWidgets('without a plan offers one', (tester) async {
      await pumpApp(tester, FakeApi(), signedIn: true);
      await goTo(tester, 'Account');
      expect(find.text('Plans & membership'), findsOneWidget);
      expect(find.text('Payments'), findsOneWidget);

      await openRow(tester, 'Plans & membership');
      expect(find.text('My membership'), findsOneWidget);
      expect(find.text('No active plan'), findsOneWidget);
      expect(find.text('Choose a plan'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await openRow(tester, 'Payments');
      expect(find.text('No payments yet.'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await openRow(tester, 'Settings');
      expect(find.text('My devices'), findsOneWidget);
    });

    testWidgets('with a plan: dates, time left, allowances, what comes next', (
      tester,
    ) async {
      final api = FakeApi()
        ..myPass = {
          'active': true,
          'current_ends_at': '2030-01-31T09:30:00Z',
          'ends_at': '2030-04-30T09:30:00Z',
          'checking': true,
          'current': {
            'id': 'p1',
            'plan_id': 'velora_prime',
            'plan_name': 'Velora Prime',
            'starts_at': '2030-01-01T09:30:00Z',
            'ends_at': '2030-01-31T09:30:00Z',
            'max_devices': 1,
            'max_streams': 1,
          },
          'queued': [
            {
              'id': 'p2',
              'plan_id': 'velora_duo',
              'plan_name': 'Velora Duo',
              'starts_at': '2030-01-31T09:30:00Z',
              'ends_at': '2030-04-30T09:30:00Z',
              'max_devices': 2,
              'max_streams': 2,
            },
          ],
        };
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Account');
      await openRow(tester, 'Plans & membership');

      expect(find.text('Velora Prime'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Payment being checked'), findsOneWidget);
      expect(find.textContaining('Expires '), findsOneWidget);
      expect(find.textContaining(' days left'), findsOneWidget);
      expect(find.text('1 registered device'), findsOneWidget);
      expect(find.text('1 screen at a time'), findsOneWidget);
      expect(find.textContaining('Next: Velora Duo, from '), findsOneWidget);
      expect(find.text('Renew'), findsOneWidget);
      expect(find.text('Change plan'), findsOneWidget);
    });

    testWidgets('lists devices and payments, and removes a device', (
      tester,
    ) async {
      final api = FakeApi()
        ..devices = [
          {
            'id': 'd1',
            'label': 'Kitchen laptop',
            'platform': 'web',
            'registered_at': '2026-11-01T10:00:00Z',
            'last_active_at': '2026-11-20T10:00:00Z',
            'current': true,
          },
        ]
        ..payments = [
          {
            'id': 'pay-9',
            'plan_id': 'velora_prime',
            'plan_name': 'Velora Prime',
            'amount_ugx': 18000,
            'state': 'completed',
            'created_at': '2026-11-20T10:00:00Z',
            'completed_at': '2026-11-20T10:01:00Z',
            'provider_reference': 'MTN123',
          },
          {
            'id': 'pay-8',
            'plan_id': 'velora_start',
            'plan_name': 'Velora Start',
            'amount_ugx': 6000,
            'state': 'failed',
            'created_at': '2026-11-19T10:00:00Z',
            'completed_at': null,
            'provider_reference': null,
          },
        ];
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Account');

      await openRow(tester, 'Payments');
      expect(find.text('Velora Prime · UGX 18,000'), findsOneWidget);
      expect(find.textContaining('Ref. MTN123'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await openRow(tester, 'Settings');
      await openRow(tester, 'My devices');
      expect(find.text('Kitchen laptop'), findsOneWidget);
      expect(find.text('This device'), findsOneWidget);

      await tester.ensureVisible(find.text('Remove').first);
      await tester.tap(find.text('Remove').first);
      await tester.pumpAndSettle();
      expect(find.text('Remove this device?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(api.removedDevices, ['d1']);
      expect(find.text('Kitchen laptop'), findsNothing);
    });

    testWidgets('signed out, there is no membership section', (tester) async {
      await pumpApp(tester, FakeApi());
      await goTo(tester, 'Account');

      expect(find.text('Plans & membership'), findsNothing);
      expect(find.text('Payments'), findsNothing);
      await openRow(tester, 'Settings');
      expect(find.text('My devices'), findsNothing);
    });
  });

  group('choosing a plan', () {
    testWidgets('each card shows the server\'s name, price and allowances', (
      tester,
    ) async {
      await pumpApp(tester, FakeApi(), signedIn: true);
      await goTo(tester, 'Account');
      await openPlans(tester);

      expect(find.text('Velora Start'), findsOneWidget);
      expect(find.text('UGX 6,000'), findsOneWidget);
      expect(find.text('7 days'), findsOneWidget);
      expect(find.text('Velora Max'), findsOneWidget);
      expect(find.text('UGX 150,000'), findsOneWidget);
      expect(find.text('3 registered devices'), findsOneWidget);
      expect(find.text('3 screens at a time'), findsOneWidget);
      // Only the featured plan is marked.
      expect(find.text('Most popular'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('plan-velora_prime')),
          matching: find.text('Most popular'),
        ),
        findsOneWidget,
      );
      expect(find.text('No automatic renewal'), findsNWidgets(3));
    });

    for (final (width, columns) in [(1280.0, 3), (800.0, 2), (360.0, 1)]) {
      testWidgets('at $width wide, $columns across without overflow', (
        tester,
      ) async {
        await pumpApp(
          tester,
          FakeApi(),
          signedIn: true,
          size: Size(width, 2400),
        );
        await goTo(tester, 'Account');
        await openPlans(tester);

        expect(tester.takeException(), isNull);
        final start = tester.getTopLeft(
          find.byKey(const ValueKey('plan-velora_start')),
        );
        final prime = tester.getTopLeft(
          find.byKey(const ValueKey('plan-velora_prime')),
        );
        final max = tester.getTopLeft(
          find.byKey(const ValueKey('plan-velora_max')),
        );
        final onFirstRow = [
          start,
          prime,
          max,
        ].where((at) => (at.dy - start.dy).abs() < 1).length;
        expect(onFirstRow, columns);
      });
    }

    testWidgets('pays on Pesapal inside the app, and shows the plan ready', (
      tester,
    ) async {
      final api = FakeApi();
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Account');
      await openPlans(tester);
      await pay(tester, '6,000');

      expect(api.checkouts.single, {
        'plan_id': 'velora_start',
        'email': 'owner@example.test',
      });
      // Pesapal's page shows here: nothing opens outside the app.
      expect(opened, isEmpty);
      expect(
        shown.single.toString(),
        'https://cybqa.pesapal.com/iframe/pay-1',
      );
      expect(find.text('Pay for your plan'), findsOneWidget);
      expect(
        find.text('Pesapal form: https://cybqa.pesapal.com/iframe/pay-1'),
        findsOneWidget,
      );

      // Paying isn't proof until the API says so.
      await checks(tester, 1);
      expect(find.textContaining('Pesapal form: '), findsOneWidget);
      await checks(tester, 1);

      expect(find.text('Your pass is ready'), findsOneWidget);
      expect(find.textContaining('You can watch until '), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Carry on watching'));
      await tester.pumpAndSettle();

      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('a failed try stays on Pesapal\'s page to try again', (
      tester,
    ) async {
      final api = FakeApi()..paymentStates = ['failed', 'failed', 'completed'];
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Account');
      await openPlans(tester);
      await pay(tester, '18,000');

      // Said above Pesapal's page, which stays for another try.
      await checks(tester, 2);
      expect(find.text("That payment didn't go through"), findsNothing);
      expect(
        find.textContaining("That try didn't go through."),
        findsOneWidget,
      );
      expect(find.textContaining('Pesapal form: '), findsOneWidget);
      expect(find.text('Choose a plan'), findsOneWidget);

      await checks(tester, 1);
      expect(find.text('Your pass is ready'), findsOneWidget);
    });

    testWidgets('a new try clears the failure note', (tester) async {
      final api = FakeApi()
        ..paymentStates = ['failed', 'pending', 'completed'];
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Account');
      await openPlans(tester);
      await pay(tester, '6,000');

      await checks(tester, 1);
      expect(find.textContaining("That try didn't go through."), findsOneWidget);
      await checks(tester, 1);
      expect(find.textContaining("That try didn't go through."), findsNothing);
      expect(find.textContaining('Pesapal form: '), findsOneWidget);
    });

    testWidgets('on a short screen the buttons sit above the form', (
      tester,
    ) async {
      await pumpApp(tester, FakeApi(), signedIn: true);
      await goTo(tester, 'Account');
      await openPlans(tester);
      await pay(tester, '6,000');
      // A phone turned on its side.
      tester.view.physicalSize = const Size(800, 360);
      await settle(tester);

      final form = tester.getRect(find.textContaining('Pesapal form: '));
      final button = tester.getRect(find.text('Pay in my browser instead'));
      expect(button.bottom, lessThan(form.top));
      final box = tester.getRect(
        find.ancestor(
          of: find.textContaining('Pesapal form: '),
          matching: find.byType(SizedBox),
        ).first,
      );
      // Always a strip of the screen to scroll with, outside the form.
      expect(box.height, lessThanOrEqualTo(360 - 56 - 100));
    });

    testWidgets('Pesapal sending the viewer back checks at once', (
      tester,
    ) async {
      final api = FakeApi()..paymentStates = ['pending', 'completed'];
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Account');
      await openPlans(tester);
      await pay(tester, '6,000');
      final before = api.paymentChecks;

      returnFromPesapal!();
      await settle(tester);
      expect(api.paymentChecks, before + 1);
      expect(find.text('Checking your payment'), findsWidgets);
      expect(find.textContaining('Pesapal form: '), findsNothing);

      await checks(tester, 1);
      expect(find.text('Your pass is ready'), findsOneWidget);
    });

    testWidgets('can pay in the browser instead, and come back', (
      tester,
    ) async {
      final api = FakeApi()..paymentStates = ['failed', 'failed', 'completed'];
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Account');
      await openPlans(tester);
      await pay(tester, '18,000');

      await tester.ensureVisible(find.text('Pay in my browser instead'));
      await tester.tap(find.text('Pay in my browser instead'));
      await settle(tester);
      expect(opened.single, shown.single);
      expect(find.text('Finish paying in your browser'), findsOneWidget);

      // Paying in the browser, a failure is said here.
      await checks(tester, 1);
      expect(find.text("That payment didn't go through"), findsOneWidget);
      await tester.tap(find.text('Try paying again'));
      await settle(tester);
      expect(find.textContaining('Pesapal form: '), findsOneWidget);

      await checks(tester, 2);
      expect(find.text('Your pass is ready'), findsOneWidget);
    });

    testWidgets('a browser that won\'t open keeps paying in the app', (
      tester,
    ) async {
      browserOpens = false;
      await pumpApp(tester, FakeApi(), signedIn: true);
      await goTo(tester, 'Account');
      await openPlans(tester);
      await pay(tester, '6,000');

      await tester.ensureVisible(find.text('Pay in my browser instead'));
      await tester.tap(find.text('Pay in my browser instead'));
      await settle(tester);
      expect(
        find.text(
          "Couldn't open your browser. You can pay here in the app instead.",
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Pesapal form: '), findsOneWidget);
    });

    testWidgets('a payment given up on goes back to the plans', (tester) async {
      final api = FakeApi()..paymentStates = ['abandoned'];
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Account');
      await openPlans(tester);
      await pay(tester, '6,000');
      await checks(tester, 1);

      expect(
        find.text(
          'This payment wasn\'t completed. Choose a pass to try again.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Choose a plan').last);
      await tester.pumpAndSettle();
      expect(find.text('UGX 6,000'), findsOneWidget);
    });

    for (final (status, message) in [
      (503, "Payments aren't available right now. Try again in a few minutes."),
      (429, 'Too many attempts. Wait a moment and try again.'),
    ]) {
      testWidgets('a checkout answered $status is said plainly', (
        tester,
      ) async {
        final api = FakeApi()..checkoutStatus = status;
        await pumpApp(tester, api, signedIn: true);
        await goTo(tester, 'Account');
        await openPlans(tester);
        await pay(tester, '6,000');

        expect(find.text(message), findsOneWidget);
        expect(opened, isEmpty);
        expect(shown, isEmpty);
      });
    }

    testWidgets('a page that isn\'t Pesapal\'s is never opened', (
      tester,
    ) async {
      final api = FakeApi()..paymentPage = 'https://pesapal.example.net/pay';
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Account');
      await openPlans(tester);
      await pay(tester, '6,000');

      expect(opened, isEmpty);
      expect(shown, isEmpty);
      expect(find.text('Something went wrong. Try again.'), findsOneWidget);
    });

    testWidgets('nothing for sale says so', (tester) async {
      final api = FakeApi()..passPlans = [];
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Account');
      await openPlans(tester);

      expect(find.text('No passes are for sale right now.'), findsOneWidget);
    });
  });

  group('the player', () {
    Future<FakeVideo> pumpPlayer(
      WidgetTester tester,
      FakeApi api, {
      String? email = 'viewer@example.test',
      DateTime Function()? clock,
    }) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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

    testWidgets('without a plan offers one, then plays', (tester) async {
      final api = FakeApi()..grantStatus = 402;
      final video = await pumpPlayer(tester, api);

      expect(find.text('You need a pass to watch'), findsOneWidget);
      expect(video.requests, isEmpty);

      await tester.tap(find.text('Choose a plan'));
      await tester.pumpAndSettle();
      await pay(tester, '6,000');
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

      api.grantStatus = 402;
      now = DateTime.utc(2026, 1, 1, 2, 0, 5);
      video.requests.last.onProgress!(const Duration(minutes: 41));
      video.requests.last.onFailed(const Duration(minutes: 41));
      await tester.pumpAndSettle();

      expect(find.text('Your pass has ended'), findsOneWidget);

      await tester.tap(find.text('Choose a plan'));
      await tester.pumpAndSettle();
      await pay(tester, '6,000');
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
      await tester.tap(find.text('Choose a plan'));
      await tester.pumpAndSettle();

      await pay(tester, '6,000');
      expect(
        find.text('Enter a phone number, such as 0772 123 456.'),
        findsOneWidget,
      );
      expect(api.checkouts, isEmpty);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone number'),
        '0772 123 456',
      );
      await pay(tester, '6,000');
      expect(api.checkouts.single, {
        'plan_id': 'velora_start',
        'phone': '0772 123 456',
      });
      await checks(tester, 2);
    });

    testWidgets('an unregistered device registers itself, then plays', (
      tester,
    ) async {
      final api = FakeApi()
        ..grantStatus = 403
        ..grantRefusal = {
          'detail': {'code': 'device_required', 'message': 'x'},
        };
      api.intercept = (request) {
        // Registered: the next grant is allowed.
        if (request.url.path == '/api/v1/me/devices') {
          api
            ..grantRefusal = null
            ..grantStatus = 200;
        }
        return null;
      };
      await pumpPlayer(tester, api);

      expect(api.deviceRegistrations, hasLength(1));
      expect(
        jsonDecode(api.deviceRegistrations.single.body),
        containsPair('platform', isA<String>()),
      );
      expect(api.grantDevices, [null, deviceCredential]);
      expect(await api.deviceStore.read(), deviceCredential);
      expect(find.text('playing grant-2.sig'), findsOneWidget);
    });

    testWidgets('a device limit offers to manage devices', (tester) async {
      final api = FakeApi()
        ..grantStatus = 409
        ..grantRefusal = {
          'detail': {'code': 'device_limit', 'message': 'x', 'limit': 1},
        };
      await pumpPlayer(tester, api);

      expect(find.text('Device limit reached'), findsOneWidget);
      expect(find.text('Manage devices'), findsOneWidget);
      // Not mistaken for "can't be watched yet".
      expect(find.text("This can't be watched yet."), findsNothing);
    });

    testWidgets('a stream limit offers to stop the other device', (
      tester,
    ) async {
      final api = FakeApi()
        ..grantStatus = 409
        ..grantRefusal = {
          'detail': {
            'code': 'stream_limit',
            'message': 'x',
            'limit': 1,
            'sessions': [
              {
                'id': 'other-session',
                'device_label': 'Living room TV',
                'started_at': '2026-01-01T00:00:00Z',
              },
            ],
          },
        };
      final video = await pumpPlayer(tester, api);

      expect(find.text('Playing on another device'), findsOneWidget);
      api.grantStatus = 200;
      await tester.tap(find.text('Stop on Living room TV and watch here'));
      await tester.pumpAndSettle();

      expect(api.stoppedSessions, ['other-session']);
      expect(video.requests, isNotEmpty);
    });

    testWidgets('keeps its session alive, and stops when it is ended', (
      tester,
    ) async {
      final api = FakeApi()..sessions = true;
      await pumpPlayer(tester, api);
      expect(find.text('playing grant-1.sig'), findsOneWidget);

      await tester.pump(const Duration(seconds: 61));
      await settle(tester);
      expect(api.heartbeats, 1);
      expect(find.text('playing grant-1.sig'), findsOneWidget);

      api.heartbeatStatus = 410;
      await tester.pump(const Duration(seconds: 60));
      await settle(tester);

      expect(find.text('Playback stopped'), findsOneWidget);
      expect(find.text('Watch here again'), findsOneWidget);
    });

    testWidgets('a heartbeat that finds the pass over says so', (tester) async {
      final api = FakeApi()
        ..sessions = true
        ..heartbeatStatus = 402;
      await pumpPlayer(tester, api);

      await tester.pump(const Duration(seconds: 61));
      await settle(tester);

      expect(find.text('Your pass has ended'), findsOneWidget);
    });
  });

  group('admin subscriptions', () {
    testWidgets('plans, prices and sale flags are shown, checked and saved', (
      tester,
    ) async {
      final api = FakeApi()..isAdmin = true;
      final saved = <Map<String, Object?>>[];
      api.admin.addAll({
        'GET /drafts': (_) => json({'editions': []}),
        'GET /billing/metrics': (_) => json({
          'active_subscribers': 4,
          'by_plan': [
            {
              'plan_id': 'velora_prime',
              'plan_name': 'Velora Prime',
              'subscribers': 4,
            },
          ],
          'revenue_30_days_ugx': 72000,
          'completed_30_days': 4,
          'failed_30_days': 1,
          'reversed_30_days': 0,
          'abandoned_30_days': 2,
          'pending_now': 0,
          'active_devices': 5,
          'live_sessions': 2,
        }),
        'GET /pass-plans': (_) => json([
          {
            'id': 'velora_prime',
            'days': 30,
            'price_ugx': 18000,
            'display_name': 'Velora Prime',
            'max_devices': 1,
            'max_streams': 1,
            'featured': true,
            'for_sale': true,
            'legacy': false,
          },
          {
            'id': 'day',
            'days': 1,
            'price_ugx': null,
            'display_name': '1 day',
            'max_devices': 1,
            'max_streams': 1,
            'featured': false,
            'for_sale': false,
            'legacy': true,
          },
        ]),
        'PATCH /pass-plans/velora_prime': (request) {
          saved.add(jsonBody(request));
          return json({});
        },
        'GET /billing/payments': (request) => json([
          {
            'id': 'pay-1',
            'user_id': 'u2',
            'plan_id': 'velora_prime',
            'plan_name': 'Velora Prime',
            'amount_ugx': 18000,
            'state': request.url.queryParameters['state'] ?? 'completed',
            'created_at': '2026-11-20T10:00:00Z',
            'completed_at': null,
            'payment_method': 'MTN',
            'provider_reference': 'ABC',
            'tracking_id': 't',
            'reason': null,
            'contact': 'v***@example.com',
          },
        ]),
        'GET /billing/subscribers': (_) => json([]),
        'GET /billing/plan-changes': (_) => json([]),
      });
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Admin');
      await tester.tap(find.text('Subscriptions'));
      await tester.pumpAndSettle();

      expect(find.text('Active subscribers'), findsWidgets);
      expect(find.text('UGX 72,000'), findsOneWidget);
      expect(find.text('Legacy pass, kept for history'), findsOneWidget);
      expect(find.textContaining('v***@example.com'), findsOneWidget);

      final price = find.widgetWithText(
        TextFormField,
        'Price for Velora Prime (UGX)',
      );
      await tester.ensureVisible(price);
      await tester.enterText(price, '100');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, isEmpty);

      await tester.enterText(price, '20,000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved, [
        {'price_ugx': 20000, 'for_sale': true, 'featured': true},
      ]);

      await tester.ensureVisible(find.text('Failed').first);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Failed'));
      await tester.pumpAndSettle();
      expect(api.requests.last.url.queryParameters['state'], 'failed');
    });

    testWidgets('a completed payment is marked refunded only once confirmed', (
      tester,
    ) async {
      final api = FakeApi()..isAdmin = true;
      var state = 'completed';
      final refunds = <String>[];
      api.admin.addAll({
        'GET /drafts': (_) => json({'editions': []}),
        'GET /billing/metrics': (_) => json({
          'active_subscribers': 1,
          'by_plan': [],
          'revenue_30_days_ugx': 6000,
          'completed_30_days': 1,
          'failed_30_days': 0,
          'reversed_30_days': 0,
          'refunded_30_days': state == 'refunded' ? 1 : 0,
          'abandoned_30_days': 0,
          'pending_now': 0,
          'active_devices': 1,
          'live_sessions': 0,
        }),
        'GET /pass-plans': (_) => json([]),
        'GET /billing/payments': (_) => json([
          {
            'id': 'pay-1',
            'user_id': 'u2',
            'plan_id': 'velora_start',
            'plan_name': 'Velora Start',
            'amount_ugx': 6000,
            'state': state,
            'created_at': '2026-11-22T09:23:00Z',
            'completed_at': '2026-11-22T09:23:52Z',
            'payment_method': 'MTNUG',
            'provider_reference': 'ABC',
            'tracking_id': 't',
            'reason': state == 'refunded' ? 'Refunded in full' : null,
            'contact': 'v***@example.com',
          },
        ]),
        'POST /billing/payments/pay-1/refund': (_) {
          refunds.add('pay-1');
          state = 'refunded';
          return json({
            'id': 'pay-1',
            'user_id': 'u2',
            'plan_id': 'velora_start',
            'plan_name': 'Velora Start',
            'amount_ugx': 6000,
            'state': 'refunded',
            'created_at': '2026-11-22T09:23:00Z',
            'completed_at': '2026-11-22T09:23:52Z',
            'payment_method': 'MTNUG',
            'provider_reference': 'ABC',
            'tracking_id': 't',
            'reason': 'Refunded in full',
            'contact': 'v***@example.com',
          });
        },
        'GET /billing/subscribers': (_) => json([]),
        'GET /billing/plan-changes': (_) => json([]),
      });
      await pumpApp(tester, api, signedIn: true);
      await goTo(tester, 'Admin');
      await tester.tap(find.text('Subscriptions'));
      await tester.pumpAndSettle();

      final button = find.byKey(const ValueKey('refund-pay-1'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.text('Mark this payment refunded?'), findsOneWidget);
      expect(
        find.textContaining('UGX 6,000 in full on Pesapal'),
        findsOneWidget,
      );
      expect(find.textContaining('v***@example.com, and'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(refunds, isEmpty);

      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Mark refunded'),
        ),
      );
      await tester.pumpAndSettle();

      expect(refunds, ['pay-1']);
      expect(find.text('Marked refunded. Its pass has ended.'), findsOneWidget);
      expect(find.byKey(const ValueKey('refund-pay-1')), findsNothing);
      expect(find.textContaining('Refunded in full'), findsOneWidget);
    });
  });
}

Map<String, Object?> jsonBody(http.Request request) =>
    jsonDecode(request.body) as Map<String, Object?>;
