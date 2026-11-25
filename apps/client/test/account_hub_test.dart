import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/widgets/empty_state.dart';
import 'package:veloraug/widgets/status_badge.dart';

import 'support.dart';

Map<String, Object?> activePass({String name = 'Velora Prime'}) => {
  'active': true,
  'checking': false,
  'current_ends_at': '2030-01-31T09:30:00Z',
  'ends_at': '2030-01-31T09:30:00Z',
  'current': {
    'id': 'p1',
    'plan_id': 'velora_prime',
    'plan_name': name,
    'starts_at': '2026-11-01T09:30:00Z',
    'ends_at': '2030-01-31T09:30:00Z',
    'max_devices': 1,
    'max_streams': 1,
  },
  'queued': <Object>[],
};

Map<String, Object?> device({String label = 'Kitchen laptop'}) => {
  'id': 'd1',
  'label': label,
  'platform': 'android',
  'registered_at': '2026-11-01T10:00:00Z',
  'last_active_at': '2026-11-20T10:00:00Z',
  'current': true,
};

Map<String, Object?> payment() => {
  'id': 'pay-9',
  'plan_id': 'velora_prime',
  'plan_name': 'Velora Prime',
  'amount_ugx': 18000,
  'state': 'completed',
  'created_at': '2026-11-20T10:00:00Z',
  'completed_at': '2026-11-20T10:01:00Z',
  'provider_reference': 'MTN123456789',
};

Map<String, Object?> watched({
  String id = 'i1',
  String title = 'Fast and Furious: Tokyo Drift',
  bool episode = false,
}) => {
  'item_id': id,
  'edition': card('e-$id', kind: episode ? 'series' : 'movie', title: title),
  'season': episode ? 1 : null,
  'episode': episode ? 2 : null,
  'episode_title': episode ? 'The Crown' : null,
  'last_watched_at': '2026-11-21T10:00:00Z',
  'resume_seconds': 1500,
};

Future<void> openHub(WidgetTester tester, FakeApi api, {Size? size}) async {
  await pumpApp(
    tester,
    api,
    signedIn: true,
    size: size ?? const Size(400, 1800),
  );
  await goTo(tester, 'Account');
}

