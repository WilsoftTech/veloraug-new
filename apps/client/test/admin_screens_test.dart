import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/admin/draft_screen.dart';
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
      expect(find.text('Still needs: a ready video'), findsOneWidget);
      expect(find.text('Published'), findsOneWidget);
    });

    testWidgets('a new draft shows its key once, then opens', (tester) async {
      final api = adminApi();
      api.admin['POST /drafts'] = (_) => json({
        'edition_id': 'd1',
        'item_id': 'i1',
        'key_id': 'k1',
        'upload_key': 'vk_THE-KEY-ONCE',
        'expires_at': '2026-11-25T10:00:00Z',
      }, 201);
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
      await openAdmin(tester, api);

      await tester.tap(find.text('New draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Title'),
        'Kabaka',
      );
      await tester.tap(find.text('Start draft'));
      await tester.pumpAndSettle();

      expect(body(api, '/drafts'), {
        'kind': 'series',
        'title': 'Kabaka',
        'language': 'lg',
        'season': 1,
        'episode': 1,
      });
      expect(find.text('vk_THE-KEY-ONCE'), findsOneWidget);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(copied, 'vk_THE-KEY-ONCE');

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(DraftScreen), findsOneWidget);
      expect(find.text('vk_THE-KEY-ONCE'), findsNothing);
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
