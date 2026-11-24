import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/api/playback_api.dart';
import 'package:veloraug/downloads/downloads.dart';

import 'download_fakes.dart';

void main() {
  late FakeMediaServer server;
  late FakeTarget target;
  late MemoryDownloadRecords records;
  late Downloads downloads;

  setUp(() async {
    server = FakeMediaServer();
    target = FakeTarget();
    records = MemoryDownloadRecords();
    downloads = Downloads(
      target: target,
      api: server.api(),
      records: records,
      clock: () => DateTime.utc(2026, 11, 24, 9),
      checkEvery: const Duration(milliseconds: 1),
    );
    await downloads.load();
  });

  tearDown(() => downloads.dispose());

  test('an offer names each quality\'s file, with its size', () async {
    final offer = await downloads.offer(movieId);

    expect(offer.files.map((f) => f.quality.label), ['720p', '360p']);
    expect(offer.files.map((f) => f.bytes), [1200000000, 350000000]);
    final file = offer.files.first;
    expect(file.fileName, 'Fast X - VJ Junior - 720p.mp4');
    expect(file.url.path, '/v1/GRANT1.sig/720p/download.mp4');
    expect(file.url.queryParameters['name'], 'Fast X - VJ Junior - 720p.mp4');
  });

  test('a quality whose file isn\'t made yet is left out', () async {
    server.sizes.remove('720p');

    final offer = await downloads.offer(movieId);

    expect(offer.files.map((f) => f.quality.label), ['360p']);
  });

  test('a film with no files yet can\'t be downloaded yet', () async {
    server.sizes.clear();

    await expectLater(
      downloads.offer(movieId),
      throwsA(
        isA<PlaybackException>().having(
          (e) => e.failure,
          'failure',
          PlaybackFailure.notReady,
        ),
      ),
    );
  });

  test('without a pass, the offer is refused as playback is', () async {
    server.grantStatus = 402;

    await expectLater(
      downloads.offer(movieId),
      throwsA(
        isA<PlaybackException>().having(
          (e) => e.failure,
          'failure',
          PlaybackFailure.needsPass,
        ),
      ),
    );
  });

  test('on a phone, a started download is followed and kept', () async {
    final offer = await downloads.offer(movieId);

    await downloads.start(movieId, offer.files.last, movieInfo);

    expect(target.started.single.fileName, 'Fast X - VJ Junior - 360p.mp4');
    final download = downloads.latestOf(movieId)!;
    expect(download.quality, '360p');
    expect(download.state, FileState.waiting);

    target.statuses['1'] = const FileStatus(
      state: FileState.running,
      bytes: 100,
      total: 400,
    );
    await downloads.refresh();
    expect(download.progress, 0.25);

    target.statuses['1'] = const FileStatus(
      state: FileState.done,
      bytes: 400,
      total: 400,
    );
    await downloads.refresh();
    expect(download.state, FileState.done);
    expect(downloads.usedBytes, 400);

    // Opened again later, it is still followed.
    final again = Downloads(
      target: target,
      api: server.api(),
      records: records,
    );
    await again.load();
    expect(again.latestOf(movieId)!.state, FileState.done);
    expect(again.latestOf(movieId)!.fileName, 'Fast X - VJ Junior - 360p.mp4');
    again.dispose();
  });

  test('running downloads are checked until they finish', () async {
    final offer = await downloads.offer(movieId);
    await downloads.start(movieId, offer.files.first, movieInfo);

    target.statuses['1'] = const FileStatus(state: FileState.done, total: 9);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(downloads.latestOf(movieId)!.state, FileState.done);
  });

  test('a download deleted outside the app shows as failed', () async {
    final offer = await downloads.offer(movieId);
    await downloads.start(movieId, offer.files.first, movieInfo);

    target.statuses.clear();
    await downloads.refresh();

    expect(downloads.latestOf(movieId)!.state, FileState.failed);
  });

  test('removing a download deletes its file and forgets it', () async {
    final offer = await downloads.offer(movieId);
    await downloads.start(movieId, offer.files.first, movieInfo);

    await downloads.remove(downloads.latestOf(movieId)!);

    expect(target.removed, ['1']);
    expect(downloads.downloads, isEmpty);
    expect(jsonDecode(records.text!)['downloads'], isEmpty);
  });

  test('a refused permission says so and follows nothing', () async {
    final offer = await downloads.offer(movieId);
    target.refuse = DownloadRefusal.noPermission;

    await expectLater(
      downloads.start(movieId, offer.files.first, movieInfo),
      throwsA(isA<DownloadRefused>()),
    );
    expect(downloads.downloads, isEmpty);
  });

  test('a browser saves the file and the app follows nothing', () async {
    final browser = FakeTarget(followed: false);
    final web = Downloads(target: browser, api: server.api());
    await web.load();
    final offer = await web.offer(movieId);

    await web.start(movieId, offer.files.first, movieInfo);

    expect(browser.started.single.url.path, endsWith('/720p/download.mp4'));
    expect(web.downloads, isEmpty);
    web.dispose();
  });
}
