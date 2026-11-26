import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/admin/draft_screen.dart';
import 'package:veloraug/admin/drafts_view.dart' show draftsRefreshEvery;
import 'package:veloraug/admin/new_draft_screen.dart';
import 'package:veloraug/widgets/velora_button.dart';
import 'package:veloraug/screens/player_screen.dart';

import 'support.dart';

Map<String, Object?> item({
  String id = 'i1',
  int? season,
  int? episode,
  String? video = 'ready',
  bool approved = false,
  bool previewable = true,
  String? filename = 'Fast X VJ Junior.mp4',
  List<Map<String, Object?>> keys = const [],
  int? progress,
  int? eta,
  int? queue,
}) => {
  'id': id,
  'season': season,
  'episode': episode,
  'episode_title': null,
  'approved': approved,
  'video': video,
  'video_reason': null,
  'previewable': previewable,
  'filename': filename,
  'credit_hints': null,
  'keys': keys,
  'progress': progress,
  'eta_seconds': eta,
  'queue_position': queue,
};

Map<String, Object?> edition(
  String id, {
  String title = 'Fast X',
  String kind = 'movie',
  String status = 'draft',
  List<String> missing = const [
    'details, from TMDB or typed in',
    'a chosen poster',
    'a confirmed VJ credit',
  ],
  String? lookup,
  List<Map<String, Object?>> matches = const [],
  List<Map<String, Object?>>? items,
  String? vj,
  String? detailsFrom,
  bool incomplete = false,
}) => {
  'id': id,
  'kind': kind,
  'display_title': title,
  'submitted_year': null,
  'language': 'lg',
  'status': status,
  'test': false,
  'tmdb_lookup': lookup,
  'source_tmdb_id': detailsFrom == null ? null : 385687,
  'source_title': detailsFrom == null ? null : title,
  'source_year': detailsFrom == null ? null : 2023,
  'source_overview': null,
  'details_from': detailsFrom,
  'poster_path': null,
  'poster_url': null,
  'vj_id': vj == null ? null : 'vj-1',
  'vj_name': vj,
  'created_at': '2026-11-18T10:00:00Z',
  'items': items ?? [item()],
  'missing': missing,
  'matches': matches,
  'incomplete': incomplete,
};

Map<String, Object?> match(int id, String title, int year) => {
  'tmdb_id': id,
  'title': title,
  'original_title': title,
  'year': year,
  'overview': 'An overview.',
  'poster_url': null,
};

/// An admin API with drafts, and the routes the draft screen loads.
FakeApi adminApi({List<Map<String, Object?>>? drafts}) {
  final api = FakeApi()..isAdmin = true;
  final all = drafts ?? [edition('d1')];
  api.admin.addAll({
    'GET /drafts': (_) => json({'editions': all}),
    'GET /vjs': (_) => json([
      {
        'id': 'vj-1',
        'name': 'VJ Junior',
        'slug': 'vj-junior',
        'match_names': ['Junior'],
        'photo_path': null,
        'photo_url': null,
        'bio': null,
        'editions': 0,
      },
    ]),
    'GET /languages': (_) => json([
      {'code': 'lg', 'name': 'Luganda'},
    ]),
    'GET /admins': (_) => json([
      {
        'user_id': 'u1',
        'email': 'owner@example.test',
        'added_by_email': null,
        'added_at': '2026-11-17T10:00:00Z',
      },
    ]),
  });
  for (final d in all) {
    final id = d['id'] as String;
    api.admin.addAll({
      'GET /editions/$id': (_) => json(d),
      'GET /editions/$id/credit': (_) => json({
        'vj_id': d['vj_id'],
        'vj_name': d['vj_name'],
        'suggestions': [
          {'vj_id': 'vj-1', 'name': 'VJ Junior', 'found_in': 'the file name'},
        ],
      }),
    });
  }
  return api;
}

Future<void> openAdmin(WidgetTester tester, FakeApi api) async {
  await pumpApp(tester, api, signedIn: true);
  await goTo(tester, 'Admin');
}

Future<void> openDraft(WidgetTester tester, FakeApi api, String title) async {
  await openAdmin(tester, api);
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
  expect(find.byType(DraftScreen), findsOneWidget);
}

