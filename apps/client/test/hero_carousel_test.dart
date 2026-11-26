import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:veloraug/screens/edition_screen.dart';
import 'package:veloraug/screens/player_screen.dart';
import 'package:veloraug/theme/tokens.dart';
import 'package:veloraug/widgets/hero_carousel.dart';

import 'support.dart';

/// Three featured titles, newest first: two movies and a series, all also
/// in the catalogue, with Fast X's page.
FakeApi featuredApi() {
  final api = FakeApi()
    ..featured.addAll([
      featuredTitle('m1', title: 'Fast X', rating: 7.4),
      featuredTitle(
        's1',
        kind: 'series',
        title: 'Kabaka',
        vj: 'VJ Emmy',
        genres: ['Drama', 'History'],
        backdrop: false,
      ),
      featuredTitle('m2', title: 'Rambo', vj: 'VJ Emmy'),
    ])
    ..editions.addAll([
      card('m1', title: 'Fast X'),
      card('s1', kind: 'series', title: 'Kabaka', vj: 'VJ Emmy'),
      card('m2', title: 'Rambo', vj: 'VJ Emmy'),
    ])
    ..details['m1'] = movieDetail('m1')
    ..details['s1'] = seriesDetail('s1')
    ..watchListItems['item-m1'] = {
      'item_id': 'item-m1',
      'edition': card('m1', title: 'Fast X'),
      'season': null,
      'episode': null,
      'episode_title': null,
    };
  return api;
}

final _hero = find.byType(HeroCarousel);

Finder inHero(Finder finder) => find.descendant(of: _hero, matching: finder);

/// The title the hero shows now, read from its heading.
bool showing(String title) =>
    inHero(find.text(title)).evaluate().isNotEmpty &&
    inHero(find.text(title)).hitTestable().evaluate().isNotEmpty;

