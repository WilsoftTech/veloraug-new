import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:veloraug/api/catalogue_api.dart';
import 'package:veloraug/api/playback_api.dart';
import 'package:veloraug/l10n/app_localizations.dart';
import 'package:veloraug/l10n/app_localizations_en.dart';
import 'package:veloraug/screens/account_screen.dart';
import 'package:veloraug/screens/edition_screen.dart';
import 'package:veloraug/screens/player_screen.dart';
import 'package:veloraug/screens/search_screen.dart';
import 'package:veloraug/widgets/movie_card.dart';
import 'package:veloraug/widgets/velora_button.dart';

import 'support.dart';

/// Two VJs, a movie each, a series, and a test film.
FakeApi catalogue() {
  final api = FakeApi()
    ..editions.addAll([
      card('m1', title: 'Fast X', vj: 'VJ Junior'),
      card('s1', kind: 'series', title: 'Kabaka', vj: 'VJ Emmy'),
      card('m2', title: 'Rambo', vj: 'VJ Emmy'),
      card('t1', title: 'The Matrix', vj: null),
    ])
    ..details['m1'] = movieDetail('m1')
    ..details['s1'] = seriesDetail('s1')
    ..vjs.addAll([
      {
        'id': 'v2',
        'name': 'VJ Emmy',
        'slug': 'vj-emmy',
        'photo_url': null,
        'editions': 2,
      },
      {
        'id': 'v1',
        'name': 'VJ Junior',
        'slug': 'vj-junior',
        'photo_url': null,
        'editions': 1,
      },
    ])
    ..vjPages['vj-emmy'] = {
      'id': 'v2',
      'name': 'VJ Emmy',
      'slug': 'vj-emmy',
      'photo_url': null,
      'editions': 2,
      'bio': 'Emmy translates dramas.',
      'movies': [card('m2', title: 'Rambo', vj: 'VJ Emmy')],
      'series': [card('s1', kind: 'series', title: 'Kabaka', vj: 'VJ Emmy')],
    };
  return api;
}

