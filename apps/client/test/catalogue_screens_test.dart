import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/api/catalogue_api.dart';
import 'package:veloraug/app.dart';
import 'package:veloraug/screens/account_screen.dart';
import 'package:veloraug/screens/movie_detail_screen.dart';
import 'package:veloraug/screens/search_screen.dart';
import 'package:veloraug/widgets/velora_button.dart';

Map<String, Object?> _movie(int n, {String? title, int? year = 2014}) => {
  'id': 'id-$n',
  'title': title ?? 'Movie $n',
  'year': year,
  'poster_url': 'https://image.tmdb.org/t/p/w342/$n.jpg',
};

Map<String, Object?> _detail(int n, {String title = 'Interstellar'}) => {
  ..._movie(n, title: title),
  'overview': 'Explorers travel through a wormhole.',
  'runtime_minutes': 169,
  'genres': ['Adventure', 'Drama'],
  'backdrop_url': 'https://image.tmdb.org/t/p/w780/back.jpg',
};

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

/// A fake API: each test sets how it answers, and sees what was asked.
class _Server {
  final requests = <Uri>[];
  FutureOr<http.Response> Function(Uri url) answer = (url) =>
      _json({'movies': [], 'next_offset': null});

  late final api = CatalogueApi(
    baseUrl: Uri.parse('http://127.0.0.1:8000'),
    httpClient: MockClient((request) async {
      requests.add(request.url);
      return answer(request.url);
    }),
  );

  List<Uri> get searches =>
      requests.where((url) => url.queryParameters.containsKey('q')).toList();
}

Future<void> _pump(WidgetTester tester, _Server server) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1200, 1600);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(VeloraApp(catalogueApi: server.api));
  await tester.pumpAndSettle();
}