Map<String, Object?> body(FakeApi api, String call) {
  final request = api.requests.lastWhere(
    (r) =>
        '${r.method} ${r.url.path}' == 'PUT /api/v1/admin$call' ||
        '${r.method} ${r.url.path}' == 'POST /api/v1/admin$call',
  );
  return jsonDecode(request.body) as Map<String, Object?>;
}

void main() {
  group('the Admin entry', () {
    testWidgets('shows for an admin', (tester) async {
      final api = adminApi();
      await pumpApp(tester, api, signedIn: true);

      expect(find.text('Admin'), findsOneWidget);
      expect(api.requests.map((r) => r.url.path), contains('/api/v1/admin/me'));
    });

    testWidgets('is hidden from someone signed in who isn\'t an admin', (
      tester,
    ) async {
      final api = FakeApi();
      await pumpApp(tester, api, signedIn: true);

      expect(find.text('Admin'), findsNothing);
      expect(api.adminCalls, isEmpty);
    });

    testWidgets('is hidden signed out, without asking', (tester) async {
      final api = adminApi();
      await pumpApp(tester, api);

      expect(find.text('Admin'), findsNothing);
      expect(
        api.requests.map((r) => r.url.path),
        isNot(contains('/api/v1/admin/me')),
      );
    });

    testWidgets('is hidden where admin screens are off, as on Android', (
      tester,
    ) async {
      final api = adminApi();
      await pumpApp(tester, api, signedIn: true, showAdmin: false);

      expect(find.text('Admin'), findsNothing);
    });

    testWidgets('goes when the admin signs out', (tester) async {
      final api = adminApi();
      final auth = await pumpApp(tester, api, signedIn: true);
      expect(find.text('Admin'), findsOneWidget);

      await auth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Admin'), findsNothing);
    });
  });

  group('drafts', () {
    testWidgets('each says what it is waiting for', (tester) async {
      final api = adminApi(
        drafts: [
          edition('d1', title: 'Needs all'),
          edition(
            'd2',
            title: 'Ready one',
            missing: const [],
            vj: 'VJ Junior',
            detailsFrom: 'tmdb',
          ),
          edition(
            'd3',
            title: 'Kabaka',
            kind: 'series',
            status: 'published',
            missing: const [],
            vj: 'VJ Emmy',
            items: [
              item(id: 'e1', season: 1, episode: 1, approved: true),
              item(id: 'e2', season: 1, episode: 2),
            ],
          ),
          edition(
            'd4',
            title: 'Uploading',
            missing: const ['a ready video'],
            items: [item(video: 'uploading', previewable: false)],
            incomplete: true,
          ),
        ],
      );
      await openAdmin(tester, api);

      expect(
        find.text(
          'Still needs: details, from TMDB or typed in, a chosen poster, '
          'a confirmed VJ credit',
        ),
        findsOneWidget,
      );
      expect(find.text('Ready to publish.'), findsOneWidget);
      expect(find.text('1 episode waiting for approval'), findsOneWidget);
      expect(find.text('Published'), findsOneWidget);
      // Still uploading: listed apart, folded away.
      expect(find.text('Uploading'), findsNothing);
      expect(find.text('1 draft still uploading'), findsOneWidget);
      await tester.tap(find.text('1 draft still uploading'));
      await tester.pumpAndSettle();
      expect(find.text('Uploading'), findsOneWidget);
      expect(
        find.text('Uploading from somewhere else, or stopped part way'),
        findsOneWidget,
      );
    });

    testWidgets('each video shows its stage, percentage and time left', (
      tester,
    ) async {
      final api = adminApi(
        drafts: [
          edition(
            'd1',
            title: 'Kabaka',
            kind: 'series',
            items: [
              item(
                id: 'e1',
                season: 1,
                episode: 1,
                video: 'converting',
                progress: 40,
                eta: 90,
              ),
              item(
                id: 'e2',
                season: 1,
                episode: 2,
                video: 'received',
                queue: 2,
              ),
              item(id: 'e3', season: 1, episode: 3, video: 'checking'),
              item(
                id: 'e4',
                season: 1,
                episode: 4,
                video: 'publishing',
                progress: 80,
              ),
              item(id: 'e5', season: 1, episode: 5, video: 'ready'),
            ],
          ),
          edition(
            'd2',
            title: 'Fast X',
            items: [item(video: 'failed')],
          ),
        ],
      );
      // Checking has a moving bar, so the screen never settles.
      await pumpApp(tester, api, signedIn: true, settle: false);
      await tester.tap(find.text('Admin').last);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('S1 E1 · Converting'), findsOneWidget);
      expect(find.text('40% · 2 min left'), findsOneWidget);
      expect(find.text('S1 E2 · Waiting to convert'), findsOneWidget);
      expect(find.text('Number 2 in line'), findsOneWidget);
      expect(find.text('S1 E3 · Checking the file'), findsOneWidget);
      expect(find.text('Takes a few seconds'), findsOneWidget);
      // Three bars at most, then a count.
      expect(find.text('S1 E4 · Sending to the server'), findsNothing);
      expect(find.text('and 1 more video'), findsOneWidget);
      final bars = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .map((bar) => bar.value)
          .toList();
      // Converting at 40%, waiting at 0, and checking with a moving bar.
      expect(bars, [0.4, 0, null]);
      expect(find.text('The movie: Failed'), findsOneWidget);
    });

    testWidgets('asks again while a video is converting, and stops after', (
      tester,
    ) async {
      final converting = [
        edition('d1', items: [item(video: 'converting', progress: 10)]),
      ];
      final api = adminApi(drafts: converting);
      var asked = 0;
      api.admin['GET /drafts'] = (_) {
        asked++;
        return json({
          'editions': asked < 3
              ? converting
              : [
                  edition('d1', items: [item()]),
                ],
        });
      };
      await openAdmin(tester, api);
      expect(asked, 1);

      await tester.pump(draftsRefreshEvery);
      await tester.pumpAndSettle();
      expect(asked, 2);
      await tester.pump(draftsRefreshEvery);
      await tester.pumpAndSettle();
      expect(asked, 3);
      expect(find.text('The movie · Converting'), findsNothing);

      await tester.pump(draftsRefreshEvery * 3);
      await tester.pumpAndSettle();
      expect(asked, 3);
    });
  });

  group('deleting drafts', () {
    Future<void> deleteFromMenu(WidgetTester tester, String title) async {
      final card = find.ancestor(
        of: find.text(title),
        matching: find.byType(Card),
      );
      await tester.tap(
        find.descendant(
          of: card.first,
          matching: find.byTooltip('More actions'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
    }

    testWidgets('one is deleted for good after confirming', (tester) async {
      final drafts = [edition('d1'), edition('d2', title: 'Kept')];
      final api = adminApi(drafts: drafts);
      api.admin['GET /drafts'] = (_) => json({'editions': drafts});
      api.admin['DELETE /editions/d1'] = (_) {
        drafts.removeAt(0);
        return json({'deleted': 1});
      };
      await openAdmin(tester, api);

      await deleteFromMenu(tester, 'Fast X');
      expect(find.text('Delete “Fast X”?'), findsOneWidget);
      expect(find.textContaining("This can't be undone."), findsOneWidget);
      await tester.tap(find.text('Delete permanently').last);
      await tester.pumpAndSettle();

      expect(api.adminCalls, contains('DELETE /editions/d1'));
      expect(find.text('“Fast X” deleted'), findsOneWidget);
      expect(find.text('Fast X'), findsNothing);
      expect(find.text('Kept'), findsOneWidget);
    });

    testWidgets('cancelling deletes nothing', (tester) async {
      final api = adminApi();
      await openAdmin(tester, api);

      await deleteFromMenu(tester, 'Fast X');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(api.adminCalls.where((c) => c.startsWith('DELETE')), isEmpty);
      expect(find.text('Fast X'), findsOneWidget);
    });

    testWidgets('a published title has no Delete in Drafts', (tester) async {
      final api = adminApi(
        drafts: [
          edition(
            'd1',
            kind: 'series',
            status: 'published',
            missing: const [],
            vj: 'VJ Emmy',
            items: [item(season: 1, episode: 2)],
          ),
        ],
      );
      await openAdmin(tester, api);

      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();

      expect(find.text('Open draft'), findsOneWidget);
      expect(find.text('Delete permanently'), findsNothing);
      // Nor Delete all: no drafts.
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      expect(find.text('Delete all drafts'), findsNothing);
    });

    testWidgets('every draft goes only once DELETE is typed', (tester) async {
      final api = adminApi(
        drafts: [
          edition('d1'),
          edition('d2', title: 'Two'),
          edition('d3', title: 'Hidden one', status: 'hidden'),
        ],
      );
      api.admin['POST /drafts/delete-all'] = (_) => json({'deleted': 2});
      await openAdmin(tester, api);

      await tester.tap(find.text('Delete all drafts'));
      await tester.pumpAndSettle();
      expect(find.text('Delete all 2 drafts?'), findsOneWidget);
      expect(
        find.textContaining('Published and hidden titles stay.'),
        findsOneWidget,
      );
      VeloraButton action() => tester.widget<VeloraButton>(
        find.widgetWithText(VeloraButton, 'Delete all drafts').last,
      );
      expect(action().onPressed, isNull);

      await tester.enterText(find.byType(TextField).last, 'delete');
      await tester.pump();
      expect(action().onPressed, isNull);
      await tester.enterText(find.byType(TextField).last, 'DELETE');
      await tester.pump();
      expect(action().onPressed, isNotNull);

      await tester.tap(
        find.widgetWithText(VeloraButton, 'Delete all drafts').last,
      );
      await tester.pumpAndSettle();

      expect(body(api, '/drafts/delete-all'), {'confirm': 'DELETE'});
      expect(find.text('2 drafts deleted'), findsOneWidget);
    });

    testWidgets('the draft page can delete its draft too', (tester) async {
      final api = adminApi();
      api.admin['DELETE /editions/d1'] = (_) => json({'deleted': 1});
      await openDraft(tester, api, 'Fast X');

      await tester.ensureVisible(find.text('Delete permanently'));
      await tester.tap(find.text('Delete permanently'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete permanently').last);
      await tester.pumpAndSettle();

      expect(api.adminCalls, contains('DELETE /editions/d1'));
      expect(find.byType(DraftScreen), findsNothing);
    });
  });

  group('a new draft', () {
    FakeApi newDraftApi() {
      final api = adminApi(drafts: [edition('d9', title: 'Fast X')]);
      api.admin.addAll({
        'GET /series': (_) => json([
          {
            'id': 's1',
            'display_title': 'Kabaka',
            'language': 'lg',
            'status': 'published',
            'vj_id': 'vj-1',
            'vj_name': 'VJ Junior',
            'episodes': [
              [1, 1],
            ],
          },
        ]),
        'GET /categories': (_) => json([]),
        'POST /drafts': (request) {
          final body = jsonDecode(request.body) as Map<String, Object?>;
          return json({
            'edition_id': body['series_edition_id'] ?? 'd9',
            'item_id': 'i9',
            'key_id': 'k1',
            'upload_key': 'vk_THE-KEY-ONCE',
            'expires_at': '2026-11-25T10:00:00Z',
          }, 201);
        },
        'PUT /editions/d9/credit': (_) => json(edition('d9', vj: 'VJ Junior')),
        'POST /editions/d9/tmdb/search': (_) =>
            json({'outcome': 'clear', 'edition': edition('d9')}),
        'PUT /editions/d9/source': (_) => json(edition('d9')),
      });
      return api;
    }

    Future<void> openNewDraft(WidgetTester tester, FakeApi api) async {
      await openAdmin(tester, api);
      await tester.tap(find.text('New draft'));
      await tester.pumpAndSettle();
      expect(find.byType(NewDraftScreen), findsOneWidget);
    }

    Future<void> chooseVj(WidgetTester tester) async {
      await tester.tap(
        find.widgetWithText(DropdownButtonFormField<String>, 'VJ credit'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('VJ Junior').last);
      await tester.pumpAndSettle();
    }

    Future<void> create(WidgetTester tester) async {
      await tester.ensureVisible(find.text('Create draft'));
      await tester.tap(find.text('Create draft'));
      await tester.pumpAndSettle();
    }

    testWidgets('needs a title and a VJ', (tester) async {
      final api = newDraftApi();
      await openNewDraft(tester, api);

      await create(tester);

      expect(find.text('Required.'), findsNWidgets(2));
      expect(api.adminCalls, isNot(contains('POST /drafts')));
    });

    testWidgets('a movie is made with its VJ and TMDB details, then its key '
        'is shown once and the draft opens', (tester) async {
      final api = newDraftApi();
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      await openNewDraft(tester, api);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Fast X',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Year (optional)'),
        '2023',
      );
      await chooseVj(tester);
      await create(tester);

      expect(body(api, '/drafts'), {
        'kind': 'movie',
        'title': 'Fast X',
        'year': 2023,
        'language': 'lg',
      });
      expect(body(api, '/editions/d9/credit'), {'vj_id': 'vj-1'});
      expect(body(api, '/editions/d9/tmdb/search'), {
        'title': 'Fast X',
        'year': 2023,
      });
      expect(find.text('vk_THE-KEY-ONCE'), findsOneWidget);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(copied, 'vk_THE-KEY-ONCE');

      await tester.tap(find.text('Done'));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // On both pages while one slides over the other.
      expect(find.text('Draft created'), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.byType(DraftScreen), findsOneWidget);
    });

    testWidgets('typed details are saved, and a part that fails is named '
        'while the draft still opens', (tester) async {
      final api = newDraftApi();
      api.admin['PUT /editions/d9/credit'] = (_) =>
          json({'detail': 'This VJ already has an edition of that title'}, 400);
      await openNewDraft(tester, api);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Omukwano',
      );
      await chooseVj(tester);
      await tester.tap(find.text('Type the details in'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description (optional)'),
        'A love story.',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Genres (optional)'),
        'Drama, Romance',
      );
      await create(tester);

      expect(body(api, '/editions/d9/source'), {
        'manual': {
          'title': 'Omukwano',
          'overview': 'A love story.',
          'year': null,
          'genres': ['Drama', 'Romance'],
          'runtime_minutes': null,
        },
      });
      expect(api.adminCalls, isNot(contains('POST /editions/d9/tmdb/search')));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(DraftScreen), findsOneWidget);
      expect(
        find.textContaining("Draft created, but some parts weren't saved"),
        findsOneWidget,
      );
      expect(
        find.textContaining('This VJ already has an edition of that title'),
        findsOneWidget,
      );
    });

    testWidgets('an episode goes to an existing series, never twice', (
      tester,
    ) async {
      final api = newDraftApi();
      api.admin['GET /editions/s1'] = (_) =>
          json(edition('s1', kind: 'series'));
      api.admin['GET /editions/s1/credit'] = (_) =>
          json({'vj_id': null, 'vj_name': null, 'suggestions': []});
      await openNewDraft(tester, api);

      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A new series'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kabaka · VJ Junior').last);
      await tester.pumpAndSettle();
      expect(find.text('Added to Kabaka, by VJ Junior.'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Title'), findsNothing);

      await create(tester);
      expect(
        find.text('This series already has season 1, episode 1.'),
        findsWidgets,
      );
      expect(api.adminCalls, isNot(contains('POST /drafts')));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Episode'),
        '2',
      );
      await create(tester);

      expect(body(api, '/drafts'), {
        'kind': 'series',
        'series_edition_id': 's1',
        'season': 1,
        'episode': 2,
      });
      // The series has its VJ already.
      expect(api.adminCalls.where((c) => c.endsWith('/credit')), isEmpty);
    });

    testWidgets('fits a narrow phone with large text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final api = newDraftApi();
      await pumpApp(tester, api, signedIn: true, size: const Size(320, 2400));
      await goTo(tester, 'Admin');
      await tester.tap(find.text('New draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('a draft', () {
    testWidgets('lists what publishing still needs', (tester) async {
      await openDraft(tester, adminApi(), 'Fast X');

      expect(
        find.text("This can't be published yet. It still needs:"),
        findsOneWidget,
      );
      expect(find.text('• a chosen poster'), findsOneWidget);
      expect(find.text('Needed'), findsNWidgets(3));
    });

    testWidgets('TMDB candidates can be chosen', (tester) async {
      final api = adminApi(
        drafts: [
          edition(
            'd1',
            lookup: 'choose',
            matches: [match(385687, 'Fast X', 2023), match(9, 'Fast', 2009)],
          ),
        ],
      );
      api.admin['PUT /editions/d1/source'] = (_) =>
          json(edition('d1', lookup: 'chosen', detailsFrom: 'tmdb'));
      await openDraft(tester, api, 'Fast X');

      expect(
        find.text('TMDB found several possible titles. Choose the right one.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Use this').first);
      await tester.pumpAndSettle();

      expect(body(api, '/editions/d1/source'), {'tmdb_id': 385687});
      expect(find.text('Details chosen from TMDB.'), findsOneWidget);
    });

    for (final (lookup, words) in [
      (null, 'TMDB is searched once the video is ready.'),
      ('none', 'TMDB found nothing.'),
      ('failed', "TMDB couldn't be reached."),
      ('clear', 'TMDB found a clear match'),
    ]) {
      testWidgets('a lookup that is $lookup says so', (tester) async {
        await openDraft(
          tester,
          adminApi(drafts: [edition('d1', lookup: lookup)]),
          'Fast X',
        );
        expect(find.textContaining(words), findsOneWidget);
      });
    }

    testWidgets('a suggested credit needs confirming', (tester) async {
      final api = adminApi();
      api.admin['PUT /editions/d1/credit'] = (_) =>
          json(edition('d1', vj: 'VJ Junior'));
      await openDraft(tester, api, 'Fast X');

      expect(find.text('VJ Junior, found in the file name'), findsOneWidget);
      await tester.ensureVisible(find.text('Credit this VJ'));
      await tester.tap(find.text('Credit this VJ'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm the VJ credit'), findsOneWidget);
      expect(api.adminCalls, isNot(contains('PUT /editions/d1/credit')));

      await tester.tap(find.text('Confirm credit'));
      await tester.pumpAndSettle();
      expect(body(api, '/editions/d1/credit'), {'vj_id': 'vj-1'});
    });

    testWidgets('a refused publish lists what is missing', (tester) async {
      final api = adminApi();
      api.admin['POST /editions/d1/publish'] = (_) => json({
        'detail': {
          'message': 'Not ready to publish: a chosen poster',
          'missing': ['a chosen poster'],
        },
      }, 409);
      await openDraft(tester, api, 'Fast X');

      await tester.ensureVisible(find.text('Publish'));
      await tester.tap(find.text('Publish'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Still needs: a chosen poster'), findsOneWidget);
    });

    testWidgets('Preview plays through the admin route', (tester) async {
      final api = adminApi();
      api.admin['POST /items/i1/preview'] = (_) => json({
        'playlist_url': '$gateway/v1/preview.sig/master.m3u8',
        'expires_at': '2030-01-01T00:00:00Z',
      });
      await openDraft(tester, api, 'Fast X');

      await tester.tap(find.text('Preview'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byType(PlayerScreen), findsOneWidget);
      expect(api.adminCalls, contains('POST /items/i1/preview'));
    });

    testWidgets('a published series offers approval of a new episode', (
      tester,
    ) async {
      final api = adminApi(
        drafts: [
          edition(
            'd3',
            title: 'Kabaka',
            kind: 'series',
            status: 'published',
            missing: const [],
            vj: 'VJ Emmy',
            items: [
              item(id: 'e1', season: 1, episode: 1, approved: true),
              item(id: 'e2', season: 1, episode: 2),
            ],
          ),
        ],
      );
      api.admin['POST /items/e2/approve'] = (_) =>
          json({'item_id': 'e2', 'approved': true});
      await openDraft(tester, api, 'Kabaka');

      expect(find.text('Waiting for approval'), findsOneWidget);
      await tester.tap(find.text('Approve episode'));
      await tester.pumpAndSettle();
      expect(api.adminCalls, contains('POST /items/e2/approve'));
      expect(find.text('Hide'), findsOneWidget);
    });
  });

  group('settings', () {
    testWidgets('the last admin can\'t be removed; another is added by email', (
      tester,
    ) async {
      final api = adminApi();
      api.admin['POST /admins'] = (_) => json({'user_id': 'u2'}, 201);
      await openAdmin(tester, api);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('owner@example.test'), findsOneWidget);
      expect(find.text('Last admin'), findsOneWidget);
      expect(find.text('Remove'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email of the new admin'),
        'second@example.test',
      );
      await tester.tap(find.text('Add admin'));
      await tester.pumpAndSettle();
      expect(body(api, '/admins'), {'email': 'second@example.test'});
    });

    testWidgets("a refusal shows the API's reason", (tester) async {
      final api = adminApi();
      api.admin['POST /admins'] = (_) =>
          json({'detail': 'They must sign in to VeloraUG first.'}, 400);
      await openAdmin(tester, api);
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email of the new admin'),
        'nobody@example.test',
      );
      await tester.tap(find.text('Add admin'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'VeloraUG refused that. They must sign in to VeloraUG first.',
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('VJs lists each VJ with their other spellings', (tester) async {
    await openAdmin(tester, adminApi());
    await tester.tap(find.text('VJs'));
    await tester.pumpAndSettle();

    expect(find.text('VJ Junior'), findsOneWidget);
    expect(find.text('Nothing published · Also: Junior'), findsOneWidget);
  });
}
