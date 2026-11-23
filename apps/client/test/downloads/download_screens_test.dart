import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/downloads/download_manager.dart';
import 'package:veloraug/downloads/download_storage.dart';
import 'package:veloraug/l10n/app_localizations.dart';
import 'package:veloraug/screens/offline_player_screen.dart';
import 'package:veloraug/widgets/movie_card.dart';

import '../support.dart';
import 'download_fakes.dart' as fakes;

/// The catalogue, with the movie's and the series' items as real IDs, as
/// the API gives them.
FakeApi catalogue() {
  final series = seriesDetail('s1');
  final seasons = series['seasons']! as List<Map<String, Object?>>;
  final firstEpisode =
      (seasons.first['episodes']! as List<Map<String, Object?>>).first;
  firstEpisode['item_id'] = fakes.episodeId;
  return FakeApi()
    ..editions.addAll([
      card('m1', title: 'Fast X', vj: 'VJ Junior'),
      card('s1', kind: 'series', title: 'Kabaka', vj: 'VJ Emmy'),
    ])
    ..details['m1'] = {...movieDetail('m1'), 'item_id': fakes.movieId}
    ..details['s1'] = series;
}

Future<void> openEdition(WidgetTester tester, String title) async {
  await tester.tap(find.widgetWithText(MovieCard, title).first);
  await tester.pumpAndSettle();
}

