import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/admin/draft_screen.dart';
import 'package:veloraug/admin/drafts_view.dart' show draftsRefreshEvery;
import 'package:veloraug/admin/library_view.dart' show librarySearchDelay;
import 'package:veloraug/admin/new_draft_screen.dart';
import 'package:veloraug/admin/uploads/file_names.dart' show maxVideoBytes;
import 'package:veloraug/admin/uploads/tus.dart';
import 'package:veloraug/admin/uploads/upload_queue.dart';
import 'package:veloraug/widgets/velora_button.dart';
import 'package:veloraug/screens/player_screen.dart';

import 'support.dart';
import 'uploads/upload_fakes.dart';

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
  bool hidden = false,
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
  'hidden': hidden,
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
  String? publishedAt,
  String? overview,
  String? trailer,
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
  'published_at': publishedAt,
  'overview': overview,
  'trailer_key': trailer,
  'source_trailer_key': 'tmdbTrailer1',
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

    testWidgets('asks again while a video uploads elsewhere, and moves it up '
        'once uploaded', (tester) async {
      final api = adminApi();
      var asked = 0;
      api.admin['GET /drafts'] = (_) {
        asked++;
        return json({
          'editions': [
            asked < 2
                ? edition(
                    'd1',
                    items: [item(video: 'uploading', previewable: false)],
                    incomplete: true,
                  )
                : edition('d1', items: [item(video: 'received', queue: 1)]),
          ],
        });
      };
      await openAdmin(tester, api);
      expect(find.text('1 draft still uploading'), findsOneWidget);

      await tester.pump(draftsRefreshEvery);
      await tester.pump();
      await tester.pump();

      expect(asked, 2);
      expect(find.text('1 draft still uploading'), findsNothing);
      expect(find.text('The movie · Waiting to convert'), findsOneWidget);
    });

    testWidgets('an older answer never replaces a newer one', (tester) async {
      final api = adminApi();
      final slow = Completer<void>();
      var asked = 0;
      api.admin['GET /drafts'] = (_) async {
        asked++;
        if (asked == 2) {
          // The refresh pressed first answers last, still listing it.
          await slow.future;
          return json({
            'editions': [edition('d1')],
          });
        }
        return json({
          'editions': asked == 1 ? [edition('d1')] : <Object?>[],
        });
      };
      api.admin['DELETE /editions/d1'] = (_) => json({
        'deleted': 1,
        'ids': ['d1'],
      });
      await openAdmin(tester, api);

      // The refresh's spinner never settles while its answer waits.
      Future<void> frames() async {
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      await tester.tap(find.text('Refresh'));
      await tester.pump();
      // Deleted while that refresh waits: the delete asks again.
      await tester.tap(find.byTooltip('More actions'));
      await frames();
      await tester.tap(find.text('Delete permanently'));
      await frames();
      await tester.tap(find.text('Delete permanently').last);
      await frames();
      expect(asked, 3);
      expect(find.text('Fast X'), findsNothing);

      slow.complete();
      await tester.pumpAndSettle();
      expect(find.text('Fast X'), findsNothing);
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
      api.admin['POST /drafts/delete-all'] = (_) => json({
        'deleted': 2,
        'ids': ['d1', 'd2'],
      });
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

    testWidgets('a series chosen, then Movie, makes a movie', (tester) async {
      final api = newDraftApi();
      await openNewDraft(tester, api);

      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A new series'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kabaka · VJ Junior').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Movie'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Title'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Fast X',
      );
      await chooseVj(tester);
      await create(tester);

      expect(body(api, '/drafts'), {
        'kind': 'movie',
        'title': 'Fast X',
        'language': 'lg',
      });
    });

    testWidgets('a video over the limit is refused when chosen', (
      tester,
    ) async {
      final api = newDraftApi();
      await pumpApp(
        tester,
        api,
        signedIn: true,
        uploads: (auth) {
          final queue = UploadQueue(
            api: api.adminApi(auth),
            tus: TusClient(FakeTusServer()),
            endpoint: Uri.parse(uploadEndpoint),
            store: MemoryUploadStore(),
          );
          addTearDown(queue.dispose);
          return queue;
        },
        pickVideos: () async => [video('Huge.mp4', size: maxVideoBytes + 1)],
      );
      await goTo(tester, 'Admin');
      await tester.tap(find.text('New draft'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Choose the file'));
      await tester.tap(find.text('Choose the file'));
      await tester.pumpAndSettle();

      expect(
        find.text("The file is larger than 50 GB, VeloraUG's limit."),
        findsOneWidget,
      );
      expect(find.textContaining('Huge.mp4'), findsNothing);
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

  group('the Library', () {
    Map<String, Object?> row(
      String id,
      String title, {
      String state = 'published',
      String kind = 'movie',
      String? vj = 'VJ Junior',
      int viewers = 0,
      int episodes = 1,
      int hidden = 0,
      int waiting = 0,
      List<String> categories = const [],
    }) => {
      'id': id,
      'kind': kind,
      'display_title': title,
      'poster_url': null,
      'vj_id': vj == null ? null : 'vj-1',
      'vj_name': vj,
      'state': state,
      'published_at': '2026-11-03T10:00:00Z',
      'updated_at': '2026-11-20T10:00:00Z',
      'episodes': episodes,
      'hidden_episodes': hidden,
      'waiting': waiting,
      'viewers': viewers,
      'categories': categories,
      'year': 2023,
    };

    /// An admin API whose Library answers with [rows], [total] in all, and
    /// records each query it was asked.
    (FakeApi, List<Map<String, String>>) libraryApi(
      List<Map<String, Object?>> rows, {
      int? total,
    }) {
      final api = adminApi(
        drafts: [
          edition(
            'l1',
            title: 'Fast X',
            status: 'published',
            missing: const [],
            vj: 'VJ Junior',
            detailsFrom: 'tmdb',
            publishedAt: '2026-11-03T10:00:00Z',
          ),
        ],
      );
      final asked = <Map<String, String>>[];
      api.admin.addAll({
        'GET /library': (request) {
          asked.add(request.url.queryParameters);
          final later = request.url.queryParameters.containsKey('offset');
          return json({
            // A later page: titles not on the first.
            'titles': later
                ? [
                    for (final r in rows) {...r, 'id': '${r['id']}-more'},
                  ]
                : rows,
            'total': total ?? rows.length,
            'viewer_days': 30,
          });
        },
        'GET /categories': (_) => json([
          {'id': 'c1', 'name': 'Indian', 'slug': 'indian', 'editions': 1},
        ]),
      });
      return (api, asked);
    }

    Future<void> openLibrary(WidgetTester tester, FakeApi api) async {
      await openAdmin(tester, api);
      await tester.tap(find.widgetWithText(Tab, 'Library'));
      await tester.pumpAndSettle();
    }

    Future<void> fromMenu(
      WidgetTester tester,
      String title,
      String action,
    ) async {
      final card = find.ancestor(
        of: find.textContaining(title),
        matching: find.byType(Card),
      );
      await tester.tap(
        find.descendant(
          of: card.first,
          matching: find.byTooltip('More actions'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(action).last);
      await tester.pumpAndSettle();
    }

    testWidgets('lists each title with its state, VJ, viewers and episodes', (
      tester,
    ) async {
      final (api, _) = libraryApi([
        row('l1', 'Fast X', viewers: 120, categories: ['Indian']),
        row(
          'l2',
          'Kabaka',
          kind: 'series',
          state: 'hidden',
          vj: 'VJ Emmy',
          episodes: 8,
          hidden: 1,
          waiting: 2,
        ),
        row('l3', 'Commando', state: 'withdrawn', viewers: 1),
      ]);
      await openLibrary(tester, api);

      expect(find.text('3 titles'), findsOneWidget);
      expect(find.text('Fast X (2023)'), findsOneWidget);
      expect(find.text('Movie · VJ Junior · Indian'), findsOneWidget);
      expect(
        find.text('Published Nov 3, 2026 · 120 viewers in 30 days'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Published Nov 3, 2026 · 0 viewers in 30 days · 8 episodes · '
          '1 hidden · 2 episodes waiting for approval',
        ),
        findsOneWidget,
      );
      expect(find.text('Withdrawn'), findsWidgets);
    });

    testWidgets('searches, filters and sorts on the server', (tester) async {
      final (api, asked) = libraryApi([row('l1', 'Fast X')]);
      await openLibrary(tester, api);
      expect(asked.single, {'sort': 'newest'});

      await tester.enterText(
        find.widgetWithText(TextField, 'Search titles and VJs'),
        'fast',
      );
      await tester.pump(librarySearchDelay);
      await tester.pumpAndSettle();
      expect(asked.last, {'q': 'fast', 'sort': 'newest'});

      await tester.tap(find.widgetWithText(ChoiceChip, 'Hidden'));
      await tester.pumpAndSettle();
      expect(asked.last['state'], 'hidden');

      await tester.tap(find.text('Newest'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Most viewers').last);
      await tester.pumpAndSettle();
      expect(asked.last, {'q': 'fast', 'state': 'hidden', 'sort': 'viewers'});
    });

    testWidgets('shows more, 50 at a time', (tester) async {
      final (api, asked) = libraryApi([row('l1', 'Fast X')], total: 51);
      await openLibrary(tester, api);

      await tester.ensureVisible(find.text('Show more (50 left)'));
      await tester.tap(find.text('Show more (50 left)'));
      await tester.pumpAndSettle();

      expect(asked.last['offset'], '1');
    });

    testWidgets('many titles are hidden at once, with what was skipped', (
      tester,
    ) async {
      final (api, _) = libraryApi([
        row('l1', 'Fast X'),
        row('l2', 'Commando', state: 'withdrawn'),
      ]);
      api.admin['POST /library/bulk'] = (_) => json({
        'changed': 1,
        'results': [
          {'id': 'l1', 'ok': true, 'reason': null},
          {
            'id': 'l2',
            'ok': false,
            'reason': 'Only a published title can be hidden',
          },
        ],
      });
      await openLibrary(tester, api);

      await tester.tap(find.bySemanticsLabel('Select every title shown'));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.widgetWithText(VeloraButton, 'Hide').first);
      await tester.pumpAndSettle();
      expect(find.text('Hide 2 titles?'), findsOneWidget);
      await tester.tap(find.widgetWithText(VeloraButton, 'Hide').last);
      await tester.pumpAndSettle();

      expect(body(api, '/library/bulk'), {
        'ids': ['l1', 'l2'],
        'action': 'hide',
      });
      expect(
        find.text(
          '1 title changed.\n'
          'Skipped:\nCommando: Only a published title can be hidden',
        ),
        findsOneWidget,
      );
      expect(find.text('2 selected'), findsNothing);
    });

    testWidgets('many titles are credited to another VJ', (tester) async {
      final (api, _) = libraryApi([row('l1', 'Fast X')]);
      api.admin['POST /library/bulk'] = (_) => json({
        'changed': 1,
        'results': [
          {'id': 'l1', 'ok': true},
        ],
      });
      await openLibrary(tester, api);

      await tester.tap(find.bySemanticsLabel('Select Fast X'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change VJ'));
      await tester.pumpAndSettle();
      expect(find.text('Credit 1 title to…'), findsOneWidget);
      await tester.tap(find.text('VJ Junior').last);
      await tester.pumpAndSettle();

      expect(body(api, '/library/bulk'), {
        'ids': ['l1'],
        'action': 'credit',
        'vj_id': 'vj-1',
      });
    });

    testWidgets('withdrawing says what happens to viewers and downloads', (
      tester,
    ) async {
      final (api, _) = libraryApi([row('l1', 'Fast X')]);
      api.admin['POST /editions/l1/withdraw'] = (_) => json(
        edition('l1', publishedAt: '2026-11-03T10:00:00Z', missing: const []),
      );
      await openLibrary(tester, api);

      await fromMenu(tester, 'Fast X', 'Withdraw');
      expect(find.text('Withdraw “Fast X”?'), findsOneWidget);
      expect(
        find.textContaining("already downloaded are theirs, and can't be"),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(VeloraButton, 'Withdraw').last);
      await tester.pumpAndSettle();

      expect(api.adminCalls, contains('POST /editions/l1/withdraw'));
      expect(find.text('“Fast X” withdrawn to Drafts'), findsOneWidget);
    });

    testWidgets('a published title is deleted only once DELETE is typed', (
      tester,
    ) async {
      final (api, _) = libraryApi([row('l1', 'Fast X')]);
      Uri? asked;
      api.admin['DELETE /editions/l1'] = (request) {
        asked = request.url;
        return json({
          'deleted': 1,
          'ids': ['l1'],
        });
      };
      await openLibrary(tester, api);

      await fromMenu(tester, 'Fast X', 'Delete permanently');
      expect(
        find.textContaining('To take it down for now instead'),
        findsOneWidget,
      );
      VeloraButton action() => tester.widget<VeloraButton>(
        find.widgetWithText(VeloraButton, 'Delete permanently').last,
      );
      expect(action().onPressed, isNull);
      await tester.enterText(find.byType(TextField).last, 'DELETE');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(VeloraButton, 'Delete permanently').last,
      );
      await tester.pumpAndSettle();

      expect(asked?.queryParameters, {'published': 'true'});
    });

    testWidgets('a hidden title is shown again from the menu', (tester) async {
      final (api, _) = libraryApi([row('l1', 'Fast X', state: 'hidden')]);
      api.admin['POST /editions/l1/publish'] = (_) =>
          json(edition('l1', status: 'published', missing: const []));
      await openLibrary(tester, api);

      await fromMenu(tester, 'Fast X', 'Show again');

      expect(api.adminCalls, contains('POST /editions/l1/publish'));
      expect(find.text('“Fast X” is showing again'), findsOneWidget);
    });

    testWidgets('fits a narrow phone with large text', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final (api, _) = libraryApi([
        row('l1', 'A very long title of a translated film', kind: 'series'),
      ]);
      await pumpApp(tester, api, signedIn: true, size: const Size(320, 2400));
      await goTo(tester, 'Admin');
      await tester.ensureVisible(find.widgetWithText(Tab, 'Library'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(Tab, 'Library'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group("a published title's page", () {
    FakeApi titleApi({
      String status = 'published',
      List<Map<String, Object?>>? items,
    }) {
      final api = adminApi(
        drafts: [
          edition(
            'd1',
            kind: items == null ? 'movie' : 'series',
            status: status,
            missing: const [],
            vj: 'VJ Junior',
            detailsFrom: 'tmdb',
            publishedAt: '2026-11-03T10:00:00Z',
            items: items,
          ),
        ],
      );
      api.admin['PATCH /editions/d1'] = (_) => json(
        edition(
          'd1',
          status: status,
          missing: const [],
          detailsFrom: 'tmdb',
          overview: 'Own words.',
        ),
      );
      return api;
    }

    testWidgets('saves only the details that changed', (tester) async {
      final api = titleApi();
      await openDraft(tester, api, 'Fast X');

      expect(find.text('What viewers see'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Description'),
        'Own words.',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Trailer, a YouTube address'),
        'https://youtu.be/abc123XYZ',
      );
      await tester.ensureVisible(find.text('Save details'));
      await tester.tap(find.text('Save details'));
      await tester.pumpAndSettle();

      final request = api.requests.lastWhere((r) => r.method == 'PATCH');
      expect(jsonDecode(request.body), {
        'overview': 'Own words.',
        'trailer': 'https://youtu.be/abc123XYZ',
      });
      expect(find.text('Details saved'), findsOneWidget);
    });

    testWidgets('offers Hide, Withdraw and Delete', (tester) async {
      await openDraft(tester, titleApi(), 'Fast X');

      for (final label in ['Hide', 'Withdraw', 'Delete permanently']) {
        expect(find.widgetWithText(VeloraButton, label), findsOneWidget);
      }
      expect(find.widgetWithText(VeloraButton, 'Show again'), findsNothing);
    });

    testWidgets('a hidden title says so, and can be shown again', (
      tester,
    ) async {
      await openDraft(tester, titleApi(status: 'hidden'), 'Fast X');

      expect(
        find.text(
          "Hidden: viewers can't see it. Show again puts it back as it was.",
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(VeloraButton, 'Show again'), findsOneWidget);
      expect(find.widgetWithText(VeloraButton, 'Withdraw'), findsOneWidget);
    });

    testWidgets('each episode is edited, hidden, withdrawn or deleted', (
      tester,
    ) async {
      final api = titleApi(
        items: [
          item(id: 'e1', season: 1, episode: 1, approved: true),
          item(id: 'e2', season: 1, episode: 2, approved: true, hidden: true),
        ],
      );
      for (final call in [
        'PATCH /items/e1',
        'POST /items/e1/hide',
        'POST /items/e2/show',
        'POST /items/e1/withdraw',
        'DELETE /items/e2',
      ]) {
        api.admin[call] = (_) => json({'item_id': 'x'});
      }
      await openDraft(tester, api, 'Fast X');
      expect(find.text('Hidden'), findsWidgets);

      Future<void> episodeAction(String episode, String action) async {
        await tester.ensureVisible(find.byTooltip('Actions for $episode'));
        await tester.tap(find.byTooltip('Actions for $episode'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(action).last);
        await tester.pumpAndSettle();
      }

      await episodeAction('S1 E1', 'Edit episode');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Episode').last,
        '2',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Episode title (optional)'),
        'Pilot',
      );
      await tester.tap(find.widgetWithText(VeloraButton, 'Save').last);
      await tester.pumpAndSettle();
      final edit = api.requests.lastWhere((r) => r.method == 'PATCH');
      expect(jsonDecode(edit.body), {
        'season': 1,
        'episode': 2,
        'episode_title': 'Pilot',
      });

      await episodeAction('S1 E1', 'Hide episode');
      await episodeAction('S1 E2', 'Show episode');
      await episodeAction('S1 E1', 'Withdraw episode');
      expect(find.text('Withdraw S1 E1?'), findsOneWidget);
      await tester.tap(find.widgetWithText(VeloraButton, 'Withdraw').last);
      await tester.pumpAndSettle();
      await episodeAction('S1 E2', 'Delete permanently');
      expect(find.text('Delete S1 E2?'), findsOneWidget);
      await tester.tap(find.text('Delete permanently').last);
      await tester.pumpAndSettle();

      expect(
        api.adminCalls,
        containsAllInOrder([
          'PATCH /items/e1',
          'POST /items/e1/hide',
          'POST /items/e2/show',
          'POST /items/e1/withdraw',
          'DELETE /items/e2',
        ]),
      );
    });
  });
}
