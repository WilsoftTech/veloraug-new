import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/admin/uploads/tus.dart';
import 'package:veloraug/admin/uploads/upload_queue.dart';

import '../support.dart';
import 'upload_fakes.dart';

void main() {
  late FakeTusServer server;
  late Admin admin;

  setUp(() {
    server = FakeTusServer();
    admin = Admin(server);
    admin.api.admin.addAll({
      'GET /drafts': (_) => json({'editions': []}),
      'GET /vjs': (_) => json([
        {'id': 'v1', 'name': 'VJ Junior', 'slug': 'vj-junior'},
      ]),
      'GET /series': (_) => json([
        {
          'id': 's1',
          'display_title': 'Kabaka',
          'language': 'lg',
          'status': 'published',
          'vj_id': 'v1',
          'vj_name': 'VJ Junior',
          'episodes': [
            [1, 1],
          ],
        },
      ]),
      'GET /languages': (_) => json([
        {'code': 'lg', 'name': 'Luganda'},
      ]),
    });
  });

  Future<void> openUploads(
    WidgetTester tester,
    List<PickedVideo> files, {
    Size size = const Size(1200, 1600),
  }) async {
    await pumpApp(
      tester,
      admin.api,
      signedIn: true,
      size: size,
      uploads: (auth) {
        final queue = UploadQueue(
          api: admin.api.adminApi(auth),
          tus: TusClient(server),
          endpoint: Uri.parse(uploadEndpoint),
          store: MemoryUploadStore(),
          chunkBytes: 10,
        );
        addTearDown(queue.dispose);
        return queue;
      },
      pickVideos: () async => files,
    );
    await goTo(tester, 'Admin');
    await tester.tap(find.widgetWithText(Tab, 'Uploads'));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester) async {
    await tester.tap(find.text('Choose files'));
    await tester.pumpAndSettle();
  }

  Map<String, Object?> draftBody(int n) => jsonDecode(
    admin.api.requests
        .where((r) => r.method == 'POST' && r.url.path.endsWith('/drafts'))
        .elementAt(n)
        .body,
  ) as Map<String, Object?>;

  testWidgets('dropped or chosen files are read, checked, then uploaded', (
    tester,
  ) async {
    await openUploads(tester, [
      video('VJ Junior - Commando (1985).mp4'),
      video('VJ Junior - Kabaka S01E02.mp4'),
      video('notes.txt'),
    ]);
    expect(find.text('Drag video files here'), findsOneWidget);
    expect(find.text('How to name files'), findsOneWidget);

    await choose(tester);
    expect(
      find.text("1 file isn't a video, and was left out."),
      findsOneWidget,
    );
    expect(find.text('Check 2 files before uploading'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Commando'), findsOneWidget);
    expect(find.widgetWithText(TextField, '1985'), findsOneWidget);
    expect(
      find.text('This VJ is credited when the draft is made.'),
      findsOneWidget,
    );
    expect(find.text('Added to Kabaka, by VJ Junior.'), findsOneWidget);

    await tester.tap(find.text('Start 2 uploads'));
    await tester.pumpAndSettle();

    expect(find.text('Uploaded'), findsNWidgets(2));
    expect(draftBody(0), {'kind': 'movie', 'title': 'Commando', 'year': 1985});
    expect(draftBody(1), {
      'kind': 'series',
      'series_edition_id': 's1',
      'season': 1,
      'episode': 2,
    });
    expect(admin.credits, ['e1:v1']);
    expect(server.finished('up1') && server.finished('up2'), isTrue);

    await tester.tap(find.text('Clear finished'));
    await tester.pumpAndSettle();
    expect(find.text('Uploaded'), findsNothing);
  });

  testWidgets('an episode the series already has is stopped before uploading', (
    tester,
  ) async {
    await openUploads(tester, [video('VJ Junior - Kabaka S01E01.mp4')]);
    await choose(tester);

    await tester.tap(find.text('Start the upload'));
    await tester.pumpAndSettle();

    expect(
      find.text('This series already has season 1, episode 1.'),
      findsOneWidget,
    );
    expect(admin.drafts, isEmpty);
  });

  testWidgets('an unknown VJ is named, and left for the draft page', (
    tester,
  ) async {
    await openUploads(tester, [video('VJ Emmy - Rambo (2008).mp4')]);
    await choose(tester);

    expect(
      find.textContaining("The file names VJ Emmy, who isn't a VJ here yet."),
      findsOneWidget,
    );
    await tester.tap(find.text('Start the upload'));
    await tester.pumpAndSettle();
    expect(admin.credits, isEmpty);
    expect(find.text('Uploaded'), findsOneWidget);
  });

  testWidgets('an upload can be paused, resumed and removed', (tester) async {
    server.hold = Completer();
    await openUploads(tester, [video('VJ Junior - Commando (1985).mp4')]);
    await choose(tester);
    await tester.tap(find.text('Start the upload'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('Uploading'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(find.text('Paused at 0%. Nothing is lost.'), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(find.text('Uploading'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Remove this upload?'), findsOneWidget);
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();

    expect(find.text('Uploading'), findsNothing);
    expect(server.log.last, 'DELETE /files/up1');
    expect(server.offsets, isEmpty);
  });

  testWidgets('fits a narrow phone with large text', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openUploads(tester, [
      video('VJ Junior - Kabaka S01E02.mp4'),
    ], size: const Size(320, 2400));
    await choose(tester);
    await tester.ensureVisible(find.text('How to name files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('How to name files'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('VJ Junior - Prison Break S01E02.mp4'), findsOneWidget);
  });
}
