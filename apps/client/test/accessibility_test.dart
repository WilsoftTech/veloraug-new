import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/downloads/downloads.dart';
import 'package:veloraug/screens/account/account_pages.dart';
import 'package:veloraug/widgets/movie_card.dart';

import 'downloads/download_fakes.dart' as fakes;
import 'support.dart';
import 'viewer_screens_test.dart' show catalogue;

/// Flutter's checks for 48-pixel tap targets, labelled targets and text
/// contrast, on what is on screen now.
Future<void> meetsGuidelines(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

Future<void> openTitle(WidgetTester tester, String title) async {
  final tile = find.widgetWithText(MovieCard, title).first;
  await tester.ensureVisible(tile);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

void main() {
  for (final (name, size) in [
    ('a phone', const Size(390, 1600)),
    ('a wide screen', const Size(1280, 1600)),
  ]) {
    group('on $name', () {
      testWidgets('Home, Search, Filter and Account', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpApp(tester, catalogue(), signedIn: true, size: size);

        await meetsGuidelines(tester);
        for (final screen in ['Search', 'Filter', 'Account']) {
          await goTo(tester, screen);
          await meetsGuidelines(tester);
        }
        semantics.dispose();
      });

      testWidgets("a movie's page and a series' page", (tester) async {
        final semantics = tester.ensureSemantics();
        final api = catalogue()
          ..progress['s1'] = [
            {'item_id': 'e11', 'position_seconds': 600, 'finished': false},
          ];
        await pumpApp(tester, api, signedIn: true, size: size);

        await openTitle(tester, 'Fast X');
        await meetsGuidelines(tester);
        await tester.pageBack();
        await tester.pumpAndSettle();

        await openTitle(tester, 'Kabaka');
        await meetsGuidelines(tester);
        semantics.dispose();
      });

      testWidgets('Downloads, with one running', (tester) async {
        debugAndroidAppOverride = true;
        addTearDown(() => debugAndroidAppOverride = null);
        final semantics = tester.ensureSemantics();
        final target = fakes.FakeTarget();
        final downloads = Downloads(
          target: target,
          api: fakes.FakeMediaServer().api(),
          checkEvery: const Duration(hours: 1),
        );
        await tester.runAsync(() async {
          await downloads.load();
          final offer = await downloads.offer(fakes.movieId);
          await downloads.start(
            fakes.movieId,
            offer.files.first,
            fakes.movieInfo,
          );
          target.statuses['1'] = const FileStatus(
            state: FileState.running,
            bytes: 300,
            total: 1000,
          );
          await downloads.refresh();
        });
        await pumpApp(
          tester,
          catalogue(),
          signedIn: true,
          size: size,
          downloads: downloads,
        );

        await goTo(tester, 'Downloads');
        await meetsGuidelines(tester);
        semantics.dispose();
        downloads.dispose();
      });
    });
  }

  testWidgets("on a series' page, Tab goes through each episode's Play, "
      'Download and Watch List in order', (tester) async {
    final downloads = Downloads(
      target: fakes.FakeTarget(),
      api: fakes.FakeMediaServer().api(),
      checkEvery: const Duration(hours: 1),
    );
    await tester.runAsync(downloads.load);
    await pumpApp(tester, catalogue(), signedIn: true, downloads: downloads);
    await openTitle(tester, 'Kabaka');

    final play = find.byTooltip('Play season 1, episode 1');
    await tester.ensureVisible(play);
    await tester.pumpAndSettle();
    Focus.of(
      tester.element(find.descendant(of: play, matching: find.byType(Icon))),
    ).requestFocus();
    await tester.pump();

    String? focusedTooltip() {
      final focused = FocusManager.instance.primaryFocus?.context;
      return focused?.findAncestorWidgetOfExactType<Tooltip>()?.message;
    }

    expect(focusedTooltip(), 'Play season 1, episode 1');
    final order = <String?>[];
    for (var i = 0; i < 3; i++) {
      FocusManager.instance.primaryFocus!.nextFocus();
      await tester.pump();
      order.add(focusedTooltip());
    }
    expect(order, [
      'Download season 1, episode 1',
      'Add to Watch List',
      'Play season 1, episode 2',
    ]);
    downloads.dispose();
  });
}