Future<void> openEdition(WidgetTester tester, String title) async {
  final tile = find.widgetWithText(MovieCard, title).first;
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

VeloraButton button(WidgetTester tester, String label) =>
    tester.widget<VeloraButton>(find.widgetWithText(VeloraButton, label));

void main() {
  testWidgets(
    'saves a movie and one episode and opens Watch List from Account',
    (tester) async {
      final api = catalogue()
        ..watchListItems['item-m1'] = {
          'item_id': 'item-m1',
          'edition': card('m1'),
          'season': null,
          'episode': null,
          'episode_title': null,
        }
        ..watchListItems['e11'] = {
          'item_id': 'e11',
          'edition': card('s1', kind: 'series', title: 'Kabaka'),
          'season': 1,
          'episode': 1,
          'episode_title': 'The Crown',
        };
      final l = AppLocalizationsEn();
      await pumpApp(tester, api, signedIn: true);
      await openEdition(tester, 'Fast X');
      await tester.tap(find.text(l.watchListAdd));
      await tester.pumpAndSettle();
      expect(find.text(l.watchListRemove), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await openEdition(tester, 'Kabaka');
      final episode = find.byKey(const ValueKey('e11'));
      final saveEpisode = find.descendant(
        of: episode,
        matching: find.byTooltip(l.watchListAdd),
      );
      await tester.ensureVisible(saveEpisode);
      await tester.tap(saveEpisode);
      await tester.pumpAndSettle();
      expect(api.watchList.keys, unorderedEquals(['item-m1', 'e11']));
      expect(
        find.descendant(
          of: episode,
          matching: find.byTooltip(l.watchListRemove),
        ),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      await goTo(tester, 'Account');
      final watchList = find.text(l.watchListTitle);
      await tester.ensureVisible(watchList);
      await tester.tap(watchList);
      await tester.pumpAndSettle();
      expect(find.text('Fast X'), findsOneWidget);
      expect(find.text(l.episodeHeading('Kabaka', 1, 1)), findsOneWidget);
      final remove = find.descendant(
        of: find.byKey(const ValueKey('e11')),
        matching: find.byTooltip(l.watchListRemove),
      );
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(api.watchList.keys, ['item-m1']);
      expect(find.text(l.episodeHeading('Kabaka', 1, 1)), findsNothing);
    },
  );

  group('home', () {
    testWidgets('has Latest, Movies, Series and a row per VJ', (tester) async {
      final api = catalogue();
      await pumpApp(tester, api);

      for (final row in [
        'Latest',
        'Movies',
        'Series',
        'VJ Emmy',
        'VJ Junior',
      ]) {
        expect(
          find.descendant(of: find.byType(Semantics), matching: find.text(row)),
          findsWidgets,
          reason: row,
        );
      }
      // Only one language: no language rows.
      expect(find.text('In Luganda'), findsNothing);
      final asked = api.requests.map((r) => r.url.queryParameters).toList();
      expect(asked, contains(equals({'limit': '12', 'vj': 'vj-emmy'})));
      expect(asked, contains(equals({'limit': '12', 'kind': 'series'})));
    });

    testWidgets('a second language adds a row per language', (tester) async {
      final api = catalogue()
        ..languages = [
          {'code': 'lg', 'name': 'Luganda', 'editions': 3},
          {'code': 'nyn', 'name': 'Runyankole', 'editions': 1},
        ]
        ..editions.add(
          card('n1', title: 'Omukama', vj: 'VJ Kats', language: 'nyn'),
        );
      await pumpApp(tester, api);

      expect(find.text('In Luganda'), findsOneWidget);
      expect(find.text('In Runyankole'), findsOneWidget);
    });

    testWidgets("a poster shows only the VJ's name, read with the title", (
      tester,
    ) async {
      await pumpApp(tester, catalogue());

      final fast = tester.widget<MovieCard>(
        find.widgetWithText(MovieCard, 'Fast X').first,
      );
      expect(fast.cornerLabel, 'VJ Junior');
      expect(find.text('Luganda · VJ Junior'), findsNothing);
      expect(
        find.bySemanticsLabel(RegExp(r'^Fast X, VJ Junior, 2023')),
        findsWidgets,
      );
      final test = tester.widget<MovieCard>(
        find.widgetWithText(MovieCard, 'The Matrix').first,
      );
      expect(test.cornerLabel, isNull);
    });

    testWidgets('See all opens every series, a page at a time', (tester) async {
      final api = catalogue();
      await pumpApp(tester, api);

      final seeAll = find.bySemanticsLabel('See all of Series');
      await tester.ensureVisible(seeAll);
      await tester.tap(seeAll);
      await tester.pumpAndSettle();

      expect(api.requests.last.url.queryParameters['kind'], 'series');
      expect(find.widgetWithText(MovieCard, 'Kabaka'), findsOneWidget);
      expect(find.widgetWithText(MovieCard, 'Fast X'), findsNothing);
    });

    testWidgets('an empty catalogue says so', (tester) async {
      await pumpApp(tester, FakeApi()..languages = []);

      expect(find.text('Nothing to watch yet'), findsOneWidget);
    });

    testWidgets('a failure explains itself, and Try again recovers', (
      tester,
    ) async {
      final api = catalogue()..catalogueStatus = 503;
      await pumpApp(tester, api);

      expect(find.text("Couldn't load the catalogue"), findsOneWidget);
      expect(
        find.text('VeloraUG is busy right now. Try again in a moment.'),
        findsOneWidget,
      );

      api.catalogueStatus = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Latest'), findsOneWidget);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('fits a 320-pixel phone at text size $scale', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final api = catalogue();
        api.editions.add(
          card(
            'long',
            title: 'A rather long translated movie title',
            vj: 'VJ Long Name Here',
          ),
        );
        await pumpApp(tester, api, size: const Size(320, 640));
        expect(tester.takeException(), isNull);

        await openEdition(tester, 'Kabaka');
        expect(tester.takeException(), isNull);
        expect(find.text('A king rises.'), findsOneWidget);
      });
    }
  });

  group('VJ page', () {
    testWidgets("a row's See all opens the VJ, with bio, movies and series", (
      tester,
    ) async {
      await pumpApp(tester, catalogue());

      final seeAll = find.bySemanticsLabel('See all of VJ Emmy');
      await tester.ensureVisible(seeAll);
      await tester.tap(seeAll);
      await tester.pumpAndSettle();

      expect(find.text('Emmy translates dramas.'), findsOneWidget);
      expect(find.text('Movies'), findsOneWidget);
      expect(find.widgetWithText(MovieCard, 'Rambo'), findsOneWidget);
      expect(find.widgetWithText(MovieCard, 'Kabaka'), findsOneWidget);
    });

    testWidgets("the edition's label opens its VJ", (tester) async {
      await pumpApp(tester, catalogue());
      await openEdition(tester, 'Kabaka');

      await tester.tap(find.text('Luganda · VJ Emmy'));
      await tester.pumpAndSettle();
      expect(find.text('Emmy translates dramas.'), findsOneWidget);
    });
  });

  group('a movie edition', () {
    testWidgets('shows its label, details and trailer', (tester) async {
      await pumpApp(tester, catalogue());
      await openEdition(tester, 'Fast X');

      expect(find.byType(EditionScreen), findsOneWidget);
      expect(find.text('Luganda · VJ Junior'), findsOneWidget);
      // The year under the title, and the runtime among the badges.
      expect(find.text('2023'), findsOneWidget);
      expect(find.text('2 h 21 min'), findsOneWidget);
      expect(find.text('Movie'), findsOneWidget);
      expect(find.text('Dom races again.'), findsOneWidget);
      expect(find.text('Trailer'), findsOneWidget);
    });

    testWidgets('signed in, Watch plays its item', (tester) async {
      final api = catalogue();
      await pumpApp(tester, api, signedIn: true);
      await openEdition(tester, 'Fast X');

      await tester.tap(find.text('Watch'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(api.granted, ['item-m1']);
    });

    testWidgets('signed out, it asks the viewer to sign in', (tester) async {
      final api = catalogue();
      await pumpApp(tester, api);
      await openEdition(tester, 'Fast X');

      expect(find.text('Watch'), findsNothing);
      expect(button(tester, 'Sign in to watch').onPressed, isNotNull);
      expect(api.grants, 0);
    });

    testWidgets('with nothing ready, it is Coming soon', (tester) async {
      final api = catalogue()
        ..details['m1'] = movieDetail('m1', playable: false, trailer: null);
      await pumpApp(tester, api, signedIn: true);
      await openEdition(tester, 'Fast X');

      expect(find.text('Coming soon'), findsOneWidget);
      expect(button(tester, 'Watch').onPressed, isNull);
      expect(find.text('Trailer'), findsNothing);
    });

    testWidgets('a removed edition says so, and Back returns', (tester) async {
      final api = catalogue()..details.remove('m1');
      await pumpApp(tester, api);
      await openEdition(tester, 'Fast X');

      expect(find.text("This title isn't available"), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(EditionScreen), findsNothing);
    });
  });

  group('a series edition', () {
    testWidgets('lists its seasons and episodes', (tester) async {
      await pumpApp(tester, catalogue(), signedIn: true);
      await openEdition(tester, 'Kabaka');

      expect(find.text('Season 1'), findsOneWidget);
      expect(find.text('Season 2'), findsOneWidget);
      expect(find.text('Episode 1'), findsOneWidget);
      expect(find.text('The Crown'), findsOneWidget);
      expect(find.text('Episode 2'), findsOneWidget);

      await tester.tap(find.text('Season 2'));
      await tester.pumpAndSettle();
      expect(find.text('The Crown'), findsNothing);
      expect(find.byTooltip('Play season 2, episode 1'), findsOneWidget);
    });

    testWidgets('signed out, episodes ask for sign-in first', (tester) async {
      await pumpApp(tester, catalogue());
      await openEdition(tester, 'Kabaka');

      expect(find.text('Sign in to watch'), findsOneWidget);
      expect(find.text('Sign in first'), findsNWidgets(2));
      expect(find.byTooltip('Play season 1, episode 1'), findsNothing);
    });

    testWidgets('an episode plays, and Next Episode follows the series', (
      tester,
    ) async {
      final api = catalogue();
      await pumpApp(tester, api, signedIn: true);
      await openEdition(tester, 'Kabaka');

      await tester.tap(find.byTooltip('Play season 1, episode 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Kabaka · S1 E1'), findsOneWidget);
      expect(api.granted, ['e11']);
      expect(
        find.byTooltip('Next episode: season 1, episode 2'),
        findsOneWidget,
      );
    });
  });

  group('the player', () {
    const episodes = [
      Episode(itemId: 'e11', season: 1, episode: 1, playable: true),
      Episode(itemId: 'e12', season: 1, episode: 2, playable: true),
      Episode(itemId: 'e21', season: 2, episode: 1, playable: true),
    ];

    Future<FakeVideo> pumpPlayer(
      WidgetTester tester,
      FakeApi api, {
      String itemId = 'e11',
      List<Episode> episodes = const [],
      DateTime Function()? clock,
    }) async {
      final auth = fakeAuth(signedIn: true);
      await auth.restore();
      final video = FakeVideo();
      await tester.pumpWidget(
        PlaybackScope(
          api: api.playback(auth),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: PlayerScreen(
              itemId: itemId,
              title: 'Kabaka',
              episodes: episodes,
              viewBuilder: video.build,
              clock: clock ?? () => DateTime.utc(2026),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return video;
    }

    testWidgets('plays the granted playlist from the start', (tester) async {
      final api = FakeApi();
      final video = await pumpPlayer(tester, api, itemId: 'movie-item');

      expect(find.text('playing grant-1.sig'), findsOneWidget);
      expect(
        video.requests.last.url.toString(),
        '$gateway/v1/grant-1.sig/master.m3u8',
      );
      expect(video.requests.last.startAt, Duration.zero);
      expect(api.requests.first.url.path, '/api/v1/items/movie-item/playback');
      // The master playlist is read for its qualities, without the token.
      expect(api.requests.last.url.path, '/v1/grant-1.sig/master.m3u8');
      expect(api.requests.last.headers['Authorization'], isNull);
      // A movie has no next episode.
      expect(find.byIcon(Icons.skip_next), findsNothing);
    });

    group('quality', () {
      setUp(() => PlayerScreen.chosenHeight = null);
      tearDown(() => PlayerScreen.chosenHeight = null);

      Future<void> choose(
        WidgetTester tester,
        String current,
        String to,
      ) async {
        await tester.tap(find.byTooltip('Quality: $current'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(to));
        await tester.pumpAndSettle();
      }

      testWidgets('the gear lists Auto and each quality, highest first', (
        tester,
      ) async {
        await pumpPlayer(tester, FakeApi(), itemId: 'movie-item');

        await tester.tap(find.byTooltip('Quality: Auto'));
        await tester.pumpAndSettle();

        final labels = ['Auto', '1080p', '720p', '480p', '360p'];
        final ys = [
          for (final label in labels) tester.getTopLeft(find.text(label)).dy,
        ];
        expect(ys, [...ys]..sort());
        expect(find.text('Changes with your connection'), findsOneWidget);
        expect(find.text('HD'), findsNWidgets(2));
      });

      testWidgets('a quality plays from the same moment, and Auto goes back', (
        tester,
      ) async {
        final api = FakeApi();
        final video = await pumpPlayer(tester, api, itemId: 'movie-item');

        video.requests.last.onProgress!(const Duration(minutes: 12));
        await choose(tester, 'Auto', '480p');

        expect(
          video.requests.last.url.toString(),
          '$gateway/v1/grant-1.sig/480p/index.m3u8',
        );
        expect(video.requests.last.startAt, const Duration(minutes: 12));
        expect(find.byTooltip('Quality: 480p'), findsOneWidget);
        // The same grant: switching asks the API for nothing.
        expect(api.grants, 1);

        video.requests.last.onProgress!(const Duration(minutes: 20));
        await choose(tester, '480p', 'Auto');

        expect(
          video.requests.last.url.toString(),
          '$gateway/v1/grant-1.sig/master.m3u8',
        );
        expect(video.requests.last.startAt, const Duration(minutes: 20));
      });

      testWidgets('the choice is kept for the next episode and a new grant', (
        tester,
      ) async {
        final api = FakeApi()..expiresAt = DateTime.utc(2026, 1, 1, 6);
        var now = DateTime.utc(2026, 1, 1, 1);
        final video = await pumpPlayer(
          tester,
          api,
          episodes: episodes,
          clock: () => now,
        );
        await choose(tester, 'Auto', '720p');

        now = DateTime.utc(2026, 1, 1, 6, 0, 5);
        video.requests.last.onFailed(const Duration(minutes: 40));
        await tester.pumpAndSettle();
        expect(
          video.requests.last.url.toString(),
          '$gateway/v1/grant-2.sig/720p/index.m3u8',
        );
        expect(video.requests.last.startAt, const Duration(minutes: 40));

        await tester.tap(find.byTooltip('Next episode: season 1, episode 2'));
        await tester.pumpAndSettle();
        expect(
          video.requests.last.url.toString(),
          '$gateway/v1/grant-3.sig/720p/index.m3u8',
        );
        expect(video.requests.last.startAt, Duration.zero);
      });

      testWidgets('a quality this video lacks falls back to Auto', (
        tester,
      ) async {
        PlayerScreen.chosenHeight = 1440;
        final video = await pumpPlayer(tester, FakeApi(), itemId: 'movie-item');

        expect(video.requests.last.url.path, endsWith('/master.m3u8'));
        expect(find.byTooltip('Quality: Auto'), findsOneWidget);
      });

      testWidgets('without readable qualities, there is no gear', (
        tester,
      ) async {
        final api = FakeApi()..masterPlaylist = 'not a playlist';
        final video = await pumpPlayer(tester, api, itemId: 'movie-item');

        expect(find.byIcon(Icons.settings_outlined), findsNothing);
        expect(video.requests.last.url.path, endsWith('/master.m3u8'));
      });
    });

    testWidgets('at the end of an episode, Next Episode plays the next', (
      tester,
    ) async {
      final api = FakeApi();
      final video = await pumpPlayer(tester, api, episodes: episodes);

      video.requests.last.onEnded!();
      await tester.pumpAndSettle();
      expect(find.text('Up next: S1 E2'), findsOneWidget);

      await tester.tap(find.widgetWithText(VeloraButton, 'Next episode'));
      await tester.pumpAndSettle();

      expect(api.granted, ['e11', 'e12']);
      expect(find.text('Kabaka · S1 E2'), findsOneWidget);
      expect(find.text('playing grant-2.sig'), findsOneWidget);
      expect(video.requests.last.startAt, Duration.zero);
    });

    testWidgets('Next Episode goes on to the next season', (tester) async {
      final api = FakeApi();
      await pumpPlayer(tester, api, itemId: 'e12', episodes: episodes);

      await tester.tap(find.byTooltip('Next episode: season 2, episode 1'));
      await tester.pumpAndSettle();

      expect(api.granted, ['e12', 'e21']);
      expect(find.text('Kabaka · S2 E1'), findsOneWidget);
      // The last episode has nothing after it.
      expect(find.byIcon(Icons.skip_next), findsNothing);
    });

    testWidgets('a grant that ran out is renewed, from the same moment', (
      tester,
    ) async {
      final api = FakeApi()..expiresAt = DateTime.utc(2026, 1, 1, 6);
      var now = DateTime.utc(2026, 1, 1, 1);
      final video = await pumpPlayer(tester, api, clock: () => now);

      now = DateTime.utc(2026, 1, 1, 6, 0, 5);
      video.requests.last.onFailed(const Duration(minutes: 97));
      await tester.pumpAndSettle();

      expect(api.grants, 2);
      expect(find.text('playing grant-2.sig'), findsOneWidget);
      expect(video.requests.last.startAt, const Duration(minutes: 97));
    });

    testWidgets('a renewed grant that fails again stops, without looping', (
      tester,
    ) async {
      final api = FakeApi()..expiresAt = DateTime.utc(2026, 1, 1, 6);
      final video = await pumpPlayer(
        tester,
        api,
        clock: () => DateTime.utc(2026, 1, 1, 7),
      );

      video.requests.last.onFailed(const Duration(minutes: 1));
      await tester.pumpAndSettle();
      video.requests.last.onFailed(const Duration(minutes: 1));
      await tester.pumpAndSettle();

      expect(api.grants, 2);
      expect(find.text("Couldn't play this"), findsOneWidget);
    });

    testWidgets('any other stop offers Try again, from the same moment', (
      tester,
    ) async {
      final api = FakeApi();
      final video = await pumpPlayer(tester, api);

      video.requests.last.onFailed(const Duration(seconds: 42));
      await tester.pumpAndSettle();
      expect(find.textContaining('Playback stopped'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(api.grants, 2);
      expect(video.requests.last.startAt, const Duration(seconds: 42));
    });

    for (final (status, words) in [
      (409, "can't be watched yet"),
      (404, "isn't available"),
      (401, "didn't accept your sign-in"),
      (503, 'busy'),
    ]) {
      testWidgets('a $status grant says so', (tester) async {
        final api = FakeApi()..grantStatus = status;
        final video = await pumpPlayer(tester, api);

        expect(find.textContaining(words), findsOneWidget);
        expect(video.requests, isEmpty);
      });
    }
  });

  group('search', () {
    testWidgets('waits for two letters and a pause, and finds VJs too', (
      tester,
    ) async {
      final api = catalogue();
      await pumpApp(tester, api);
      await goTo(tester, 'Search');

      await tester.enterText(find.byType(TextField), 'e');
      await tester.pump(searchDelay * 2);
      expect(api.searches, isEmpty);
      expect(find.text('Find a movie, series or VJ'), findsOneWidget);

      await tester.enterText(find.byType(TextField), ' emmy ');
      await tester.pump(searchDelay);
      await tester.pumpAndSettle();
      expect(api.searches.single.queryParameters['q'], 'emmy');
      expect(find.text('2 results for "emmy"'), findsOneWidget);
    });

    testWidgets('a slow earlier answer never replaces a newer one', (
      tester,
    ) async {
      final slow = Completer<http.Response>();
      final api = catalogue()
        ..editions.add(card('m9', title: 'Inception', vj: 'VJ Junior'))
        ..intercept = (request) =>
            request.url.queryParameters['q'] == 'fast' ? slow.future : null;
      await pumpApp(tester, api);
      await goTo(tester, 'Search');

      await tester.enterText(find.byType(TextField), 'fast');
      await tester.pump(searchDelay);
      await tester.enterText(find.byType(TextField), 'incep');
      await tester.pump(searchDelay);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MovieCard, 'Inception'), findsOneWidget);

      slow.complete(
        json({
          'editions': [card('m1', title: 'Fast X')],
          'next_offset': null,
        }),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MovieCard, 'Inception'), findsOneWidget);
      expect(find.widgetWithText(MovieCard, 'Fast X'), findsNothing);
    });

    testWidgets('nothing found says so, and a failure can be retried', (
      tester,
    ) async {
      final api = catalogue()..catalogueStatus = 500;
      await pumpApp(tester, api);
      api.catalogueStatus = 500;
      await goTo(tester, 'Search');

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text("Couldn't search"), findsOneWidget);

      api.catalogueStatus = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches'), findsOneWidget);
    });
  });

  testWidgets('Settings credits TMDB with its exact notice', (tester) async {
    await pumpApp(tester, catalogue());
    await goTo(tester, 'Account');
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    final l = AppLocalizationsEn();
    // Folded away until Credits is tapped.
    expect(find.text(l.tmdbNotice), findsNothing);
    await tester.ensureVisible(find.text('Credits'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Credits'));
    await tester.pumpAndSettle();
    expect(find.text(l.tmdbNotice), findsOneWidget);
    expect(
      l.tmdbNotice,
      'This product uses the TMDB API but is not endorsed or certified by '
      'TMDB.',
    );
    final logo = tester.widget<Image>(
      find.byWidgetPredicate(
        (widget) => widget is Image && widget.semanticLabel == 'TMDB logo',
      ),
    );
    expect((logo.image as AssetImage).assetName, tmdbLogoAsset);
    expect(logo.height, 16);
  });

  test('runtimes read naturally', () {
    final l = AppLocalizationsEn();
    expect(formatRuntime(l, 169), '2 h 49 min');
    expect(formatRuntime(l, 45), '45 min');
    expect(formatRuntime(l, 120), '2 h');
  });
}
