import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:veloraug/admin/account_billing_screen.dart';
import 'package:veloraug/admin/subscriptions_view.dart' show billingSearchDelay;

import 'support.dart';

Map<String, Object?> jsonBody(http.Request request) =>
    jsonDecode(request.body) as Map<String, Object?>;

Map<String, Object?> payment(
  String id, {
  String state = 'completed',
  String plan = 'Velora Start',
  int amount = 6000,
  String? reason,
  String? tracking = 'track-1',
}) => {
  'id': id,
  'user_id': 'u2',
  'plan_id': 'velora_start',
  'plan_name': plan,
  'amount_ugx': amount,
  'state': state,
  'created_at': '2026-11-22T09:23:00Z',
  'completed_at': state == 'completed' ? '2026-11-22T09:23:52Z' : null,
  'payment_method': 'MTNUG',
  'provider_reference': state == 'completed' ? 'ABC' : null,
  'tracking_id': tracking,
  'reason': reason,
  'contact': 'v***@example.com',
};

Map<String, Object?> detail(Map<String, Object?> pay, List<String> steps) => {
  'payment': pay,
  'timeline': [
    for (final step in steps)
      {'step': step, 'at': step == 'sent' ? null : '2026-11-22T09:23:00Z'},
  ],
  'pass': pay['state'] == 'completed'
      ? {
          'id': 'pass-1',
          'payment_id': pay['id'],
          'plan_id': 'velora_start',
          'plan_name': 'Velora Start',
          'starts_at': '2026-11-22T09:23:52Z',
          'ends_at': '2026-11-29T09:23:52Z',
          'max_devices': 1,
          'max_streams': 1,
          'revoked_at': null,
          'grant_id': null,
        }
      : null,
  'refunded_at': null,
  'refunded_by': null,
};

Map<String, Object?> metrics({int pending = 0}) => {
  'active_subscribers': 4,
  'by_plan': [
    {'plan_id': 'velora_prime', 'plan_name': 'Velora Prime', 'subscribers': 4},
  ],
  'revenue_today_ugx': 12000,
  'revenue_7_days_ugx': 30000,
  'revenue_30_days_ugx': 72000,
  'completed_30_days': 3,
  'failed_30_days': 1,
  'reversed_30_days': 0,
  'refunded_30_days': 0,
  'abandoned_30_days': 0,
  'pending_now': pending,
  'active_devices': 5,
  'live_sessions': 2,
  'success_rate_30_days': 0.75,
  'ending_soon': 2,
  'granted_30_days': 1,
  'payment_timeout_minutes': 60,
  'daily': [
    for (var d = 1; d <= 30; d++)
      {
        'day': '2026-11-${d.toString().padLeft(2, '0')}',
        'revenue_ugx': d == 26 ? 12000 : 0,
        'completed': d == 26 ? 2 : 0,
      },
  ],
};

/// An admin API for the Subscriptions tab. Records each transactions
/// query; [payments] is what transactions answers.
(FakeApi, List<Map<String, String>>) billingApi({
  List<Map<String, Object?>>? payments,
  List<Map<String, Object?>> subscribers = const [],
}) {
  final api = FakeApi()..isAdmin = true;
  final asked = <Map<String, String>>[];
  final rows = payments ?? [payment('pay-1')];
  api.admin.addAll({
    'GET /drafts': (_) => json({'editions': []}),
    'GET /billing/metrics': (_) => json(metrics()),
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
    'GET /billing/transactions': (request) {
      asked.add(request.url.queryParameters);
      return json({'payments': rows, 'total': rows.length});
    },
    'GET /billing/subscribers': (request) {
      asked.add({'subscribers': '', ...request.url.queryParameters});
      return json(subscribers);
    },
    'GET /billing/plan-changes': (_) => json([]),
  });
  return (api, asked);
}

