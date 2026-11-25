import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/l10n/app_localizations.dart';
import 'package:veloraug/theme/tokens.dart';
import 'package:veloraug/theme/velora_theme.dart';
import 'package:veloraug/widgets/screen_body.dart';

Widget app(Widget home, {double textScale = 1, bool reduced = false}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: buildVeloraTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduced,
        ),
        child: child!,
      ),
      home: home,
    );

void main() {
  group('page transitions', () {
    test('every platform uses the same one', () {
      final builders = buildVeloraTheme().pageTransitionsTheme.builders;
      for (final platform in TargetPlatform.values) {
        expect(builders[platform], isA<VeloraPageTransitionsBuilder>());
      }
    });

    for (final reduced in [false, true]) {
      testWidgets(
        reduced ? 'with reduced motion a page simply appears' : 'pages fade',
        (tester) async {
          await tester.pumpWidget(
            app(
              Builder(
                builder: (context) => TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const Scaffold(body: Text('Next')),
                    ),
                  ),
                  child: const Text('Go'),
                ),
              ),
              reduced: reduced,
            ),
          );
          await tester.tap(find.text('Go'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));

          // Part way: faded in, or already there.
          final fades = tester.widgetList<FadeTransition>(
            find.ancestor(
              of: find.text('Next'),
              matching: find.byType(FadeTransition),
            ),
          );
          final opacity = fades.fold<double>(
            1,
            (value, fade) => value * fade.opacity.value,
          );
          if (reduced) {
            expect(opacity, 1);
          } else {
            expect(opacity, lessThan(1));
          }
          await tester.pumpAndSettle();
          expect(find.text('Next'), findsOneWidget);
        },
      );
    }
  });

  group('page headings at large text sizes', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('"Plans & membership" fits 320 pixels at $scale', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 900);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          app(
            const Scaffold(
              body: ScreenBody(
                heading: 'Plans & membership',
                intro: 'Your plan, when it ends, renewing or changing',
                children: [],
              ),
            ),
            textScale: scale,
          ),
        );

        expect(tester.takeException(), isNull);
        final heading = tester.widget<RichText>(
          find.descendant(
            of: find.text('Plans & membership'),
            matching: find.byType(RichText),
          ),
        );
        // Capped at 1.5; the intro keeps the viewer's full size.
        expect(
          heading.textScaler.scale(10),
          closeTo(
            10 * (scale > 1.5 ? VeloraLayout.maxHeadingTextScale : scale),
            0.01,
          ),
        );
        final intro = tester.widget<RichText>(
          find.descendant(
            of: find.text('Your plan, when it ends, renewing or changing'),
            matching: find.byType(RichText),
          ),
        );
        expect(intro.textScaler.scale(10), closeTo(10 * scale, 0.01));
      });
    }
  });
}
