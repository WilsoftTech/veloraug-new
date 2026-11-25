import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/api/account_api.dart';
import 'package:veloraug/api/catalogue_api.dart';
import 'package:veloraug/downloads/download_ui.dart';
import 'package:veloraug/downloads/downloads.dart';
import 'package:veloraug/l10n/app_localizations.dart';
import 'package:veloraug/theme/velora_theme.dart';
import 'package:veloraug/widgets/episode_row.dart';
import 'package:veloraug/widgets/movie_card.dart';

import 'downloads/download_fakes.dart' as fakes;
import 'support.dart';

/// Kabaka, with running times on its episodes.
FakeApi kabaka() {
  final detail = seriesDetail('s1');
  for (final season in detail['seasons'] as List) {
    for (final e in (season as Map)['episodes'] as List) {
      (e as Map)['runtime_minutes'] = 42;
    }
  }
  return FakeApi()
    ..editions.add(card('s1', kind: 'series', title: 'Kabaka', vj: 'VJ Emmy'))
    ..details['s1'] = detail;
}

Future<void> openKabaka(
  WidgetTester tester,
  FakeApi api, {
  bool signedIn = true,
  Size size = const Size(1200, 1600),
}) async {
  await pumpApp(tester, api, signedIn: signedIn, size: size);
  final tile = find.widgetWithText(MovieCard, 'Kabaka').first;
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Finder row(String itemId) => find.byKey(ValueKey(itemId));

const episodeInfo = DownloadInfo(
  editionId: 's1',
  title: 'Kabaka',
  label: 'Luganda · VJ Emmy',
  season: 1,
  episode: 3,
);

void main() {
  group('the row', () {
    testWidgets('number and name, running time, and its buttons', (
      tester,
    ) async {
      await openKabaka(tester, kabaka());

      final first = row('e11');
      expect(
        find.descendant(of: first, matching: find.text('1 · The Crown')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: first, matching: find.text('42 min')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: first, matching: find.text('E1')),
        findsOneWidget,
      );
      expect(find.byTooltip('Play season 1, episode 1'), findsOneWidget);
      // No progress without having played it.
      expect(find.byKey(const ValueKey('progress-e11')), findsNothing);
    });

    testWidgets('how far the viewer got: a bar, time left, or Watched', (
      tester,
    ) async {
      final api = kabaka()
        ..progress['s1'] = [
          {'item_id': 'e11', 'position_seconds': 1260, 'finished': false},
          {'item_id': 'e12', 'position_seconds': null, 'finished': true},
        ];
      await openKabaka(tester, api);

      final half = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('progress-e11')),
      );
      expect(half.value, closeTo(0.5, 0.01));
      expect(half.semanticsLabel, '50% watched');
      expect(
        find.descendant(of: row('e11'), matching: find.text('21 min left')),
        findsOneWidget,
      );
      final done = tester.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('progress-e12')),
      );
      expect(done.value, 1);
      expect(
        find.descendant(of: row('e12'), matching: find.text('Watched')),
        findsOneWidget,
      );
      expect(
        api.requests.where(
          (r) => r.url.path == '/api/v1/me/editions/s1/progress',
        ),
        hasLength(1),
      );
    });

    testWidgets('signed out, no progress is asked for', (tester) async {
      final api = kabaka();
      await openKabaka(tester, api, signedIn: false);

      expect(
        api.requests.where((r) => r.url.path.contains('/progress')),
        isEmpty,
      );
      expect(find.text('Sign in first'), findsWidgets);
    });

    testWidgets('a failed progress load leaves the rows without bars', (
      tester,
    ) async {
      final api = kabaka()
        ..intercept = (request) => request.url.path.endsWith('/progress')
            ? Future.error(Exception('offline'))
            : null;
      await openKabaka(tester, api);

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('1 · The Crown'), findsOneWidget);
    });

    testWidgets('the thumbnail plays with a pointer', (tester) async {
      final api = kabaka();
      await openKabaka(tester, api);

      await tester.tap(
        find.descendant(of: row('e11'), matching: find.text('E1')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(api.granted, ['e11']);
    });

    testWidgets('Play, Download and Watch List are 48 by 48, in that order', (
      tester,
    ) async {
      final api = kabaka();
      await openKabaka(tester, api);

      final buttons = find.descendant(
        of: row('e11'),
        matching: find.byType(IconButton),
      );
      expect(buttons, findsWidgets);
      for (final button in tester.widgetList<IconButton>(buttons)) {
        final size = tester.getSize(find.byWidget(button));
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
      // Tab goes Play, then the next button in the row.
      final play = find.byTooltip('Play season 1, episode 1');
      final playX = tester.getTopLeft(play).dx;
      for (final other in tester.widgetList<IconButton>(buttons).skip(1)) {
        expect(tester.getTopLeft(find.byWidget(other)).dx, greaterThan(playX));
      }
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('fits a 320-pixel phone at text size $scale', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final api = kabaka()
          ..progress['s1'] = [
            {'item_id': 'e11', 'position_seconds': 600, 'finished': false},
          ];
        await openKabaka(tester, api, size: const Size(320, 1400));
        await tester.ensureVisible(row('e11'));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // The title isn't squeezed beside the buttons.
        expect(
          tester.getSize(find.text('1 · The Crown')).width,
          greaterThan(80),
        );
      });
    }
  });

  group('the download button', () {
    late fakes.FakeMediaServer server;
    late fakes.FakeTarget target;

    setUp(() {
      server = fakes.FakeMediaServer();
      target = fakes.FakeTarget();
    });

    /// The button for S1 E3, with its download at [status], or none.
    Future<Downloads> pumpButton(
      WidgetTester tester, [
      FileStatus? status,
    ]) async {
      final downloads = Downloads(
        target: target,
        api: server.api(),
        checkEvery: const Duration(hours: 1),
      );
      await tester.runAsync(() async {
        await downloads.load();
        if (status != null) {
          final offer = await downloads.offer(fakes.episodeId);
          await downloads.start(
            fakes.episodeId,
            offer.files.first,
            episodeInfo,
          );
          target.statuses['1'] = status;
          await downloads.refresh();
        }
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          theme: buildVeloraTheme(),
          home: Scaffold(
            body: Center(
              child: DownloadsScope(
                downloads: downloads,
                child: const EpisodeDownloadButton(
                  itemId: fakes.episodeId,
                  info: episodeInfo,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      addTearDown(downloads.dispose);
      return downloads;
    }

    Finder icon(IconData data) => find.byIcon(data);
    const name = 'Download season 1, episode 3';

    testWidgets('not downloaded: an arrow, and it offers qualities', (
      tester,
    ) async {
      await pumpButton(tester);

      expect(icon(Icons.download_outlined), findsOneWidget);
      expect(find.byTooltip(name), findsOneWidget);
    });

    testWidgets('queued: a clock', (tester) async {
      await pumpButton(tester, const FileStatus(state: FileState.waiting));

      expect(icon(Icons.schedule), findsOneWidget);
      expect(find.byTooltip('$name: Waiting to download'), findsOneWidget);
    });

    testWidgets('downloading: a ring at its progress', (tester) async {
      await pumpButton(
        tester,
        const FileStatus(state: FileState.running, bytes: 450, total: 1000),
      );

      final ring = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(ring.value, closeTo(0.45, 0.001));
      expect(find.byTooltip('$name: Downloading 45%'), findsOneWidget);
    });

    testWidgets('paused: the ring with a pause mark', (tester) async {
      await pumpButton(
        tester,
        const FileStatus(
          state: FileState.paused,
          bytes: 300,
          total: 1000,
          pause: PauseReason.network,
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(icon(Icons.pause), findsOneWidget);
      expect(find.byTooltip('$name: Waiting for a connection'), findsOneWidget);
    });

    testWidgets('downloaded: a tick, and a tap plays the file', (tester) async {
      await pumpButton(
        tester,
        const FileStatus(state: FileState.done, bytes: 1000, total: 1000),
      );

      expect(icon(Icons.download_done), findsOneWidget);
      expect(find.byTooltip('$name: Downloaded'), findsOneWidget);
      await tester.tap(find.byType(IconButton));
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(target.opened, ['1']);
    });

    testWidgets('failed: a warning, and a tap tries again', (tester) async {
      await pumpButton(tester, const FileStatus(state: FileState.failed));

      expect(icon(Icons.error_outline), findsOneWidget);
      expect(
        find.byTooltip('$name: Download failed. Tap to try again'),
        findsOneWidget,
      );
      await tester.tap(find.byType(IconButton));
      await tester.pump();
      // The quality sheet opens again.
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets('each state is read out, on a 48 by 48 target', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpButton(
        tester,
        const FileStatus(state: FileState.running, bytes: 450, total: 1000),
      );

      expect(tester.getSize(find.byType(IconButton)), const Size(48, 48));
      expect(
        tester.getSemantics(find.byType(IconButton)),
        isSemantics(
          tooltip: '$name: Downloading 45%',
          isButton: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });
  });

  testWidgets('a movie\'s Download button uses the same looks', (tester) async {
    final downloads = Downloads(
      target: fakes.FakeTarget(),
      api: fakes.FakeMediaServer().api(),
      checkEvery: const Duration(hours: 1),
    );
    await tester.runAsync(downloads.load);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: buildVeloraTheme(),
        home: Scaffold(
          body: DownloadsScope(
            downloads: downloads,
            child: const DownloadButton(
              itemId: fakes.movieId,
              info: fakes.movieInfo,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Download'), findsOneWidget);
    expect(find.byIcon(Icons.download_outlined), findsOneWidget);
    downloads.dispose();
  });

  testWidgets('the row alone: Watched without a running time', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: buildVeloraTheme(),
        home: const Scaffold(
          body: EpisodeRow(
            episode: Episode(itemId: 'x', season: 1, episode: 4),
            progress: WatchProgress(finished: true),
            actions: [],
          ),
        ),
      ),
    );

    expect(find.text('Episode 4'), findsOneWidget);
    expect(find.text('Watched'), findsOneWidget);
  });
}
