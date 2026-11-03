import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/app.dart';
import 'package:veloraug/showcase/design_system_showcase.dart';
import 'package:veloraug/showcase/showcase_gate.dart';
import 'package:veloraug/widgets/status_badge.dart';

const _tabs = [
  'Tokens',
  'Actions',
  'Fields',
  'Movies',
  'Feedback',
  'Layouts',
  'Text size',
];

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const DesignSystemShowcase());
  await tester.pump();
}

// Some tabs have running placeholders, so pumpAndSettle would never return.
// Tabs may be scrolled out of view on a narrow screen, so this doesn't tap them.
Future<void> _openTab(WidgetTester tester, String name) async {
  DefaultTabController.of(tester.element(find.byType(TabBar))).index = _tabs
      .indexOf(name);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  group('gate', () {
    test('is off unless asked for', () {
      expect(showcaseEnabled, isFalse);
    });

    test('is a compile-time constant that requires a debug build', () {
      final source = File('lib/showcase/showcase_gate.dart')
          .readAsStringSync()
          .replaceAll(RegExp(r'\s+'), ' ');
      expect(
        source,
        contains(
          "const bool showcaseEnabled = kDebugMode && "
          "bool.fromEnvironment('SHOW_DESIGN_SYSTEM');",
        ),
      );
      expect(kDebugMode, isTrue);
    });

    test('main opens the normal app by default', () {
      final source = File('lib/main.dart').readAsStringSync();
      expect(source, contains('showcaseEnabled'));
      expect(source, contains('const VeloraApp()'));
    });

    testWidgets('the normal app has no showcase', (tester) async {
      await tester.pumpWidget(const VeloraApp());
      await tester.pumpAndSettle();
      expect(find.byType(DesignSystemShowcase), findsNothing);
      expect(find.textContaining('Design system'), findsNothing);
    });
  });

  group('showcase', () {
    testWidgets('says on every tab that it is demonstration content', (
      tester,
    ) async {
      await _pump(tester, const Size(1200, 800));
      for (final name in _tabs) {
        await _openTab(tester, name);
        expect(find.textContaining('Development only'), findsOneWidget);
        expect(find.textContaining('All titles and results'), findsOneWidget);
      }
    });

    for (final (label, size) in const [
      ('320 pixels wide', Size(320, 640)),
      ('landscape phone', Size(640, 320)),
      ('1280 pixels wide', Size(1280, 800)),
    ]) {
      testWidgets('no tab overflows at $label', (tester) async {
        await _pump(tester, size);
        for (final name in _tabs) {
          await _openTab(tester, name);
          expect(tester.takeException(), isNull, reason: name);
        }
      });
    }

    testWidgets('no tab overflows with large text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _pump(tester, const Size(360, 700));
      for (final name in _tabs) {
        await _openTab(tester, name);
        expect(tester.takeException(), isNull, reason: name);
      }
    });

    testWidgets('shows every status tone', (tester) async {
      await _pump(tester, const Size(1200, 800));
      await _openTab(tester, 'Feedback');
      for (final tone in StatusTone.values) {
        expect(
          find.byWidgetPredicate((w) => w is StatusBadge && w.tone == tone),
          findsOneWidget,
        );
      }
    });

    testWidgets('demonstration form shows errors and sends nothing', (
      tester,
    ) async {
      await _pump(tester, const Size(1200, 1000));
      await _openTab(tester, 'Fields');
      await tester.tap(find.text('Validate'));
      await tester.pump();
      expect(find.text('Enter an email address.'), findsOneWidget);
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
    });

    testWidgets('the themed dialog opens and closes', (tester) async {
      await _pump(tester, const Size(1200, 2400));
      await _openTab(tester, 'Actions');
      await tester.tap(find.text('Open dialog'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Demonstration dialog'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Demonstration dialog'), findsNothing);
    });

    testWidgets('the reduced motion switch stops the spinner', (tester) async {
      await _pump(tester, const Size(1200, 2000));
      await _openTab(tester, 'Feedback');
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.text('Simulate reduced motion'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.hourglass_top), findsOneWidget);
    });

    testWidgets('layouts tab draws narrow, medium and wide examples', (
      tester,
    ) async {
      await _pump(tester, const Size(1400, 3000));
      await _openTab(tester, 'Layouts');
      expect(find.text('Narrow: 360 pixels wide'), findsOneWidget);
      expect(find.text('Medium: 768 pixels wide'), findsOneWidget);
      expect(find.text('Wide: 1280 pixels wide'), findsOneWidget);
      expect(find.text('Demonstration screen'), findsNWidgets(3));
    });

    testWidgets('text size tab shows each scale', (tester) async {
      await _pump(tester, const Size(1200, 3000));
      await _openTab(tester, 'Text size');
      expect(find.text('Text at 100%'), findsOneWidget);
      expect(find.text('Text at 130%'), findsOneWidget);
      expect(find.text('Text at 200%'), findsOneWidget);
    });
  });
}