/// Lets the download run to its end.
Future<void> finish(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

void main() {
  late fakes.FakeMediaServer server;
  late MemoryDownloadStorage storage;
  late DownloadManager downloads;

  setUp(() {
    server = fakes.FakeMediaServer();
    storage = MemoryDownloadStorage();
    downloads = fakes.manager(server, storage);
  });

  tearDown(() => downloads.dispose());

  testWidgets('without downloads, as on the web, nothing offers them', (
    tester,
  ) async {
    await pumpApp(tester, catalogue(), signedIn: true);

    expect(find.text('Downloads'), findsNothing);
    await openEdition(tester, 'Fast X');
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('signed out, a movie offers sign-in, not Download', (
    tester,
  ) async {
    await pumpApp(tester, catalogue(), downloads: downloads);
    await openEdition(tester, 'Fast X');

    expect(find.text('Download'), findsNothing);
  });

  testWidgets(
    'a movie is downloaded in the quality chosen, then plays offline',
    (tester) async {
      await pumpApp(tester, catalogue(), signedIn: true, downloads: downloads);
      await openEdition(tester, 'Fast X');

      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(find.text('Download quality'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);
      expect(find.text('360p'), findsOneWidget);
      // 30 seconds at 800 kbit/s.
      expect(find.text('About 3 MB'), findsOneWidget);

      await tester.tap(find.text('360p'));
      await finish(tester);

      expect(find.text('Downloading Fast X.'), findsOneWidget);
      expect(find.text('Downloaded'), findsOneWidget);
      expect(downloads[fakes.movieId]!.quality.label, '360p');

      await tester.tap(find.text('Downloaded'));
      await tester.pump();
      await tester.pump();
      expect(find.byType(OfflinePlayerScreen), findsOneWidget);
    },
  );

  testWidgets('without a pass, the sheet says so and offers a plan', (
    tester,
  ) async {
    server.grantStatus = 402;
    await pumpApp(tester, catalogue(), signedIn: true, downloads: downloads);
    await openEdition(tester, 'Fast X');

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't start the download"), findsOneWidget);
    expect(find.text('Choose a plan'), findsOneWidget);
    expect(downloads.downloads, isEmpty);
  });

  testWidgets('each playable episode has its own Download', (tester) async {
    await pumpApp(tester, catalogue(), signedIn: true, downloads: downloads);
    await openEdition(tester, 'Kabaka');

    expect(find.byTooltip('Download season 1, episode 1'), findsOneWidget);
    expect(find.byTooltip('Download season 1, episode 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Download season 1, episode 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('720p'));
    await finish(tester);

    final done = downloads[fakes.episodeId]!;
    expect(done.state, DownloadState.done);
    expect(done.info.season, 1);
    expect(done.info.episodeTitle, 'The Crown');
    expect(
      find.byTooltip('Download season 1, episode 1: Downloaded'),
      findsOneWidget,
    );
  });

  group('the Downloads tab', () {
    Future<void> downloadMovie(WidgetTester tester) async {
      await tester.runAsync(() async {
        await downloads.load();
        final offer = await downloads.prepare(fakes.movieId);
        await downloads.start(offer, offer.qualities.first, fakes.movieInfo);
        for (var i = 0; i < 200; i++) {
          if (downloads[fakes.movieId]!.state == DownloadState.done) break;
          await Future<void>.delayed(Duration.zero);
        }
      });
    }

    testWidgets('says how to download when there is nothing yet', (
      tester,
    ) async {
      await pumpApp(tester, catalogue(), signedIn: true, downloads: downloads);
      await goTo(tester, 'Downloads');

      expect(find.text('No downloads yet'), findsOneWidget);
    });

    testWidgets('lists a download with its quality, size and licence', (
      tester,
    ) async {
      await downloadMovie(tester);
      await pumpApp(tester, catalogue(), signedIn: true, downloads: downloads);
      await goTo(tester, 'Downloads');

      expect(find.text('Fast X'), findsOneWidget);
      expect(find.text('Luganda · VJ Junior'), findsOneWidget);
      expect(find.textContaining('720p · '), findsOneWidget);
      expect(find.textContaining('Plays offline until'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Play'), findsOneWidget);
    });

    testWidgets('a download is deleted only once confirmed', (tester) async {
      await downloadMovie(tester);
      await pumpApp(tester, catalogue(), signedIn: true, downloads: downloads);
      await goTo(tester, 'Downloads');

      await tester.tap(find.byTooltip('Delete download'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(downloads[fakes.movieId], isNotNull);

      await tester.tap(find.byTooltip('Delete download'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(downloads[fakes.movieId], isNull);
      expect(storage.files[fakes.movieId], isNull);
      expect(find.text('No downloads yet'), findsOneWidget);
    });

    testWidgets('a licence run out asks to connect, and Check now renews it', (
      tester,
    ) async {
      await downloadMovie(tester);
      server.now = server.offlineUntil.add(const Duration(hours: 1));
      server.licenceStatus = 500;
      await pumpApp(tester, catalogue(), signedIn: true, downloads: downloads);
      await goTo(tester, 'Downloads');

      expect(
        find.text('Connect to the internet to keep watching this download.'),
        findsOneWidget,
      );

      server
        ..licenceStatus = 200
        ..offlineUntil = server.now.add(const Duration(days: 7));
      await tester.tap(find.text('Check now'));
      await tester.pumpAndSettle();

      expect(find.text('Check now'), findsNothing);
      expect(find.textContaining('Plays offline until'), findsOneWidget);
    });

    testWidgets('an ended pass offers a plan on the download', (tester) async {
      await downloadMovie(tester);
      server.licenceStatus = 402;
      await tester.runAsync(() => downloads.renewLicences(force: true));
      await pumpApp(tester, catalogue(), signedIn: true, downloads: downloads);
      await goTo(tester, 'Downloads');

      expect(
        find.text(
          'Your pass has ended. Choose a plan to watch your downloads again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Choose a plan'), findsOneWidget);
    });
  });

  testWidgets('the offline player plays the download’s own playlist', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await downloads.load();
      final offer = await downloads.prepare(fakes.movieId);
      await downloads.start(offer, offer.qualities.last, fakes.movieInfo);
      for (var i = 0; i < 200; i++) {
        if (downloads[fakes.movieId]!.state == DownloadState.done) break;
        await Future<void>.delayed(Duration.zero);
      }
    });
    final video = FakeVideo();
    await tester.pumpWidget(
      DownloadsScope(
        manager: downloads,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: OfflinePlayerScreen(
            download: downloads[fakes.movieId]!,
            viewBuilder: video.build,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(video.requests.single.url.scheme, 'file');
    expect(video.requests.single.url.path, endsWith('/master.m3u8'));
    expect(video.requests.single.url.path, contains(fakes.movieId));
  });
}
