import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/app.dart';
import 'package:veloraug/shell/app_shell.dart';
import 'package:veloraug/widgets/dev_auth_proof.dart';
import 'package:veloraug/widgets/dev_connection_check.dart';

const _narrow = Size(400, 800);
const _wide = Size(1200, 800);

void _setScreenSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Future<void> _pumpApp(WidgetTester tester, Size size) async {
  _setScreenSize(tester, size);
  await tester.pumpWidget(const VeloraApp());
  await tester.pumpAndSettle();
}

Future<void> _goTo(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('layout', () {
    testWidgets('narrow screens use the bottom bar', (tester) async {
      await _pumpApp(tester, _narrow);

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });

    testWidgets('wide screens use the side rail', (tester) async {
      await _pumpApp(tester, _wide);

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('layout changes exactly at the breakpoint', (tester) async {
      await _pumpApp(tester, const Size(wideLayoutBreakpoint - 1, 800));
      expect(find.byType(NavigationBar), findsOneWidget);

      _setScreenSize(tester, const Size(wideLayoutBreakpoint, 800));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationRail), findsOneWidget);
    });

    for (final (name, size) in [
      ('small phone', const Size(320, 480)),
      ('landscape phone', const Size(640, 320)),
    ]) {
      testWidgets('large text does not overflow on a $name', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await _pumpApp(tester, size);

        for (final label in ['Search', 'Account', 'Home']) {
          await _goTo(tester, label);
          expect(tester.takeException(), isNull);
        }
      });
    }
  });

  testWidgets('content starts at the top on both layouts', (tester) async {
    double headingTop() =>
        tester.getTopLeft(find.text('Welcome to VeloraUG')).dy;

    await _pumpApp(tester, _narrow);
    final narrowTop = headingTop();

    _setScreenSize(tester, _wide);
    await tester.pumpAndSettle();

    expect(headingTop(), narrowTop);
  });

  group('navigation', () {
    for (final (name, size) in [('narrow', _narrow), ('wide', _wide)]) {
      testWidgets('reaches every screen on a $name layout', (tester) async {
        await _pumpApp(tester, size);
        expect(find.text('Welcome to VeloraUG'), findsOneWidget);

        await _goTo(tester, 'Search');
        expect(find.text("Search isn't connected yet"), findsOneWidget);
        expect(find.text('Welcome to VeloraUG'), findsNothing);

        await _goTo(tester, 'Account');
        expect(find.text("You're signed out"), findsOneWidget);
        expect(find.text("Search isn't connected yet"), findsNothing);

        await _goTo(tester, 'Home');
        expect(find.text('Welcome to VeloraUG'), findsOneWidget);
        expect(find.text("You're signed out"), findsNothing);
      });
    }

    testWidgets('search text survives changing screen and resizing', (
      tester,
    ) async {
      await _pumpApp(tester, _narrow);
      await _goTo(tester, 'Search');
      await tester.enterText(find.byType(TextField), 'kampala');

      await _goTo(tester, 'Home');
      _setScreenSize(tester, _wide);
      await tester.pumpAndSettle();
      await _goTo(tester, 'Search');

      expect(find.text('kampala'), findsOneWidget);
    });
  });

  group('honest placeholders', () {
    testWidgets('home shows an empty catalogue and no movies', (tester) async {
      await _pumpApp(tester, _narrow);

      expect(find.text('No movies yet'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('search still explains itself after typing', (tester) async {
      await _pumpApp(tester, _narrow);
      await _goTo(tester, 'Search');
      await tester.enterText(find.byType(TextField), 'anything');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text("Search isn't connected yet"), findsOneWidget);
    });

    testWidgets('account labels the connection check as development only', (
      tester,
    ) async {
      await _pumpApp(tester, _narrow);
      await _goTo(tester, 'Account');

      expect(
        find.text('Development only: API connection check'),
        findsOneWidget,
      );
      expect(find.text('Check connection'), findsOneWidget);
    });

    testWidgets('account offers no sign-in or payment controls', (
      tester,
    ) async {
      await _pumpApp(tester, _narrow);
      await _goTo(tester, 'Account');

      // The only buttons allowed are the debug-only development tools'.
      final devCheckButtons = find.descendant(
        of: find.byType(DevConnectionCheck),
        matching: find.byType(ButtonStyleButton),
      );
      final devProofButtons = find.descendant(
        of: find.byType(DevAuthProof),
        matching: find.byType(ButtonStyleButton),
      );
      expect(
        find.byType(ButtonStyleButton).evaluate().length,
        devCheckButtons.evaluate().length + devProofButtons.evaluate().length,
      );
      expect(find.byType(TextField), findsNothing);
      expect(
        find.textContaining(RegExp('pay|subscri', caseSensitive: false)),
        findsNothing,
      );
    });
  });

  group('accessibility', () {
    for (final (name, size) in [('narrow', _narrow), ('wide', _wide)]) {
      testWidgets('meets tap target, label and contrast guidelines on a '
          '$name layout', (tester) async {
        final semantics = tester.ensureSemantics();
        await _pumpApp(tester, size);

        for (final label in ['Home', 'Search', 'Account']) {
          await _goTo(tester, label);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }
        semantics.dispose();
      });

      testWidgets('keyboard alone can change screen on a $name layout', (
        tester,
      ) async {
        await _pumpApp(tester, size);

        // Home has nothing else to focus, so the first Tab presses move
        // through the navigation items in order: Home, then Search.
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();

        expect(find.text("Search isn't connected yet"), findsOneWidget);
      });
    }

    testWidgets('Tab reaches the search field only on the Search screen', (
      tester,
    ) async {
      Future<bool> tabReachesField() async {
        for (var i = 0; i < 10; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          final focused = FocusManager.instance.primaryFocus?.context;
          if (focused?.findAncestorWidgetOfExactType<EditableText>() != null) {
            return true;
          }
        }
        return false;
      }

      await _pumpApp(tester, _wide);
      expect(await tabReachesField(), isFalse);

      await _goTo(tester, 'Search');
      expect(await tabReachesField(), isTrue);
    });

    testWidgets('the search field has a label for screen readers', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pumpApp(tester, _narrow);
      await _goTo(tester, 'Search');

      expect(
        tester.getSemantics(find.bySemanticsLabel('Search movies')),
        isSemantics(label: 'Search movies', isTextField: true),
      );
      semantics.dispose();
    });
  });
}
