import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/widgets/maintenance_banner.dart';
import 'package:veloraug/widgets/velora_button.dart';

import 'admin_screens_test.dart' show adminApi, settingsJson;
import 'support.dart';

/// An admin API whose settings are [values], and records each PATCH.
(FakeApi, List<Map<String, Object?>>) settingsApi({
  Map<String, Object?> values = const {},
}) {
  final api = adminApi();
  final saved = <Map<String, Object?>>[];
  var current = {...values};
  api.admin['GET /settings'] = (_) => json(settingsJson(values: current));
  api.admin['PATCH /settings'] = (request) {
    final changes = jsonDecode(request.body) as Map<String, Object?>;
    saved.add(changes);
    current = {...current, ...changes};
    return json(settingsJson(values: current));
  };
  return (api, saved);
}

Future<void> openSettings(
  WidgetTester tester,
  FakeApi api, {
  Size size = const Size(1200, 2400),
}) async {
  await pumpApp(tester, api, signedIn: true, size: size);
  await goTo(tester, 'Admin');
  await tester.ensureVisible(find.widgetWithText(Tab, 'Settings'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(Tab, 'Settings'));
  await tester.pumpAndSettle();
}

Finder field(String label) => find.widgetWithText(TextField, label);

Future<void> type(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(field(label));
  await tester.pumpAndSettle();
  await tester.enterText(field(label), text);
  await tester.pump();
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(VeloraButton, 'Save').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows every part, and what the server is set up with', (
    tester,
  ) async {
    final (api, _) = settingsApi();
    await openSettings(tester, api);

    for (final part in [
      'Support contacts',
      'Maintenance',
      'Payments',
      'Viewers',
      'Content defaults',
      'Plans and pricing',
      'About',
    ]) {
      expect(find.widgetWithText(ActionChip, part), findsOneWidget);
    }
    expect(find.text('Pesapal, sandbox, for testing'), findsOneWidget);
    expect(find.text('50 GB a file'), findsOneWidget);
    expect(find.text('360p, 480p, 720p, 1080p'), findsOneWidget);
    expect(find.text('0019'), findsOneWidget);
    expect(
      find.textContaining("Roles with fewer rights aren't set up yet"),
      findsOneWidget,
    );
    // Nothing changed: nothing to save.
    expect(find.text('Discard'), findsNothing);
  });

  testWidgets('only changed settings are saved, from the bar at the bottom', (
    tester,
  ) async {
    final (api, saved) = settingsApi();
    await openSettings(tester, api);

    await type(tester, 'Support WhatsApp', '+256 772 123 456');
    await type(tester, 'Remind viewers before their pass ends, in days', '5');
    expect(find.text("Changes in 2 parts aren't saved"), findsOneWidget);
    expect(find.text('Not saved'), findsNWidgets(2));

    await save(tester);

    expect(saved, [
      {'support_whatsapp': '+256 772 123 456', 'pass_reminder_days': 5},
    ]);
    expect(find.text('2 settings saved'), findsOneWidget);
    expect(find.text('Discard'), findsNothing);
  });

  testWidgets('a part undoes its changes, and Discard undoes them all', (
    tester,
  ) async {
    final (api, saved) = settingsApi(values: {'support_email': 'a@b.ug'});
    await openSettings(tester, api);

    await type(tester, 'Support email', 'new@veloraug.ug');
    await tester.ensureVisible(find.text('Undo changes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Undo changes'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field('Support email')).controller!.text,
      'a@b.ug',
    );
    expect(find.text('Discard'), findsNothing);

    await type(tester, 'Support email', 'new@veloraug.ug');
    await tester.tap(find.widgetWithText(VeloraButton, 'Discard'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(field('Support email')).controller!.text,
      'a@b.ug',
    );
    expect(saved, isEmpty);
  });

  testWidgets('wrong values are named, here and by the server', (tester) async {
    final (api, saved) = settingsApi();
    await openSettings(tester, api);

    await type(tester, 'Support phone', '0772123456');
    await type(tester, 'Give up on unpaid payments after, in minutes', '2');
    await save(tester);
    expect(saved, isEmpty);
    expect(find.text('Give the whole number, starting +256'), findsOneWidget);
    expect(find.text('Use a whole number from 5 to 1440.'), findsOneWidget);
    expect(
      find.text('Some settings need fixing first: see the red notes.'),
      findsOneWidget,
    );

    await type(tester, 'Support phone', '+256772123456');
    await type(tester, 'Give up on unpaid payments after, in minutes', '30');
    api.admin['PATCH /settings'] = (_) => json({
      'detail': {
        'message': "Some settings weren't saved",
        'errors': {'support_phone': "That isn't a phone number"},
      },
    }, 400);
    await save(tester);
    expect(find.text("That isn't a phone number"), findsOneWidget);
    // In the bar, which no snack bar covers.
    expect(
      find.text('Some settings need fixing first: see the red notes.'),
      findsOneWidget,
    );
  });

  testWidgets("the payment timeout goes back to the server's", (tester) async {
    final (api, saved) = settingsApi(values: {'payment_timeout_minutes': 30});
    await openSettings(tester, api);

    final payments = find.ancestor(
      of: find.text('Give up on unpaid payments after, in minutes'),
      matching: find.byType(Card),
    );
    await tester.ensureVisible(
      find.descendant(of: payments, matching: find.text('Use defaults')),
    );
    await tester.tap(
      find.descendant(of: payments, matching: find.text('Use defaults')),
    );
    await tester.pumpAndSettle();
    await save(tester);

    expect(saved, [
      {'payment_timeout_minutes': null},
    ]);
  });

  testWidgets('maintenance shows a preview, and is saved with its message', (
    tester,
  ) async {
    final (api, saved) = settingsApi();
    await openSettings(tester, api);

    await tester.ensureVisible(find.text('Maintenance mode'));
    await tester.tap(find.text('Maintenance mode'));
    await tester.pumpAndSettle();
    expect(find.text('What viewers will see'), findsOneWidget);
    expect(find.byType(MaintenanceBanner), findsOneWidget);
    await type(tester, 'Message for viewers', 'Back by 6pm.');
    expect(
      find.descendant(
        of: find.byType(MaintenanceBanner),
        matching: find.text('Back by 6pm.'),
      ),
      findsOneWidget,
    );
    await save(tester);

    expect(saved, [
      {'maintenance': true, 'maintenance_message': 'Back by 6pm.'},
    ]);
  });

  testWidgets('changes are kept while other tabs are visited', (tester) async {
    final (api, _) = settingsApi();
    await openSettings(tester, api);
    await type(tester, 'Support email', 'help@veloraug.ug');

    await tester.tap(find.widgetWithText(Tab, 'Drafts'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(Tab, 'Settings'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(field('Support email')).controller!.text,
      'help@veloraug.ug',
    );
    expect(find.text('Discard'), findsOneWidget);
  });

  testWidgets('fits a narrow phone with large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final (api, _) = settingsApi(values: {'maintenance': true});
    await openSettings(tester, api, size: const Size(320, 6000));
    await type(tester, 'Support email', 'help@veloraug.ug');

    expect(tester.takeException(), isNull);
  });

  group('in the app', () {
    testWidgets('viewers see the maintenance notice above every screen', (
      tester,
    ) async {
      final api = FakeApi()
        ..status = {
          'maintenance': true,
          'maintenance_message': 'Back by 6pm.',
          'support_email': '',
          'support_phone': '',
          'support_whatsapp': '',
        };
      await pumpApp(tester, api, settle: false);
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(MaintenanceBanner), findsOneWidget);
      expect(find.text('Back by 6pm.'), findsOneWidget);
      expect(find.text('VeloraUG is being worked on'), findsOneWidget);
    });

    testWidgets('no notice without maintenance, or from an older server', (
      tester,
    ) async {
      await pumpApp(tester, FakeApi());
      expect(find.byType(MaintenanceBanner), findsNothing);
    });

    testWidgets("viewers' Settings lists the support contacts that are set", (
      tester,
    ) async {
      final api = FakeApi()
        ..status = {
          'maintenance': false,
          'maintenance_message': '',
          'support_email': 'help@veloraug.ug',
          'support_phone': '',
          'support_whatsapp': '+256772123456',
        };
      await pumpApp(tester, api, signedIn: true, size: const Size(400, 1800));
      await goTo(tester, 'Account');
      final settings = find.text('Settings').first;
      await tester.ensureVisible(settings);
      await tester.pumpAndSettle();
      await tester.tap(settings);
      await tester.pumpAndSettle();

      expect(find.text('Help and support'), findsOneWidget);
      expect(find.text('Chat on WhatsApp'), findsOneWidget);
      expect(find.text('+256772123456'), findsOneWidget);
      expect(find.text('Email us'), findsOneWidget);
      expect(find.text('Call us'), findsNothing);
    });
  });
}
