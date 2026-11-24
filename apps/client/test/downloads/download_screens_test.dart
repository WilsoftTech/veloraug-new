import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/downloads/downloads.dart';
import 'package:veloraug/widgets/movie_card.dart';

import '../support.dart';
import 'download_fakes.dart' as fakes;

FakeApi catalogue() => FakeApi()
  ..editions.addAll([
    card('m1', title: 'Fast X', vj: 'VJ Junior'),
    card('s1', kind: 'series', title: 'Kabaka', vj: 'VJ Emmy'),
  ])
  ..details['m1'] = {...movieDetail('m1'), 'item_id': fakes.movieId}
  ..details['s1'] = seriesDetail('s1');

/// Pumps long enough for a sheet to close and a snack bar to show, without
/// waiting for a moving progress bar to stop.
Future<void> settleBriefly(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> openEdition(WidgetTester tester, String title) async {
  await tester.tap(find.widgetWithText(MovieCard, title).first);
  await tester.pumpAndSettle();
}

void main() {
  late fakes.FakeMediaServer server;
  late fakes.FakeTarget target;

  Downloads phone() => Downloads(
    target: target,
    api: server.api(),
    checkEvery: const Duration(hours: 1),
  );

  setUp(() {
    server = fakes.FakeMediaServer();
    target = fakes.FakeTarget();
  });

  testWidgets('without downloads, nothing offers them', (tester) async {
    await pumpApp(tester, catalogue(), signedIn: true);

    expect(find.text('Downloads'), findsNothing);
    await openEdition(tester, 'Fast X');
    expect(find.text('Download'), findsNothing);
  });

  testWidgets('signed out, a movie offers sign-in, not Download', (
    tester,
  ) async {
    await pumpApp(tester, catalogue(), downloads: phone());
    await openEdition(tester, 'Fast X');

    expect(find.text('Download'), findsNothing);
  });

  testWidgets('on a phone, the chosen quality is saved and followed', (
    tester,
  ) async {
    final downloads = phone();
    await pumpApp(tester, catalogue(), signedIn: true, downloads: downloads);
    expect(find.text('Downloads'), findsOneWidget);
    await openEdition(tester, 'Fast X');

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(find.text('Download quality'), findsOneWidget);
    expect(find.textContaining('Downloads/VeloraUG'), findsOneWidget);
    expect(find.text('1.2 GB'), findsOneWidget);
    expect(find.text('350 MB'), findsOneWidget);

    await tester.tap(find.text('360p'));
    // Waiting: its progress bar moves until Android starts it.
    await settleBriefly(tester);

    expect(
      find.text('Downloading Fast X - VJ Junior - 360p.mp4.'),
      findsOneWidget,
    );
    expect(target.started.single.url.path, endsWith('/360p/download.mp4'));
    expect(find.text('Waiting to download'), findsOneWidget);

    target.statuses['1'] = const FileStatus(
      state: FileState.done,
      bytes: 350000000,
      total: 350000000,
    );
    await downloads.refresh();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Downloaded'));
    await tester.pumpAndSettle();
    expect(target.opened, ['1']);
    downloads.dispose();
  });

  testWidgets('in a browser, the browser saves it and no tab is added', (
    tester,
  ) async {
    final browser = fakes.FakeTarget(followed: false);
    final downloads = Downloads(target: browser, api: server.api());
    await pumpApp(tester, catalogue(), signedIn: true, downloads: downloads);

    expect(find.text('Downloads'), findsNothing);
    await openEdition(tester, 'Fast X');
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(find.textContaining("computer's Downloads folder"), findsOneWidget);

    await tester.tap(find.text('720p'));
    await tester.pumpAndSettle();

    expect(
      find.text('Your browser is saving Fast X - VJ Junior - 720p.mp4.'),
      findsOneWidget,
    );
    expect(browser.started.single.fileName, 'Fast X - VJ Junior - 720p.mp4');
    // The button stays Download: the browser shows the progress.
    expect(find.text('Download'), findsOneWidget);
    downloads.dispose();
  });

  testWidgets('without a pass, the sheet offers a plan', (tester) async {
    server.grantStatus = 402;
    await pumpApp(tester, catalogue(), signedIn: true, downloads: phone());
    await openEdition(tester, 'Fast X');

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't start the download"), findsOneWidget);
    expect(find.text('Choose a plan'), findsOneWidget);
    expect(target.started, isEmpty);
  });

  testWidgets('a film whose files aren\'t made yet says so', (tester) async {
    server.sizes.clear();
    await pumpApp(tester, catalogue(), signedIn: true, downloads: phone());
    await openEdition(tester, 'Fast X');

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(
      find.text("This can't be downloaded yet. Try again later."),
      findsOneWidget,
    );
  });

  testWidgets('a refused storage permission says so', (tester) async {
    target.refuse = DownloadRefusal.noPermission;
    await pumpApp(tester, catalogue(), signedIn: true, downloads: phone());
    await openEdition(tester, 'Fast X');

    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('720p'));
    await tester.pumpAndSettle();

    expect(find.textContaining('needs permission'), findsOneWidget);
  });

  testWidgets('each playable episode has its own Download', (tester) async {
    final downloads = phone();
    await pumpApp(tester, catalogue(), signedIn: true, downloads: downloads);
    await openEdition(tester, 'Kabaka');

    expect(find.byTooltip('Download season 1, episode 1'), findsOneWidget);
    await tester.tap(find.byTooltip('Download season 1, episode 1'));
    await tester.pumpAndSettle();
    server.fileName = 'Kabaka - S01E01 - VJ Emmy';
    await tester.tap(find.text('720p'));
    await settleBriefly(tester);

    expect(target.started, hasLength(1));
    expect(
      find.byTooltip('Download season 1, episode 1: Waiting to download'),
      findsOneWidget,
    );
    downloads.dispose();
  });

  group('the Downloads tab', () {
    Future<Downloads> withOne(WidgetTester tester, FileStatus status) async {
      final downloads = phone();
      await tester.runAsync(() async {
        await downloads.load();
        final offer = await downloads.offer(fakes.movieId);
        await downloads.start(
          fakes.movieId,
          offer.files.first,
          fakes.movieInfo,
        );
      });
      target.statuses['1'] = status;
      await tester.runAsync(downloads.refresh);
      return downloads;
    }

    testWidgets('says how to download when there is nothing yet', (
      tester,
    ) async {
      await pumpApp(tester, catalogue(), signedIn: true, downloads: phone());
      await goTo(tester, 'Downloads');

      expect(find.text('No downloads yet'), findsOneWidget);
    });

    testWidgets('shows a running download\'s progress', (tester) async {
      final downloads = await withOne(
        tester,
        const FileStatus(state: FileState.running, bytes: 300, total: 1000),
      );
      await pumpApp(tester, catalogue(), signedIn: true, downloads: downloads);
      await goTo(tester, 'Downloads');

      expect(find.text('Fast X'), findsOneWidget);
      expect(find.textContaining('Downloading 30%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      downloads.dispose();
    });

    testWidgets('a finished download opens, or says why it can\'t', (
      tester,
    ) async {
      final downloads = await withOne(
        tester,
        const FileStatus(state: FileState.done, bytes: 1000, total: 1000),
      );
      await pumpApp(tester, catalogue(), signedIn: true, downloads: downloads);
      await goTo(tester, 'Downloads');
      expect(find.text('Fast X - VJ Junior - 720p.mp4'), findsOneWidget);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(target.opened, ['1']);

      target.canOpen = false;
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining("can't be opened"), findsOneWidget);
      downloads.dispose();
    });

    testWidgets('a full phone says so, and offers to download again', (
      tester,
    ) async {
      final downloads = await withOne(
        tester,
        const FileStatus(state: FileState.failed, noRoom: true),
      );
      await pumpApp(tester, catalogue(), signedIn: true, downloads: downloads);
      await goTo(tester, 'Downloads');

      expect(find.textContaining('Your phone is full'), findsOneWidget);
      expect(find.text('Download again'), findsOneWidget);
      downloads.dispose();
    });

    testWidgets('a download is deleted only once confirmed', (tester) async {
      final downloads = await withOne(
        tester,
        const FileStatus(state: FileState.done, total: 1000),
      );
      await pumpApp(tester, catalogue(), signedIn: true, downloads: downloads);
      await goTo(tester, 'Downloads');

      await tester.tap(find.byTooltip('Delete download'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(target.removed, isEmpty);

      await tester.tap(find.byTooltip('Delete download'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(target.removed, ['1']);
      expect(find.text('No downloads yet'), findsOneWidget);
      downloads.dispose();
    });
  });
}
