import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:veloraug/screens/edition_screen.dart';
import 'package:veloraug/widgets/discovery_rails.dart';
import 'package:veloraug/widgets/edition_cards.dart';
import 'package:veloraug/widgets/movie_card.dart';

import 'support.dart';

List<Map<String, Object?>> cards(
  String prefix, {
  int count = 3,
  String vj = 'VJ Emmy',
}) => [
  for (var i = 1; i <= count; i++)
    card('$prefix$i', title: '$prefix $i', vj: vj, rating: 7.0),
];

/// Fast X, a movie by VJ Junior, with every movie rail.
FakeApi movieApi() {
  final api = FakeApi()
    ..editions.add(card('m1', title: 'Fast X'))
    ..details['m1'] = movieDetail('m1')
    ..rails['m1'] = {
      'vj': cards('Junior', vj: 'VJ Junior'),
      'recommended': cards('Like'),
      'popular': cards('Popular'),
      'top_rated': cards('Best'),
      'recent': cards('New'),
    };
  return api;
}

Future<void> openFastX(
  WidgetTester tester,
  FakeApi api, {
  bool signedIn = false,
}) async {
  await pumpApp(tester, api, signedIn: signedIn);
  final tile = find.widgetWithText(MovieCard, 'Fast X').first;
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

List<String> railTitles(WidgetTester tester) => [
  for (final row in tester.widgetList<EditionRow>(find.byType(EditionRow)))
    row.title,
];

Finder chip(String label) => find.widgetWithText(ChoiceChip, label);

Future<void> choose(WidgetTester tester, String label) async {
  await tester.ensureVisible(chip(label));
  await tester.pumpAndSettle();
  await tester.tap(chip(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets("a movie's page ends with its rails, named for it", (
    tester,
  ) async {
    await openFastX(tester, movieApi());

    expect(find.text('More like this'), findsOneWidget);
    expect(railTitles(tester), [
      'More from VJ Junior',
      'Recommended for you',
      'Most popular',
      'Top rated',
      'Recently added',
    ]);
    // The ratings on the posters are credited.
    await tester.ensureVisible(find.text('Ratings from'));
    expect(find.text('Ratings from'), findsOneWidget);
  });

  testWidgets("a series' rails have the series names", (tester) async {
    final api = FakeApi()
      ..editions.add(card('s1', kind: 'series', title: 'Kabaka', vj: 'VJ Emmy'))
      ..details['s1'] = seriesDetail('s1')
      ..rails['s1'] = {
        'recommended': cards('Like'),
        'popular': cards('Trend'),
        'new_episodes': cards('Fresh'),
      };
    await pumpApp(tester, api);
    await tester.tap(find.widgetWithText(MovieCard, 'Kabaka').first);
    await tester.pumpAndSettle();

    expect(railTitles(tester), [
      'Recommended series',
      'Trending series',
      'New episodes this week',
    ]);
  });

  testWidgets('a rail with fewer than three titles is left out', (
    tester,
  ) async {
    final api = movieApi();
    api.rails['m1']!['vj'] = cards('Junior', count: 2, vj: 'VJ Junior');
    await openFastX(tester, api);

    expect(railTitles(tester), isNot(contains('More from VJ Junior')));
    expect(chip('Same VJ'), findsNothing);
  });

  group('the chips', () {
    for (final (label, rails) in [
      ('Same VJ', ['More from VJ Junior']),
      ('Same genre', ['Recommended for you']),
      ('Top rated', ['Top rated']),
      ('New', ['Recently added']),
    ]) {
      testWidgets('$label shows only its rails', (tester) async {
        await openFastX(tester, movieApi());

        await choose(tester, label);

        expect(railTitles(tester), rails);
        expect(tester.widget<ChoiceChip>(chip(label)).selected, isTrue);
        expect(tester.widget<ChoiceChip>(chip('All')).selected, isFalse);
      });
    }

    testWidgets('All shows every rail again', (tester) async {
      await openFastX(tester, movieApi());
      await choose(tester, 'Top rated');

      await choose(tester, 'All');

      expect(railTitles(tester), hasLength(5));
    });

    testWidgets('a single rail needs no chips', (tester) async {
      final api = movieApi();
      api.rails['m1'] = {'recent': cards('New')};
      await openFastX(tester, api);

      expect(railTitles(tester), ['Recently added']);
      expect(find.byType(ChoiceChip), findsNothing);
    });
  });

  group('Because you watched', () {
    testWidgets('signed in, it follows Recommended, and Same genre shows it', (
      tester,
    ) async {
      final api = movieApi()..because['m1'] = ('Rambo', cards('Action'));
      await openFastX(tester, api, signedIn: true);

      expect(railTitles(tester), [
        'More from VJ Junior',
        'Recommended for you',
        'Because you watched Rambo',
        'Most popular',
        'Top rated',
        'Recently added',
      ]);

      await choose(tester, 'Same genre');
      expect(railTitles(tester), [
        'Recommended for you',
        'Because you watched Rambo',
      ]);
    });

    testWidgets('signed out, it is never asked for', (tester) async {
      final api = movieApi()..because['m1'] = ('Rambo', cards('Action'));
      await openFastX(tester, api);

      expect(railTitles(tester), isNot(contains('Because you watched Rambo')));
      expect(
        api.requests.where((r) => r.url.path.contains('because-you-watched')),
        isEmpty,
      );
    });
  });

  group('states', () {
    testWidgets('rail-shaped placeholders while they load', (tester) async {
      final api = movieApi();
      final held = Completer<http.Response>();
      api.intercept = (request) =>
          request.url.path.endsWith('/rails') ? held.future : null;
      await pumpApp(tester, api);
      await tester.tap(find.widgetWithText(MovieCard, 'Fast X').first);
      // Frames, not settling: the placeholder pulses until the answer comes,
      // and settling would run past the request's time limit.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(RailSkeleton), findsOneWidget);
      // The rest of the page doesn't wait.
      expect(find.text('Dom races again.'), findsOneWidget);

      held.complete(http.Response('{"rails": []}', 200));
      await tester.pumpAndSettle();
      expect(find.byType(RailSkeleton), findsNothing);
    });

    testWidgets('a failure says so, and Try again loads them', (tester) async {
      final api = movieApi()..railsStatus = 503;
      await openFastX(tester, api);

      expect(find.text("Couldn't load more titles"), findsOneWidget);

      api.railsStatus = 200;
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(railTitles(tester), hasLength(5));
    });

    testWidgets('with no rails, the section is left out', (tester) async {
      final api = movieApi()..rails.clear();
      await openFastX(tester, api);

      expect(find.byType(EditionScreen), findsOneWidget);
      expect(find.text('More like this'), findsNothing);
    });
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('fits a 320-pixel phone at text size $scale', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = movieApi();
      await pumpApp(tester, api, size: const Size(320, 900));
      final tile = find.widgetWithText(MovieCard, 'Fast X').first;
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(tile);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DiscoveryRails));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(EditionRow), findsWidgets);
    });
  }
}