Future<void> open(WidgetTester tester, String row) async {
  final finder = find.text(row).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String? subtitleOf(WidgetTester tester, String key) {
  final tile = tester.widget<ListTile>(
    find.descendant(
      of: find.byKey(ValueKey(key)),
      matching: find.byType(ListTile),
    ),
  );
  return (tile.subtitle as Text?)?.data;
}

void main() {
  group('the hub at a glance', () {
    testWidgets('the Plans row says the plan and the time left', (
      tester,
    ) async {
      await openHub(tester, FakeApi()..myPass = activePass());

      expect(subtitleOf(tester, 'row-plans'), startsWith('Velora Prime · '));
      expect(subtitleOf(tester, 'row-plans'), endsWith('days left'));
    });

    testWidgets('without a plan it offers one', (tester) async {
      await openHub(tester, FakeApi());

      expect(subtitleOf(tester, 'row-plans'), 'No plan · Choose a plan');
    });

    testWidgets("if the plan can't load, the row keeps its usual help", (
      tester,
    ) async {
      final api = FakeApi()
        ..intercept = (request) => request.url.path == '/api/v1/me/pass'
            ? Future.error(Exception('offline'))
            : null;
      await openHub(tester, api);

      expect(
        subtitleOf(tester, 'row-plans'),
        'Your plan, when it ends, renewing or changing',
      );
    });

    testWidgets('Notifications shows how many are new, and none at zero', (
      tester,
    ) async {
      final api = FakeApi()..inbox = {'notifications': <Object>[], 'unread': 2};
      await openHub(tester, api);

      final row = find.byKey(const ValueKey('row-notifications'));
      expect(
        find.descendant(of: row, matching: find.text('2 new')),
        findsOneWidget,
      );

      api.inbox = {'notifications': <Object>[], 'unread': 0};
      // Back from a page, the glance is fresh.
      await open(tester, 'Notifications');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: row, matching: find.byType(StatusBadge)),
        findsNothing,
      );
    });

    testWidgets('the card names the viewer, with their email under it', (
      tester,
    ) async {
      await openHub(tester, FakeApi()..displayName = 'Willis');

      expect(find.text('Willis'), findsOneWidget);
      expect(find.text('owner@example.test'), findsOneWidget);
    });

    testWidgets('without a display name, the email is the title', (
      tester,
    ) async {
      await openHub(tester, FakeApi());

      expect(find.text('owner@example.test'), findsOneWidget);
      expect(find.text("You're signed in"), findsOneWidget);
    });

    testWidgets('Sign out is at the foot, below Danger zone', (tester) async {
      await openHub(tester, FakeApi());

      final signOut = find.widgetWithText(OutlinedButton, 'Sign out');
      expect(signOut, findsOneWidget);
      expect(
        tester.getTopLeft(signOut).dy,
        greaterThan(tester.getTopLeft(find.text('Danger zone')).dy),
      );
    });

    testWidgets('My devices is under Membership; Account status is gone', (
      tester,
    ) async {
      await openHub(tester, FakeApi());

      expect(
        tester.getTopLeft(find.text('My devices')).dy,
        lessThan(tester.getTopLeft(find.text('Your library')).dy),
      );
      expect(find.text('Account status'), findsNothing);
    });
  });

  group('the pages', () {
    testWidgets('Profile has the sign-in card from Account status', (
      tester,
    ) async {
      await openHub(tester, FakeApi());
      await open(tester, 'Profile');

      expect(find.text('Sign-in'), findsOneWidget);
      expect(find.text('owner@example.test'), findsOneWidget);
    });

    testWidgets('My devices: one heading, the name full width, actions under '
        'it', (tester) async {
      final api = FakeApi()..devices = [device()];
      await openHub(tester, api);
      await open(tester, 'My devices');

      // The bar and the page's heading; the card has no title of its own.
      expect(find.text('My devices'), findsNWidgets(2));
      expect(
        tester.getTopLeft(find.text('Rename')).dy,
        greaterThan(tester.getTopLeft(find.text('Kitchen laptop')).dy),
      );
    });

    testWidgets('My devices with none says so', (tester) async {
      await openHub(tester, FakeApi());
      await open(tester, 'My devices');

      expect(find.widgetWithText(EmptyState, 'No devices yet'), findsOneWidget);
    });

    testWidgets('Payments: one fact per line, and an empty state', (
      tester,
    ) async {
      final api = FakeApi()..payments = [payment()];
      await openHub(tester, api);
      await open(tester, 'Payments');

      expect(find.text('Payments'), findsNWidgets(2));
      expect(find.text('Velora Prime'), findsOneWidget);
      expect(find.text('UGX 18,000'), findsOneWidget);
      expect(find.text('Ref. MTN123456789'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      api.payments = [];
      await open(tester, 'Payments');
      expect(
        find.widgetWithText(EmptyState, 'No payments yet'),
        findsOneWidget,
      );
    });

    testWidgets('Watch history: what it is, and Resume under the title', (
      tester,
    ) async {
      final api = FakeApi()
        ..history = [
          watched(),
          watched(id: 'i2', title: 'Kabaka', episode: true),
        ];
      await openHub(tester, api);
      await open(tester, 'Watch history');

      expect(find.text('Movie · Luganda · VJ Junior'), findsOneWidget);
      expect(find.text('The Crown · Luganda · VJ Junior'), findsOneWidget);
      final title = find.text('Fast and Furious: Tokyo Drift');
      expect(
        tester.getTopLeft(find.text('Resume').first).dy,
        greaterThan(tester.getTopLeft(title).dy),
      );
    });

    testWidgets('Settings: push is one line, and devices moved out', (
      tester,
    ) async {
      await openHub(tester, FakeApi());
      await open(tester, 'Settings');

      expect(
        find.text('Coming soon. Notifications still arrive in your inbox.'),
        findsOneWidget,
      );
      expect(find.text('My devices'), findsNothing);
    });
  });

  // Each page at 320 pixels, with long text: nothing overflows, and the
  // titles keep a readable width.
  for (final scale in [1.0, 2.0]) {
    group('at 320 pixels and text size $scale', () {
      FakeApi rich() => FakeApi()
        ..myPass = activePass()
        ..displayName = 'Willis Karugaba'
        ..inbox = {'notifications': <Object>[], 'unread': 3}
        ..devices = [device(label: "Willis's Samsung Galaxy A54")]
        ..payments = [payment()]
        ..history = [watched()];

      for (final (page, title) in [
        (null, null),
        ('Plans & membership', null),
        ('Payments', null),
        ('My devices', "Willis's Samsung Galaxy A54"),
        ('Watch List', null),
        ('Watch history', 'Fast and Furious: Tokyo Drift'),
        ('Notifications', null),
        ('Profile', null),
        ('Settings', null),
      ]) {
        testWidgets(page ?? 'the hub', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await openHub(tester, rich(), size: const Size(320, 900));
          if (page != null) await open(tester, page);

          expect(tester.takeException(), isNull);
          if (title != null) {
            // At least half the screen: not squeezed beside buttons.
            expect(
              tester.getSize(find.text(title).first).width,
              greaterThan(160),
            );
          }
        });
      }
    });
  }
}
