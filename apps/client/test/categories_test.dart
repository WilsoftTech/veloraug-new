import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:veloraug/screens/browse_screen.dart';
import 'package:veloraug/widgets/edition_cards.dart';
import 'package:veloraug/widgets/loading_placeholder.dart';

import 'support.dart';

final indianChip = find.byKey(const ValueKey('indian-movies'));

/// Three Indian movies, an Indian series also for Kids, and a Nollywood
/// movie, tagged as the API lists them.
FakeApi tagged({List<Map<String, Object?>>? categories}) {
  final api = FakeApi()
    ..categories =
        categories ??
        [
          category('kids', 'Kids', editions: 4, movies: 4),
          category('nollywood', 'Nollywood', editions: 1, movies: 1),
          category('indian', 'Indian', editions: 4, movies: 3),
        ];
  for (final (id, title) in [
    ('r1', 'RRR'),
    ('b1', 'Baahubali'),
    ('p1', 'Pathaan'),
  ]) {
    api.editions.add({
      ...card(id, title: title),
      'categories': ['indian'],
    });
  }
  api.editions
    ..add({
      ...card('s1', title: 'Kabaka', kind: 'series'),
      'categories': ['indian', 'kids'],
    })
    ..add({
      ...card('n1', title: 'Lagos Nights'),
      'categories': ['nollywood'],
    });
  return api;
}

void main() {
  group('Indian Movies', () {
    testWidgets('comes first on Home, and opens Indian movies only', (
      tester,
    ) async {
      final api = tagged();
      await pumpApp(tester, api);

      expect(indianChip, findsOneWidget);
      // Before Search.
      expect(
        tester.getTopLeft(indianChip).dx,
        lessThan(
          tester.getTopLeft(find.widgetWithText(ActionChip, 'Search titles')).dx,
        ),
      );

      await tester.tap(indianChip);
      await tester.pumpAndSettle();

      expect(find.byType(BrowseScreen), findsOneWidget);
      expect(find.text('Indian Movies'), findsWidgets);
      final asked = api.requests.last.url.queryParameters;
      expect(asked['category'], 'indian');
      expect(asked['kind'], 'movie');
      expect(find.byType(EditionTile), findsNWidgets(3));
      expect(find.text('Kabaka'), findsNothing);
    });

    testWidgets('is hidden without Indian movies', (tester) async {
      // Only an Indian series.
      final api = tagged(
        categories: [category('indian', 'Indian', editions: 1, movies: 0)],
      );
      await pumpApp(tester, api);

      expect(indianChip, findsNothing);
      await goTo(tester, 'Filter');
      expect(indianChip, findsNothing);
    });

    testWidgets("is hidden when categories can't load, and Home carries on", (
      tester,
    ) async {
      final api = tagged()..categoriesStatus = 503;
      await pumpApp(tester, api);

      expect(indianChip, findsNothing);
      expect(find.byKey(const ValueKey('row-latest')), findsOneWidget);
    });

    testWidgets('is at the top of Filter too', (tester) async {
      final api = tagged();
      await pumpApp(tester, api);
      await goTo(tester, 'Filter');

      expect(indianChip, findsOneWidget);
      await tester.tap(indianChip);
      await tester.pumpAndSettle();

      expect(api.requests.last.url.queryParameters['category'], 'indian');
      expect(find.byType(EditionTile), findsNWidgets(3));
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('fits a 320-pixel phone at text size $scale', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpApp(tester, tagged(), size: const Size(320, 900));

        expect(tester.takeException(), isNull);
        expect(indianChip, findsOneWidget);
      });
    }
  });

  group("Home's category rows", () {
    testWidgets('one per category with titles, Indian first, then most used', (
      tester,
    ) async {
      final api = tagged(
        categories: [
          category('kids', 'Kids', editions: 1),
          category('nollywood', 'Nollywood', editions: 1),
          category('korean', 'Korean', editions: 0),
          category('indian', 'Indian', editions: 4, movies: 3),
        ],
      );
      await pumpApp(tester, api, size: const Size(1200, 4000));

      final rows = [
        for (final row in tester.widgetList<EditionRow>(
          find.byType(EditionRow),
        ))
          row.title,
      ];
      final first = rows.indexOf('Indian');
      expect(first, greaterThan(rows.indexOf('Series')));
      expect(rows.sublist(first, first + 3), ['Indian', 'Kids', 'Nollywood']);
      // Nothing published in Korean.
      expect(rows, isNot(contains('Korean')));
    });

    testWidgets('See all opens the whole category', (tester) async {
      final api = tagged();
      await pumpApp(tester, api, size: const Size(1200, 4000));
      final row = find.byKey(const ValueKey('row-category:indian'));

      await tester.tap(
        find.descendant(of: row, matching: find.text('See all')),
      );
      await tester.pumpAndSettle();

      expect(api.requests.last.url.queryParameters['category'], 'indian');
      expect(api.requests.last.url.queryParameters['kind'], isNull);
      expect(find.byType(EditionTile), findsNWidgets(4));
    });

    testWidgets('at most six', (tester) async {
      final api = FakeApi()
        ..categories = [
          for (var i = 0; i < 8; i++)
            category('c$i', 'Category $i', editions: 1),
        ];
      for (var i = 0; i < 8; i++) {
        api.editions.add({
          ...card('e$i', title: 'Title $i'),
          'categories': ['c$i'],
        });
      }
      await pumpApp(tester, api, size: const Size(1200, 6000));

      expect(
        find.byWidgetPredicate(
          (w) =>
              w is EditionRow &&
              (w.key as ValueKey<String>?)?.value.startsWith('row-category:') ==
                  true,
        ),
        findsNWidgets(6),
      );
    });
  });

  group("Filter's Category section", () {
    testWidgets('narrows the results with the other choices', (tester) async {
      final api = tagged();
      await pumpApp(tester, api, size: const Size(400, 1600));
      await goTo(tester, 'Filter');

      await tester.tap(find.text('Series').last);
      await tester.tap(find.byKey(const ValueKey('choice-kids')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();

      final asked = api.requests.last.url.queryParameters;
      expect(asked['category'], 'kids');
      expect(asked['kind'], 'series');
      expect(find.text('Series · Kids'), findsWidgets);
      expect(find.text('Kabaka'), findsWidgets);
    });

    testWidgets('loads with placeholders, and a failure can be retried', (
      tester,
    ) async {
      final api = tagged();
      final held = Completer<http.Response>();
      api.intercept = (request) =>
          request.url.path == '/api/v1/categories' && !held.isCompleted
          ? held.future
          : null;
      await pumpApp(tester, api, settle: false);
      await tester.tap(find.text('Filter').last);
      // Frames, not settling: settling would run past the request's time
      // limit.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Category'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(VeloraLoadingRegion),
          matching: find.byType(VeloraSkeleton),
        ),
        findsNWidgets(3),
      );

      held.complete(http.Response('{}', 503));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load Category choices"), findsOneWidget);

      api.intercept = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('choice-indian')), findsOneWidget);
    });

    testWidgets('is left out while no category has titles', (tester) async {
      final api = tagged(categories: []);
      await pumpApp(tester, api);
      await goTo(tester, 'Filter');

      expect(find.text('Category'), findsNothing);
      expect(find.text('Genre'), findsOneWidget);
    });
  });
}