Future<void> openSubscriptions(
  WidgetTester tester,
  FakeApi api, {
  Size size = const Size(1200, 1600),
}) async {
  await pumpApp(tester, api, signedIn: true, size: size);
  await goTo(tester, 'Admin');
  await tester.ensureVisible(find.widgetWithText(Tab, 'Subscriptions'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(Tab, 'Subscriptions'));
  await tester.pumpAndSettle();
}

Future<void> openPayment(WidgetTester tester, String text) async {
  final tile = find.textContaining(text).first;
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the overview shows money, success, passes ending and a chart', (
    tester,
  ) async {
    final (api, _) = billingApi();
    await openSubscriptions(tester, api);

    expect(find.textContaining('not paid within 60 minutes'), findsOneWidget);
    for (final (value, label) in [
      ('UGX 12,000', 'Taken today'),
      ('UGX 30,000', 'Taken in 7 days'),
      ('UGX 72,000', 'Revenue, last 30 days'),
      ('75%', 'Paid, of payments in 30 days'),
      ('2', 'Passes ending in 3 days'),
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
      expect(find.text(value), findsWidgets, reason: value);
    }
    expect(find.text('Subscribers by plan: Velora Prime: 4'), findsOneWidget);
    expect(find.text('Money taken each day, last 30 days'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'Nov 26: UGX 12,000, 2 payments')),
      findsOneWidget,
    );

    await tester.ensureVisible(find.text('Show as table'));
    await tester.tap(find.text('Show as table'));
    await tester.pumpAndSettle();
    expect(find.text('2 payments'), findsOneWidget);
    expect(find.text('Show as chart'), findsOneWidget);
  });

  testWidgets('plans, prices and sale flags are shown, checked and saved', (
    tester,
  ) async {
    final (api, asked) = billingApi();
    final saved = <Map<String, Object?>>[];
    api.admin['PATCH /pass-plans/velora_prime'] = (request) {
      saved.add(jsonBody(request));
      return json({});
    };
    await openSubscriptions(tester, api);

    expect(find.text('Legacy pass, kept for history'), findsOneWidget);
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
    expect(asked, isNotEmpty);
  });

  testWidgets('payments are filtered, searched and exported on the server', (
    tester,
  ) async {
    final (api, asked) = billingApi(
      payments: [
        payment('pay-1'),
        payment('pay-2', state: 'abandoned', reason: 'Not paid within 1 hour'),
      ],
    );
    api.admin['GET /billing/transactions.csv'] = (request) {
      asked.add({'csv': '', ...request.url.queryParameters});
      return http.Response('created_at,state\n', 200);
    };
    await openSubscriptions(tester, api);

    expect(find.text('2 payments'), findsOneWidget);
    expect(find.text('Expired'), findsWidgets);
    expect(find.text('Not paid within 1 hour'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Failed'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Failed'));
    await tester.pumpAndSettle();
    expect(asked.last, {'state': 'failed'});

    await tester.enterText(
      find.widgetWithText(TextField, 'Search payments'),
      '0772',
    );
    await tester.pump(billingSearchDelay);
    await tester.pumpAndSettle();
    expect(asked.last, {'state': 'failed', 'q': '0772'});

    await tester.ensureVisible(find.text('Export CSV'));
    await tester.tap(find.text('Export CSV'));
    await tester.pumpAndSettle();
    expect(asked.last, {'csv': '', 'state': 'failed', 'q': '0772'});
    // Tests don't run in a browser.
    expect(find.text('Exporting works in the browser only.'), findsOneWidget);
  });

  testWidgets('a payment shows its steps, and is marked refunded once '
      'confirmed', (tester) async {
    var state = 'completed';
    final (api, _) = billingApi();
    api.admin['GET /billing/payments/pay-1'] = (_) => json(
      detail(payment('pay-1', state: state), [
        'started',
        'sent',
        'completed',
        if (state == 'refunded') 'refunded',
      ]),
    );
    final refunds = <String>[];
    api.admin['POST /billing/payments/pay-1/refund'] = (_) {
      refunds.add('pay-1');
      state = 'refunded';
      return json(payment('pay-1', state: 'refunded'));
    };
    await openSubscriptions(tester, api);

    await openPayment(tester, 'Velora Start · UGX 6,000');
    expect(find.text('What happened'), findsOneWidget);
    expect(find.text('Started in the app'), findsOneWidget);
    expect(find.text('Sent to Pesapal'), findsOneWidget);
    expect(find.text('time not recorded'), findsOneWidget);
    expect(find.textContaining('Its pass:'), findsOneWidget);
    expect(find.text('track-1'), findsOneWidget);

    await tester.tap(find.text('Mark refunded'));
    await tester.pumpAndSettle();
    expect(find.text('Mark this payment refunded?'), findsOneWidget);
    expect(find.textContaining('UGX 6,000 in full on Pesapal'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(refunds, isEmpty);

    await tester.tap(find.text('Mark refunded'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Mark refunded'),
      ),
    );
    await tester.pumpAndSettle();

    expect(refunds, ['pay-1']);
    expect(find.text('Marked refunded'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Mark refunded'), findsNothing);
  });

  testWidgets('an expired payment is re-checked with Pesapal', (tester) async {
    var state = 'abandoned';
    final (api, _) = billingApi(
      payments: [payment('pay-1', state: 'abandoned')],
    );
    api.admin['GET /billing/payments/pay-1'] = (_) => json(
      detail(payment('pay-1', state: state), ['started', 'sent', 'expired']),
    );
    api.admin['POST /billing/payments/pay-1/recheck'] = (_) {
      state = 'completed';
      return json(detail(payment('pay-1'), ['started', 'sent', 'completed']));
    };
    await openSubscriptions(tester, api);

    await openPayment(tester, 'Velora Start · UGX 6,000');
    expect(find.text('Expired, not paid'), findsOneWidget);
    expect(find.textContaining('If the viewer says they paid'), findsOneWidget);
    await tester.tap(find.text('Re-check with Pesapal'));
    await tester.pumpAndSettle();

    expect(api.adminCalls, contains('POST /billing/payments/pay-1/recheck'));
    expect(find.text('Pesapal checked: Paid'), findsOneWidget);
    expect(find.text('Paid'), findsWidgets);
  });

  testWidgets('subscribers are searched, and those ending soon found', (
    tester,
  ) async {
    final (api, asked) = billingApi();
    await openSubscriptions(tester, api);

    await tester.ensureVisible(
      find.widgetWithText(TextField, 'Search by email, phone or account ID'),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Search by email, phone or account ID'),
      'viewer@',
    );
    await tester.pump(billingSearchDelay);
    await tester.pumpAndSettle();
    expect(asked.last, {'subscribers': '', 'q': 'viewer@'});

    await tester.tap(find.widgetWithText(FilterChip, 'Ending within 3 days'));
    await tester.pumpAndSettle();
    expect(asked.last, {
      'subscribers': '',
      'q': 'viewer@',
      'ending_within_days': '3',
    });
  });

  testWidgets("an account's passes and free days, and giving more", (
    tester,
  ) async {
    final (api, _) = billingApi(
      subscribers: [
        {
          'user_id': 'u2',
          'plan_id': 'velora_prime',
          'plan_name': 'Velora Prime',
          'starts_at': '2026-11-20T10:00:00Z',
          'ends_at': '2026-12-20T10:00:00Z',
          'max_devices': 1,
          'active_devices': 1,
          'contact': 'v***@example.com',
        },
      ],
    );
    var given = false;
    api.admin['GET /billing/users/u2'] = (_) => json({
      'user_id': 'u2',
      'passes': [
        {
          'id': 'pass-1',
          'payment_id': 'pay-1',
          'plan_id': 'velora_prime',
          'plan_name': 'Velora Prime',
          'starts_at': '2026-11-20T10:00:00Z',
          'ends_at': '2099-12-20T10:00:00Z',
          'max_devices': 1,
          'max_streams': 1,
          'revoked_at': null,
          'grant_id': null,
        },
      ],
      'payments': [payment('pay-1')],
      'grants': [
        if (given)
          {
            'id': 'g1',
            'plan_id': 'velora_prime',
            'plan_name': 'Velora Prime',
            'days': 5,
            'reason': 'Sorry for the outage',
            'granted_by': 'a1',
            'granted_by_email': 'boss@example.com',
            'created_at': '2026-11-26T10:00:00Z',
          },
      ],
      'devices': [],
      'live_sessions': [],
    });
    final sent = <Map<String, Object?>>[];
    api.admin['POST /billing/users/u2/grants'] = (request) {
      sent.add(jsonBody(request));
      given = true;
      return json({
        'id': 'pass-2',
        'payment_id': null,
        'plan_id': 'velora_prime',
        'plan_name': 'Velora Prime',
        'starts_at': '2099-12-20T10:00:00Z',
        'ends_at': '2099-12-25T10:00:00Z',
        'max_devices': 1,
        'max_streams': 1,
        'revoked_at': null,
        'grant_id': 'g1',
      }, 201);
    };
    await openSubscriptions(tester, api);

    await tester.ensureVisible(find.byKey(const ValueKey('subscriber-u2')));
    await tester.tap(find.byKey(const ValueKey('subscriber-u2')));
    await tester.pumpAndSettle();
    expect(find.byType(AccountBillingScreen), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.textContaining('Bought'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Give free days').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Days, 1 to 90'),
      '5',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Give free days').last);
    await tester.pumpAndSettle();
    // A reason is needed.
    expect(sent, isEmpty);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Why'),
      'Sorry for the outage',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Give free days').last);
    await tester.pumpAndSettle();

    expect(sent, [
      {'plan_id': 'velora_prime', 'days': 5, 'reason': 'Sorry for the outage'},
    ]);
    expect(find.textContaining('Free days given:'), findsOneWidget);
    expect(find.text('5 days of Velora Prime'), findsOneWidget);
    expect(
      find.textContaining('Sorry for the outage · by boss@example.com'),
      findsOneWidget,
    );
  });

  testWidgets('fits a narrow phone with large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final (api, _) = billingApi();
    api.admin['GET /billing/payments/pay-1'] = (_) =>
        json(detail(payment('pay-1'), ['started', 'sent', 'completed']));
    await openSubscriptions(tester, api, size: const Size(320, 4000));
    expect(tester.takeException(), isNull);

    await openPayment(tester, 'Velora Start');
    expect(tester.takeException(), isNull);
  });
}