void reduceMotion(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// Lets one title's time run out, then its crossfade finish.
Future<void> waitOneTitle(WidgetTester tester) async {
  await tester.pump(VeloraMotion.heroInterval);
  await tester.pump(VeloraMotion.heroCrossfade);
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('Home', () {
    testWidgets('leads with the hero instead of the welcome panel', (
      tester,
    ) async {
      reduceMotion(tester);
      await pumpApp(tester, featuredApi(), size: const Size(1280, 900));

      expect(_hero, findsOneWidget);
      expect(find.text('Welcome to VeloraUG'), findsNothing);
      expect(find.bySemanticsLabel('Recently added'), findsOneWidget);
      expect(inHero(find.text('Fast X')), findsOneWidget);
      expect(inHero(find.text('VJ Junior · 2023')), findsOneWidget);
      expect(inHero(find.text('7.4')), findsOneWidget);
      expect(inHero(find.text('Action')), findsOneWidget);
      expect(
        find.bySemanticsLabel('Rated 7.4 out of 10 on TMDB'),
        findsWidgets,
      );
      // No "Ratings from TMDB" line at the foot of Home.
      expect(find.text('Ratings from'), findsNothing);
    });

    testWidgets('keeps the welcome panel with nothing to feature', (
      tester,
    ) async {
      final api = featuredApi()..featured.clear();
      await pumpApp(tester, api);

      expect(_hero, findsNothing);
      expect(find.text('Welcome to VeloraUG'), findsOneWidget);
    });

    testWidgets('keeps the welcome panel and its shelves when it fails', (
      tester,
    ) async {
      final api = featuredApi()..featuredStatus = 500;
      await pumpApp(tester, api);

      expect(_hero, findsNothing);
      expect(find.text('Welcome to VeloraUG'), findsOneWidget);
      expect(find.text('Latest'), findsOneWidget);
    });

    testWidgets('shows a hero-shaped placeholder while it loads', (
      tester,
    ) async {
      final api = featuredApi();
      final held = Completer<http.Response>();
      api.intercept = (request) =>
          request.url.path == '/api/v1/featured' ? held.future : null;
      await pumpApp(tester, api, settle: false);

      expect(find.byType(HeroCarouselSkeleton), findsOneWidget);
      expect(find.text('Latest'), findsOneWidget);

      held.complete(http.Response('[]', 200));
      await tester.pumpAndSettle();
      expect(find.byType(HeroCarouselSkeleton), findsNothing);
      expect(find.text('Welcome to VeloraUG'), findsOneWidget);
    });
  });

  group('moving on', () {
    testWidgets('every 6 seconds, with a crossfade, back to the first', (
      tester,
    ) async {
      await pumpApp(tester, featuredApi(), settle: false);
      expect(showing('Fast X'), isTrue);

      await waitOneTitle(tester);
      expect(showing('Kabaka'), isTrue);
      expect(showing('Fast X'), isFalse);

      await waitOneTitle(tester);
      await waitOneTitle(tester);
      expect(showing('Fast X'), isTrue);
    });

    testWidgets('the artwork zooms slowly while it plays', (tester) async {
      await pumpApp(tester, featuredApi(), settle: false);
      double scale() {
        final transform = tester.widget<Transform>(
          inHero(find.byType(Transform)).first,
        );
        return transform.transform.getMaxScaleOnAxis();
      }

      final early = scale();
      await tester.pump(const Duration(seconds: 3));
      expect(scale(), greaterThan(early));
      expect(scale(), lessThanOrEqualTo(VeloraMotion.heroZoom));
    });

    testWidgets('stops under the mouse, and goes on when it leaves', (
      tester,
    ) async {
      await pumpApp(
        tester,
        featuredApi(),
        settle: false,
        size: const Size(1280, 900),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(_hero));
      await tester.pump();

      await waitOneTitle(tester);
      await waitOneTitle(tester);
      expect(showing('Fast X'), isTrue);

      await mouse.moveTo(const Offset(1, 899));
      await tester.pump();
      await waitOneTitle(tester);
      expect(showing('Kabaka'), isTrue);
    });

    testWidgets('stops while touched', (tester) async {
      await pumpApp(tester, featuredApi(), settle: false);
      final finger = await tester.startGesture(
        tester.getCenter(_hero),
        kind: PointerDeviceKind.touch,
      );
      await tester.pump();

      await waitOneTitle(tester);
      expect(showing('Fast X'), isTrue);

      await finger.up();
      await tester.pump();
      await waitOneTitle(tester);
      expect(showing('Kabaka'), isTrue);
    });

    testWidgets('stops while a button in it has keyboard focus', (
      tester,
    ) async {
      await pumpApp(tester, featuredApi(), settle: false, signedIn: true);
      Focus.of(tester.element(inHero(find.text('Watch now')))).requestFocus();
      await tester.pump();

      await waitOneTitle(tester);
      expect(showing('Fast X'), isTrue);
    });

    testWidgets('stops while the app is in the background', (tester) async {
      await pumpApp(tester, featuredApi(), settle: false);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();

      await waitOneTitle(tester);
      expect(showing('Fast X'), isTrue);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await waitOneTitle(tester);
      expect(showing('Kabaka'), isTrue);
    });

    testWidgets('the pause button stops it, and play starts it again', (
      tester,
    ) async {
      await pumpApp(tester, featuredApi(), settle: false);

      await tester.tap(find.byTooltip('Pause slideshow'));
      await tester.pump();
      await waitOneTitle(tester);
      expect(showing('Fast X'), isTrue);
      expect(find.byTooltip('Play slideshow'), findsOneWidget);

      await tester.tap(find.byTooltip('Play slideshow'));
      await tester.pump();
      await waitOneTitle(tester);
      expect(showing('Kabaka'), isTrue);
    });

    testWidgets('with reduced motion, it never moves on or zooms by itself', (
      tester,
    ) async {
      reduceMotion(tester);
      await pumpApp(tester, featuredApi());

      await waitOneTitle(tester);
      await waitOneTitle(tester);
      expect(showing('Fast X'), isTrue);
      expect(find.byTooltip('Pause slideshow'), findsNothing);
      final transform = tester.widget<Transform>(
        inHero(find.byType(Transform)).first,
      );
      expect(transform.transform.getMaxScaleOnAxis(), 1);

      // The dots still work, at once.
      await tester.tap(find.bySemanticsLabel('Show title 3 of 3'));
      await tester.pump();
      expect(showing('Rambo'), isTrue);
    });
  });

  group('choosing a title', () {
    testWidgets('a dot shows its title, read as selected', (tester) async {
      reduceMotion(tester);
      await pumpApp(tester, featuredApi());

      expect(
        tester.getSemantics(find.bySemanticsLabel('Show title 1 of 3')),
        isSemantics(isSelected: true, isButton: true),
      );
      await tester.tap(find.bySemanticsLabel('Show title 2 of 3'));
      await tester.pump();

      expect(showing('Kabaka'), isTrue);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Show title 2 of 3')),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Show title 1 of 3')),
        isSemantics(isSelected: false),
      );
    });

    testWidgets('a swipe moves to the next or the previous title', (
      tester,
    ) async {
      reduceMotion(tester);
      await pumpApp(tester, featuredApi());

      await tester.fling(_hero, const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(showing('Kabaka'), isTrue);

      await tester.fling(_hero, const Offset(300, 0), 1000);
      await tester.pumpAndSettle();
      expect(showing('Fast X'), isTrue);
    });

    testWidgets('the arrow keys move between titles when it has focus', (
      tester,
    ) async {
      reduceMotion(tester);
      await pumpApp(tester, featuredApi(), signedIn: true);
      Focus.of(tester.element(inHero(find.text('Watch now')))).requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(showing('Kabaka'), isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(showing('Rambo'), isTrue);
    });
  });

  group('Watch now', () {
    testWidgets('signed in, a movie plays through the player', (tester) async {
      reduceMotion(tester);
      final api = featuredApi();
      await pumpApp(tester, api, signedIn: true);

      await tester.tap(inHero(find.text('Watch now')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PlayerScreen), findsOneWidget);
      // The same grant request as the movie's page, which checks the pass.
      expect(api.granted, ['item-m1']);
    });

    testWidgets('signed out, it asks the viewer to sign in first', (
      tester,
    ) async {
      reduceMotion(tester);
      final api = featuredApi();
      await pumpApp(tester, api);

      expect(inHero(find.text('Watch now')), findsNothing);
      expect(inHero(find.text('Sign in to watch')), findsOneWidget);
      expect(api.grants, 0);
    });

    testWidgets("a series opens its page to choose an episode", (tester) async {
      reduceMotion(tester);
      final api = featuredApi();
      await pumpApp(tester, api, signedIn: true);
      await tester.tap(find.bySemanticsLabel('Show title 2 of 3'));
      await tester.pump();

      expect(inHero(find.text('Add to Watch List')), findsNothing);
      await tester.tap(inHero(find.text('Watch now')));
      await tester.pumpAndSettle();

      expect(find.byType(EditionScreen), findsOneWidget);
      expect(api.grants, 0);
    });

    testWidgets('Details and the poster open the title page', (tester) async {
      reduceMotion(tester);
      await pumpApp(tester, featuredApi());
      await tester.tap(find.bySemanticsLabel('Show title 2 of 3'));
      await tester.pump();

      await tester.tap(inHero(find.text('Details')));
      await tester.pumpAndSettle();
      expect(find.byType(EditionScreen), findsOneWidget);
    });
  });

  group('Watch List', () {
    testWidgets('adds a movie at once, then saves it', (tester) async {
      reduceMotion(tester);
      final api = featuredApi();
      await pumpApp(tester, api, signedIn: true);

      await tester.tap(inHero(find.text('Add to Watch List')));
      await tester.pump();
      expect(inHero(find.text('In Watch List')), findsOneWidget);
      expect(inHero(find.byIcon(Icons.check)), findsOneWidget);

      await tester.pumpAndSettle();
      expect(api.watchList.keys, ['item-m1']);
      // One node: the button, read as on.
      expect(
        tester.getSemantics(find.bySemanticsLabel(RegExp('In Watch List'))),
        isSemantics(isButton: true, isToggled: true),
      );

      await tester.tap(inHero(find.text('In Watch List')));
      await tester.pumpAndSettle();
      expect(api.watchList, isEmpty);
      expect(inHero(find.text('Add to Watch List')), findsOneWidget);
    });

    testWidgets('shows a movie already saved', (tester) async {
      reduceMotion(tester);
      final api = featuredApi();
      api.watchList['item-m1'] = api.watchListItems['item-m1']!;
      await pumpApp(tester, api, signedIn: true);

      expect(inHero(find.text('In Watch List')), findsOneWidget);
    });

    testWidgets('puts it back and says so when saving fails', (tester) async {
      reduceMotion(tester);
      final api = featuredApi();
      final refused = Completer<http.Response>();
      api.intercept = (request) =>
          request.method == 'PUT' ? refused.future : null;
      await pumpApp(tester, api, signedIn: true);

      await tester.tap(inHero(find.text('Add to Watch List')));
      await tester.pump();
      // Shown as saved before the API answers.
      expect(inHero(find.text('In Watch List')), findsOneWidget);

      refused.complete(http.Response('{"detail": "x"}', 404));
      await tester.pumpAndSettle();
      expect(api.watchList, isEmpty);
      expect(inHero(find.text('Add to Watch List')), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('signed out, it asks the viewer to sign in', (tester) async {
      reduceMotion(tester);
      final api = featuredApi();
      await pumpApp(tester, api);

      expect(inHero(find.text('Add to Watch List')), findsOneWidget);
      expect(
        api.requests.where((r) => r.url.path.contains('watch-list')),
        isEmpty,
      );
    });
  });

  group('fits', () {
    for (final width in [320.0, 768.0, 1280.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$width pixels wide at text size $scale', (tester) async {
          reduceMotion(tester);
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pumpApp(tester, featuredApi(), size: Size(width, 1000));

          expect(tester.takeException(), isNull);
          expect(_hero, findsOneWidget);
          final hero = tester.getRect(_hero);
          if (width < VeloraLayout.mediumBreakpoint) {
            // Edge to edge on a phone.
            expect(hero.width, width);
          } else {
            expect(hero.width, lessThan(width));
            expect(
              hero.height,
              greaterThanOrEqualTo(VeloraLayout.heroMinHeight),
            );
          }
        });
      }
    }
  });
}