Future<void> _goTo(WidgetTester tester, String label) async {
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  group('home', () {
    testWidgets('shows published movies with their years', (tester) async {
      final server = _Server()
        ..answer = (url) => _json({
          'movies': [_movie(1, title: 'Inception', year: 2010), _movie(2)],
          'next_offset': null,
        });

      await _pump(tester, server);

      expect(find.text('Inception'), findsOneWidget);
      expect(find.text('2010'), findsOneWidget);
      expect(find.text('Movie 2'), findsOneWidget);
      expect(find.text('Show more'), findsNothing);
      expect(server.requests.single.path, '/api/v1/movies');
    });

    testWidgets('Show more adds the next page', (tester) async {
      final server = _Server()
        ..answer = (url) => url.queryParameters['offset'] == '24'
            ? _json({
                'movies': [_movie(3)],
                'next_offset': null,
              })
            : _json({
                'movies': [_movie(1), _movie(2)],
                'next_offset': 24,
              });
      await _pump(tester, server);

      await tester.ensureVisible(find.text('Show more'));
      await tester.tap(find.text('Show more'));
      await tester.pumpAndSettle();

      expect(find.text('Movie 1'), findsOneWidget);
      expect(find.text('Movie 3'), findsOneWidget);
      expect(find.text('Show more'), findsNothing);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('fits a 320-pixel phone at text size $scale', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final server = _Server()
          ..answer = (url) => url.path == '/api/v1/movies'
              ? _json({
                  'movies': [
                    for (var n = 0; n < 5; n++)
                      _movie(n, title: 'A rather long movie title number $n'),
                  ],
                  'next_offset': 5,
                })
              : _json(_detail(1, title: 'A rather long movie title number 1'));
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 640);
        addTearDown(tester.view.reset);

        await tester.pumpWidget(VeloraApp(catalogueApi: server.api));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final card = find.text('A rather long movie title number 1');
        await tester.ensureVisible(card);
        await tester.pumpAndSettle();
        await tester.tap(card);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('Explorers travel through a wormhole.'),
          findsOneWidget,
        );
      });
    }

    testWidgets('an empty catalogue says so', (tester) async {
      await _pump(tester, _Server());

      expect(find.text('No movies yet'), findsOneWidget);
    });

    testWidgets('a failure explains itself, and Try again recovers', (
      tester,
    ) async {
      final server = _Server()..answer = (url) => _json({'detail': 'x'}, 503);
      await _pump(tester, server);

      expect(find.text("Couldn't load movies"), findsOneWidget);
      expect(
        find.text('VeloraUG is busy right now. Try again in a moment.'),
        findsOneWidget,
      );

      server.answer = (url) => _json({
        'movies': [_movie(1)],
        'next_offset': null,
      });
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();

      expect(find.text('Movie 1'), findsOneWidget);
    });
  });

  group('detail', () {
    testWidgets('tapping a card opens its details', (tester) async {
      final server = _Server()
        ..answer = (url) => url.path == '/api/v1/movies'
            ? _json({
                'movies': [_movie(7, title: 'Interstellar')],
                'next_offset': null,
              })
            : _json(_detail(7));
      await _pump(tester, server);

      await tester.tap(find.text('Interstellar'));
      await tester.pumpAndSettle();

      expect(server.requests.last.path, '/api/v1/movies/id-7');
      expect(find.text('2014 · 2 h 49 min'), findsOneWidget);
      expect(find.text('Adventure'), findsOneWidget);
      expect(find.text('Explorers travel through a wormhole.'), findsOneWidget);
      expect(find.text('Coming soon'), findsOneWidget);
      final watch = tester.widget<VeloraButton>(
        find.widgetWithText(VeloraButton, 'Watch'),
      );
      expect(watch.onPressed, isNull);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Welcome to VeloraUG'), findsOneWidget);
    });

    testWidgets('a movie that is gone says so, and Back returns', (
      tester,
    ) async {
      final server = _Server()
        ..answer = (url) => url.path == '/api/v1/movies'
            ? _json({
                'movies': [_movie(7, title: 'Hidden now')],
                'next_offset': null,
              })
            : _json({'detail': "This movie isn't available."}, 404);
      await _pump(tester, server);

      await tester.tap(find.text('Hidden now'));
      await tester.pumpAndSettle();

      expect(find.text("This movie isn't available"), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to VeloraUG'), findsOneWidget);
    });

    testWidgets('details still being fetched can be retried', (tester) async {
      var detailCalls = 0;
      final server = _Server()
        ..answer = (url) {
          if (url.path == '/api/v1/movies') {
            return _json({
              'movies': [_movie(7, title: 'Interstellar')],
              'next_offset': null,
            });
          }
          detailCalls++;
          return detailCalls == 1
              ? _json({'detail': 'later'}, 503)
              : _json(_detail(7));
        };
      await _pump(tester, server);

      await tester.tap(find.text('Interstellar'));
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load this movie"), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Explorers travel through a wormhole.'), findsOneWidget);
    });

    test('runtimes read naturally', () {
      expect(formatRuntime(169), '2 h 49 min');
      expect(formatRuntime(45), '45 min');
      expect(formatRuntime(120), '2 h');
    });
  });

  group('search', () {
    testWidgets('waits for two letters and a pause before asking', (
      tester,
    ) async {
      final server = _Server()
        ..answer = (url) => _json({
          'movies': [_movie(7, title: 'Interstellar')],
          'next_offset': null,
        });
      await _pump(tester, server);
      await _goTo(tester, 'Search');

      await tester.enterText(find.byType(TextField), 'i');
      await tester.pump(searchDelay * 2);
      expect(server.searches, isEmpty);
      expect(find.text('Find a movie'), findsOneWidget);

      await tester.enterText(find.byType(TextField), ' inter ');
      await tester.pump(searchDelay ~/ 2);
      expect(server.searches, isEmpty);

      await tester.pump(searchDelay);
      await tester.pumpAndSettle();
      expect(server.searches.single.queryParameters['q'], 'inter');
      expect(find.text('Interstellar'), findsOneWidget);
      expect(find.text('1 movie for "inter"'), findsOneWidget);
    });

    testWidgets('a slow earlier answer never replaces a newer one', (
      tester,
    ) async {
      final slow = Completer<http.Response>();
      final server = _Server()
        ..answer = (url) => url.queryParameters['q'] == 'mat'
            ? slow.future
            : _json({
                'movies': [_movie(1, title: 'Inception')],
                'next_offset': null,
              });
      await _pump(tester, server);
      await _goTo(tester, 'Search');

      await tester.enterText(find.byType(TextField), 'mat');
      await tester.pump(searchDelay);
      await tester.enterText(find.byType(TextField), 'incep');
      await tester.pump(searchDelay);
      await tester.pumpAndSettle();
      expect(find.text('Inception'), findsOneWidget);

      slow.complete(
        _json({
          'movies': [_movie(2, title: 'The Matrix')],
          'next_offset': null,
        }),
      );
      await tester.pumpAndSettle();

      expect(find.text('Inception'), findsOneWidget);
      expect(find.text('The Matrix'), findsNothing);
    });

    testWidgets('pressing search sends at once', (tester) async {
      final server = _Server();
      await _pump(tester, server);
      await _goTo(tester, 'Search');

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(server.searches, hasLength(1));
      await tester.pumpAndSettle();

      expect(find.text('No movies match'), findsOneWidget);
      // The pending timer was cancelled, so it doesn't search again.
      await tester.pump(searchDelay * 2);
      expect(server.searches, hasLength(1));
    });

    testWidgets('a failed search can be retried', (tester) async {
      final server = _Server()..answer = (url) => _json({'detail': 'x'}, 500);
      await _pump(tester, server);
      await _goTo(tester, 'Search');

      await tester.enterText(find.byType(TextField), 'inter');
      await tester.pump(searchDelay);
      await tester.pumpAndSettle();
      expect(find.text("Couldn't search"), findsOneWidget);

      server.answer = (url) => _json({
        'movies': [_movie(7, title: 'Interstellar')],
        'next_offset': null,
      });
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Interstellar'), findsOneWidget);
    });
  });

  testWidgets('Account credits TMDB with its exact notice', (tester) async {
    await _pump(tester, _Server());
    await _goTo(tester, 'Account');

    expect(find.text('About'), findsOneWidget);
    expect(find.text(tmdbNotice), findsOneWidget);
    final logo = tester.widget<Image>(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.semanticLabel == 'TMDB logo',
      ),
    );
    expect((logo.image as AssetImage).assetName, tmdbLogoAsset);
    expect(logo.height, 16);
    expect(find.bySemanticsLabel('TMDB logo'), findsOneWidget);
    expect(
      tmdbNotice,
      'This product uses the TMDB API but is not endorsed or certified by '
      'TMDB.',
    );
  });
}
