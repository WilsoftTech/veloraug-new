import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/admin/uploads/file_names.dart' show maxVideoBytes;
import 'package:veloraug/admin/uploads/tus.dart';
import 'package:veloraug/admin/uploads/upload_queue.dart';
import 'package:veloraug/api/catalogue_api.dart' show EditionKind;

import '../support.dart';
import 'upload_fakes.dart';

UploadPlan movie(String title, {int? year, String? vjId, String? vjName}) =>
    UploadPlan(
      kind: EditionKind.movie,
      title: title,
      year: year,
      vjId: vjId,
      vjName: vjName,
    );

UploadPlan episode(
  String title,
  int season,
  int number, {
  String? vjId,
  String? series,
}) => UploadPlan(
  kind: EditionKind.series,
  title: title,
  season: season,
  episode: number,
  vjId: vjId,
  seriesEditionId: series,
);

void main() {
  late FakeTusServer server;
  late Admin admin;
  late MemoryUploadStore store;
  late FakeNetwork network;
  late DateTime now;

  setUp(() {
    server = FakeTusServer();
    admin = Admin(server);
    store = MemoryUploadStore();
    network = FakeNetwork();
    now = DateTime.utc(2026, 11, 18, 12);
  });

  Future<UploadQueue> queue({int parallel = 2}) async {
    final auth = fakeAuth(signedIn: true);
    await auth.restore();
    final q = UploadQueue(
      api: admin.api.adminApi(auth),
      tus: TusClient(server),
      endpoint: Uri.parse(uploadEndpoint),
      store: store,
      network: network,
      maxParallel: parallel,
      chunkBytes: 10,
      now: () => now,
    );
    addTearDown(q.dispose);
    return q;
  }

  /// Lets the queue's requests run, within the test's fake time.
  Future<void> settle(
    WidgetTester tester, [
    Duration by = Duration.zero,
  ]) async {
    await tester.pump(by);
    for (var i = 0; i < 30; i++) {
      await tester.pump();
    }
  }

  UploadTask only(UploadQueue q) => q.tasks.single;

  testWidgets('a movie makes its draft, credits the VJ and uploads in parts', (
    tester,
  ) async {
    final q = await queue();
    await q.add([
      (
        video('VJ Junior - Commando (1985).mp4'),
        movie('Commando', year: 1985, vjId: 'v1', vjName: 'VJ Junior'),
      ),
    ]);
    await settle(tester);

    expect(admin.drafts.single, {
      'kind': 'movie',
      'title': 'Commando',
      'year': 1985,
    });
    expect(admin.credits, ['e1:v1']);
    expect(server.log, [
      'POST /files/',
      'PATCH /files/up1',
      'PATCH /files/up1',
      'PATCH /files/up1',
    ]);
    expect(server.patchOffsets, [0, 10, 20]);
    expect(server.finished('up1'), isTrue);
    expect(
      utf8.decode(base64.decode(server.names['up1']!.split(' ').last)),
      'VJ Junior - Commando (1985).mp4',
    );
    final task = only(q);
    expect(task.phase, UploadPhase.finished);
    expect(task.percent, 100);
    expect(store.records, isEmpty);
  });

  testWidgets('two upload at a time, and the rest wait their turn', (
    tester,
  ) async {
    final q = await queue();
    server.hold = Completer();
    await q.add([
      for (final name in ['a', 'b', 'c']) (video('$name.mp4'), movie(name)),
    ]);
    await settle(tester);

    expect(
      [for (final t in q.tasks) t.phase],
      [UploadPhase.uploading, UploadPhase.uploading, UploadPhase.queued],
    );
    expect(admin.drafts.length, 2);
    server.hold!.complete();
    server.hold = null;
    await settle(tester);
    expect(q.tasks.every((t) => t.phase == UploadPhase.finished), isTrue);
  });

  testWidgets(
    'a dropped connection retries and carries on from the server offset',
    (tester) async {
      final q = await queue();
      server.dropAfter = 4;
      await q.add([(video('a.mp4'), movie('A'))]);
      await settle(tester);

      final task = only(q);
      expect(task.phase, UploadPhase.retrying);
      expect(task.sent, 4);
      expect(task.retryAt, now.add(const Duration(seconds: 1)));

      await settle(tester, const Duration(seconds: 1));
      expect(task.phase, UploadPhase.finished);
      // Asked where to carry on, then sent only the rest.
      expect(server.log.sublist(2), [
        'HEAD /files/up1',
        'PATCH /files/up1',
        'PATCH /files/up1',
        'PATCH /files/up1',
      ]);
      expect(server.patchOffsets, [0, 4, 14, 24]);
      expect(admin.drafts.length, 1);
    },
  );

  testWidgets(
    'retries wait longer each time, and the network coming back starts at once',
    (tester) async {
      final q = await queue();
      server.offline = true;
      await q.add([(video('a.mp4'), movie('A'))]);
      await settle(tester);
      expect(only(q).phase, UploadPhase.retrying);

      final delays = <Duration>[];
      for (var i = 0; i < 4; i++) {
        delays.add(only(q).retryAt!.difference(now));
        await settle(tester, delays.last);
      }
      expect(delays, [
        const Duration(seconds: 1),
        const Duration(seconds: 3),
        const Duration(seconds: 5),
        const Duration(seconds: 10),
      ]);

      network.set(false);
      expect(only(q).phase, UploadPhase.offline);
      server.offline = false;
      network.set(true);
      await settle(tester);
      expect(only(q).phase, UploadPhase.finished);
    },
  );

  testWidgets(
    'pause stops sending and resume carries on without starting again',
    (tester) async {
      final q = await queue();
      await q.add([(video('a.mp4'), movie('A'))]);
      server.hold = Completer();
      await settle(tester);
      final task = only(q);
      expect(task.phase, UploadPhase.uploading);

      q.pause(task.id);
      await settle(tester);
      expect(task.phase, UploadPhase.paused);
      expect(store.records[task.id]!['paused'], isTrue);
      expect(store.records[task.id]!['upload_url'], '${uploadEndpoint}up1');

      server.hold = null;
      await q.resume(task.id);
      await settle(tester);
      expect(task.phase, UploadPhase.finished);
      expect(admin.drafts.length, 1);
      expect(server.log.where((l) => l.startsWith('POST')).length, 1);
      expect(server.log, contains('HEAD /files/up1'));
    },
  );

  testWidgets('after a power cut the same file dropped again carries on', (
    tester,
  ) async {
    final first = await queue();
    server.dropAfter = 4;
    await first.add([(video('a.mp4', size: 30), movie('A'))]);
    await settle(tester);
    expect(server.offsets['up1'], 4);
    // The page closes.
    first.dispose();

    final second = await queue();
    await second.restore();
    final task = only(second);
    expect(task.phase, UploadPhase.needsFile);
    expect(task.canReopen, isFalse);
    expect(task.percent, 13);

    // A different file with the same name isn't taken for it.
    final other = await second.attach([video('a.mp4', size: 30, modified: 1)]);
    expect(other.length, 1);
    expect(task.phase, UploadPhase.needsFile);

    final none = await second.attach([video('a.mp4', size: 30)]);
    expect(none, isEmpty);
    await settle(tester);
    expect(task.phase, UploadPhase.finished);
    expect(admin.drafts.length, 1);
    expect(server.patchOffsets, [0, 4, 14, 24]);
    expect(store.records, isEmpty);
  });

  testWidgets('with a kept file handle, Resume opens the file again', (
    tester,
  ) async {
    final first = await queue();
    final handle = Object();
    server.hold = Completer();
    await first.add([(video('a.mp4', handle: handle), movie('A'))]);
    await settle(tester);
    first.dispose();
    server.hold = null;

    final second = await queue();
    await second.restore();
    final task = only(second);
    expect(task.canReopen, isTrue);

    await second.resume(task.id);
    expect(task.problem, UploadProblem.fileUnreadable);

    store.reopenable[task.id] = FakeFile('a.mp4', size: 25, lastModified: 5);
    await second.resume(task.id);
    expect(task.problem, UploadProblem.fileChanged);

    store.reopenable[task.id] = FakeFile('a.mp4');
    await second.resume(task.id);
    await settle(tester);
    expect(task.phase, UploadPhase.finished);
  });

  testWidgets('a key lost before the upload started is replaced', (
    tester,
  ) async {
    final first = await queue();
    server.offline = true;
    await first.add([(video('a.mp4'), movie('A'))]);
    await settle(tester);
    first.dispose();
    server.offline = false;

    final second = await queue();
    await second.restore();
    await second.attach([video('a.mp4')]);
    await settle(tester);

    expect(admin.newKeys, ['i1']);
    expect(only(second).phase, UploadPhase.finished);
  });

  testWidgets('an upload the server lost starts again with a new key', (
    tester,
  ) async {
    final q = await queue();
    server.dropAfter = 5;
    await q.add([(video('a.mp4'), movie('A'))]);
    await settle(tester);
    server.offsets.remove('up1');

    await settle(tester, const Duration(seconds: 1));
    final task = only(q);
    expect(task.phase, UploadPhase.finished);
    expect(task.restarted, isTrue);
    expect(admin.newKeys, ['i1']);
    expect(server.finished('up2'), isTrue);
  });

  testWidgets('remove deletes the part uploaded from the server', (
    tester,
  ) async {
    final q = await queue();
    server.hold = Completer();
    await q.add([(video('a.mp4'), movie('A'))]);
    await settle(tester);
    final task = only(q);

    await q.remove(task.id);
    await settle(tester);
    expect(q.tasks, isEmpty);
    expect(server.log.last, 'DELETE /files/up1');
    expect(server.offsets, isEmpty);
    expect(store.records, isEmpty);
  });

  testWidgets('a remove that fails can be tried again', (tester) async {
    final q = await queue();
    server.hold = Completer();
    await q.add([(video('a.mp4'), movie('A'))]);
    await settle(tester);
    final task = only(q);

    server.offline = true;
    await q.remove(task.id);
    expect(task.phase, UploadPhase.failed);
    expect(task.problem, UploadProblem.removeFailed);

    server.offline = false;
    await q.resume(task.id);
    expect(q.tasks, isEmpty);
    expect(server.offsets, isEmpty);
  });

  testWidgets('episodes of a new series share one draft, credited once', (
    tester,
  ) async {
    final q = await queue();
    await q.add([
      (video('k1.mp4'), episode('Kabaka', 1, 1, vjId: 'v1')),
      (video('k2.mp4'), episode('Kabaka', 1, 2, vjId: 'v1')),
    ]);
    await settle(tester);

    expect(admin.drafts, [
      {'kind': 'series', 'title': 'Kabaka', 'season': 1, 'episode': 1},
      {'kind': 'series', 'series_edition_id': 'e1', 'season': 1, 'episode': 2},
    ]);
    expect(admin.credits, ['e1:v1']);
    expect(q.tasks.every((t) => t.phase == UploadPhase.finished), isTrue);
  });

  testWidgets('an episode of an existing series is added to it', (
    tester,
  ) async {
    final q = await queue();
    await q.add([(video('k3.mp4'), episode('Kabaka', 1, 3, series: 'old'))]);
    await settle(tester);

    expect(admin.drafts.single, {
      'kind': 'series',
      'series_edition_id': 'old',
      'season': 1,
      'episode': 3,
    });
    expect(admin.credits, isEmpty);
  });

  testWidgets('a refused draft stops with the reason', (tester) async {
    admin.api.admin['POST /drafts'] = (_) =>
        json({'detail': 'Episode 1 already exists'}, 400);
    final q = await queue();
    await q.add([(video('a.mp4'), movie('A'))]);
    await settle(tester);

    final task = only(q);
    expect(task.phase, UploadPhase.failed);
    expect(task.problem, UploadProblem.refused);
    expect(task.adminError!.detail, 'Episode 1 already exists');
  });

  testWidgets('a file over 50 GB is refused before anything is made', (
    tester,
  ) async {
    final q = await queue();
    await q.add([
      (video('big.mkv', size: 50 * 1024 * 1024 * 1024 + 1), movie('Big')),
    ]);
    await settle(tester);

    expect(only(q).problem, UploadProblem.tooLarge);
    expect(admin.drafts, isEmpty);
  });

  testWidgets('speed and time left come from the last few seconds', (
    tester,
  ) async {
    final q = await queue();
    await q.add([(video('a.mp4', size: 100), movie('A'))]);
    server.hold = Completer();
    await settle(tester);
    final task = only(q);
    expect(task.sent, 0);

    // 10 bytes arrive over 2 seconds.
    now = now.add(const Duration(seconds: 2));
    server.hold!.complete();
    server.hold = Completer();
    await settle(tester);
    expect(task.speed, 5);
    expect(task.timeLeft, const Duration(seconds: 18));
    server.hold!.complete();
    server.hold = null;
    await settle(tester);
  });

  testWidgets('a refused credit is told, and the upload carries on', (
    tester,
  ) async {
    admin.api.admin['PUT /editions/e1/credit'] = (_) =>
        json({'detail': 'This VJ already has an edition of that title'}, 400);
    final q = await queue();
    await q.add([(video('a.mp4'), movie('A', vjId: 'v1'))]);
    await settle(tester);

    final task = only(q);
    expect(task.phase, UploadPhase.finished);
    expect(
      task.creditError!.detail,
      'This VJ already has an edition of that title',
    );
  });

  group('Step 13H', () {
    testWidgets('a file for a draft made already uses its item and key', (
      tester,
    ) async {
      server.keys.add('the-drafts-own-key');
      final q = await queue();

      await q.addToItem(
        video('a.mp4'),
        movie('A'),
        editionId: 'e9',
        itemId: 'i9',
        key: 'the-drafts-own-key',
      );
      await settle(tester);

      final task = only(q);
      expect(task.phase, UploadPhase.finished);
      expect(task.editionId, 'e9');
      // No second draft, and no second key.
      expect(admin.drafts, isEmpty);
      expect(admin.newKeys, isEmpty);
    });

    testWidgets('without its key, a new one is made for the same item', (
      tester,
    ) async {
      final q = await queue();

      await q.addToItem(
        video('a.mp4'),
        movie('A'),
        editionId: 'e9',
        itemId: 'i9',
      );
      await settle(tester);

      expect(only(q).phase, UploadPhase.finished);
      expect(admin.drafts, isEmpty);
      expect(admin.newKeys, ['i9']);
    });

    testWidgets('pause all, resume all and remove all', (tester) async {
      server.hold = Completer();
      final q = await queue();
      await q.add([
        (video('a.mp4'), movie('A')),
        (video('b.mp4'), movie('B')),
        (video('c.mp4'), movie('C')),
      ]);
      await settle(tester);
      expect(q.tasks.map((t) => t.phase), [
        UploadPhase.uploading,
        UploadPhase.uploading,
        UploadPhase.queued,
      ]);
      expect((q.canPauseAll, q.canResumeAll), (true, false));

      q.pauseAll();
      await settle(tester);
      expect(q.tasks.map((t) => t.phase), everyElement(UploadPhase.paused));
      expect((q.canPauseAll, q.canResumeAll), (false, true));

      await q.resumeAll();
      await settle(tester);
      expect(
        q.tasks.where((t) => t.phase == UploadPhase.uploading),
        hasLength(2),
      );
      expect(q.tasks.last.phase, UploadPhase.queued);

      await q.removeAll();
      await settle(tester);
      expect(q.tasks, isEmpty);
      expect(q.canRemoveAll, isFalse);
      // What reached tusd is deleted there.
      expect(server.offsets, isEmpty);
      expect(store.records, isEmpty);
    });

    testWidgets('resume all leaves a file too large to upload', (tester) async {
      final q = await queue();
      await q.add([(video('big.mp4', size: maxVideoBytes + 1), movie('Big'))]);
      await settle(tester);

      expect(only(q).problem, UploadProblem.tooLarge);
      expect(q.canResumeAll, isFalse);
    });

    testWidgets('a deleted new series takes its waiting episodes too', (
      tester,
    ) async {
      server.hold = Completer();
      final q = await queue(parallel: 1);
      await q.add([
        (video('k1.mp4'), episode('Kabaka', 1, 1)),
        (video('k2.mp4'), episode('Kabaka', 1, 2)),
        (video('k3.mp4'), episode('Kabaka', 1, 3)),
        (video('other.mp4'), movie('Other')),
      ]);
      await settle(tester);
      final series = q.tasks.first.editionId!;
      // The others haven't started, so don't know the series' ID yet.
      expect(q.tasks.skip(1).map((t) => t.editionId), everyElement(isNull));

      await q.removeForEdition(series);
      await settle(tester);

      expect(q.tasks.map((t) => t.fileName), ['other.mp4']);
      // Nothing made the series again; the movie made its own draft.
      expect(admin.drafts.where((d) => d['kind'] == 'series'), hasLength(1));
    });

    testWidgets('a deleted edition takes only its own uploads with it', (
      tester,
    ) async {
      server.hold = Completer();
      final q = await queue();
      await q.add([(video('a.mp4'), movie('A')), (video('b.mp4'), movie('B'))]);
      await settle(tester);
      final doomed = q.tasks.first.editionId!;

      await q.removeForEdition(doomed);
      await settle(tester);

      expect(q.tasks.map((t) => t.fileName), ['b.mp4']);
    });
  });

  test('the upload is only ever sent back to the same server', () async {
    final tus = TusClient(_Redirecting());
    await expectLater(
      tus.create(
        endpoint: Uri.parse(uploadEndpoint),
        file: FakeFile('a.mp4'),
        key: 'k',
      ),
      throwsA(isA<TusRetry>()),
    );
  });
}

class _Redirecting implements TusTransport {
  @override
  Future<TusReply> send(
    String method,
    Uri url,
    Map<String, String> headers, {
    LocalVideoFile? file,
    int start = 0,
    int end = 0,
    void Function(int sent)? onProgress,
    TusCancel? cancel,
  }) async =>
      const TusReply(201, {'location': 'https://elsewhere.example/files/x'});
}
