import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/api/playback_api.dart';
import 'package:veloraug/downloads/download_manager.dart';
import 'package:veloraug/downloads/download_storage.dart';

import 'download_fakes.dart';

/// Lets the manager run until nothing is queued, downloading or waiting.
Future<void> settle(DownloadManager downloads) async {
  for (var i = 0; i < 500; i++) {
    await Future<void>.delayed(Duration.zero);
    final busy = downloads.downloads.any(
      (d) =>
          d.state == DownloadState.queued ||
          d.state == DownloadState.downloading ||
          d.state == DownloadState.waiting,
    );
    if (!busy) return;
  }
  fail('The downloads never settled');
}

Future<Download> download720(
  DownloadManager downloads, {
  String itemId = movieId,
}) async {
  final offer = await downloads.prepare(itemId);
  await downloads.start(offer, offer.qualities.first, movieInfo);
  await settle(downloads);
  return downloads[itemId]!;
}

void main() {
  late FakeMediaServer server;
  late MemoryDownloadStorage storage;
  late DownloadManager downloads;

  setUp(() async {
    server = FakeMediaServer();
    storage = MemoryDownloadStorage();
    downloads = manager(server, storage);
    await downloads.load();
  });

  tearDown(() => downloads.dispose());

  test(
    'an offer lists each quality with about how much room it takes',
    () async {
      final offer = await downloads.prepare(movieId);

      expect(offer.qualities.map((q) => q.quality.label), ['720p', '360p']);
      // Five six-second chunks at 800 kbit/s.
      expect(offer.qualities.first.estimatedBytes, 800000 * 30 ~/ 8);
      expect(offer.grant.offlineUntil, server.offlineUntil);
    },
  );

  test(
    'one quality is downloaded whole, kept, and watchable offline',
    () async {
      final done = await download720(downloads);

      expect(done.state, DownloadState.done);
      expect(done.progress, 1);
      final files = storage.files[movieId]!;
      expect(
        files.keys,
        containsAll(['720p/init_0.mp4', '720p/seg_00004.m4s']),
      );
      expect(files.keys.where((k) => k.startsWith('360p')), isEmpty);
      final master = utf8.decode(files['master.m3u8']!);
      expect(master, contains('720p/index.m3u8'));
      expect(master, isNot(contains('360p')));
      expect(downloads.watchable(done), Watchable.yes);
      expect(downloads.usedBytes, greaterThan(0));

      // Opened again later, it is still there.
      final reopened = manager(server, storage);
      await reopened.load();
      expect(reopened[movieId]!.state, DownloadState.done);
      expect(reopened.watchable(reopened[movieId]!), Watchable.yes);
      reopened.dispose();
    },
  );

  test(
    'a download stopped by the app closing carries on from its files',
    () async {
      final offer = await downloads.prepare(movieId);
      await downloads.start(offer, offer.qualities.first, movieInfo);
      // The app closes part way: the index says downloading, three files are
      // whole.
      downloads.dispose();
      final index = jsonDecode(storage.index!) as Map<String, Object?>;
      final row = (index['downloads'] as List).single as Map<String, Object?>;
      row
        ..['state'] = 'downloading'
        ..['files'] = [
          'init_0.mp4',
          for (var i = 0; i < 5; i++) 'seg_0000$i.m4s',
        ];
      storage
        ..index = jsonEncode(index)
        ..files[movieId] = {
          'master.m3u8': storage.files[movieId]!['master.m3u8']!,
          for (final name in ['init_0.mp4', 'seg_00000.m4s', 'seg_00001.m4s'])
            '720p/$name': FakeMediaServer.bytesOf('720p/$name'),
        };
      server.fetched.clear();

      downloads = manager(server, storage);
      await downloads.load();
      await settle(downloads);

      expect(downloads[movieId]!.state, DownloadState.done);
      expect(server.fetched, [
        '720p/seg_00002.m4s',
        '720p/seg_00003.m4s',
        '720p/seg_00004.m4s',
      ]);
    },
  );

  test(
    'a grant the gateway refuses is replaced once, and carries on',
    () async {
      final offer = await downloads.prepare(movieId);
      server.refusedGrants.add('GRANT1.sig');

      await downloads.start(offer, offer.qualities.first, movieInfo);
      await settle(downloads);

      expect(downloads[movieId]!.state, DownloadState.done);
      expect(server.grants, 2);
    },
  );

  test('a grant about to run out is replaced before it is used', () async {
    server.grantLasts = const Duration(minutes: 1);
    final offer = await downloads.prepare(movieId);
    server.grantLasts = const Duration(hours: 1);

    await downloads.start(offer, offer.qualities.first, movieInfo);
    await settle(downloads);

    expect(downloads[movieId]!.state, DownloadState.done);
    expect(server.grants, 2);
  });

  test('a file dropped once is fetched again at once', () async {
    server.dropOnce.add('720p/seg_00002.m4s');

    final done = await download720(downloads);

    expect(done.state, DownloadState.done);
  });

  test('a connection down for longer waits, then carries on', () async {
    downloads.dispose();
    downloads = DownloadManager(
      storage: storage,
      api: server.api(),
      clock: () => server.now,
      retryAfter: (_) => const Duration(hours: 1),
      fileRetryDelay: Duration.zero,
    );
    await downloads.load();
    server.statusFor['720p/seg_00003.m4s'] = 503;

    final offer = await downloads.prepare(movieId);
    await downloads.start(offer, offer.qualities.first, movieInfo);
    for (var i = 0; i < 50; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(downloads[movieId]!.state, DownloadState.waiting);

    server.statusFor.clear();
    downloads.resume(movieId);
    await settle(downloads);
    expect(downloads[movieId]!.state, DownloadState.done);
  });

  test('without a pass, a download stops and says so', () async {
    server.grantStatus = 402;

    await expectLater(
      downloads.prepare(movieId),
      throwsA(
        isA<PlaybackException>().having(
          (e) => e.failure,
          'failure',
          PlaybackFailure.needsPass,
        ),
      ),
    );
  });

  test('a full phone stops the download and says so', () async {
    final offer = await downloads.prepare(movieId);
    storage.full = true;

    await downloads.start(offer, offer.qualities.first, movieInfo);
    await settle(downloads);

    expect(downloads[movieId]!.state, DownloadState.failed);
    expect(downloads[movieId]!.problem, DownloadProblem.storageFull);
  });

  test('pause keeps what is done; resume carries on; remove deletes', () async {
    final offer = await downloads.prepare(movieId);
    await downloads.start(offer, offer.qualities.first, movieInfo);
    downloads.pause(movieId);
    await settle(downloads);
    expect(downloads[movieId]!.state, DownloadState.paused);

    downloads.resume(movieId);
    await settle(downloads);
    expect(downloads[movieId]!.state, DownloadState.done);

    await downloads.remove(movieId);
    expect(downloads[movieId], isNull);
    expect(storage.files[movieId], isNull);
    expect(jsonDecode(storage.index!)['downloads'], isEmpty);
  });

  group('offline licences', () {
    test('a licence run out needs a check-in, which renews it', () async {
      final done = await download720(downloads);
      server.now = server.offlineUntil.add(const Duration(minutes: 1));
      expect(downloads.watchable(done), Watchable.checkIn);

      server.offlineUntil = server.now.add(const Duration(days: 7));
      expect(await downloads.renewLicences(), isTrue);

      expect(downloads.watchable(done), Watchable.yes);
    });

    test('licences are renewed only when due, unless forced', () async {
      await download720(downloads);
      final before = server.licenceRenewals;

      await downloads.renewLicences();
      expect(server.licenceRenewals, before);
      await downloads.renewLicences(force: true);
      expect(server.licenceRenewals, before + 1);
    });

    test('a title taken down is deleted', () async {
      final done = await download720(downloads);
      server.takenDown.add(movieId);

      await downloads.renewLicences(force: true);

      expect(done.state, DownloadState.unavailable);
      expect(downloads.watchable(done), Watchable.notFinished);
      expect(storage.files[movieId], isNull);
    });

    test('an ended pass locks downloads until a pass is bought', () async {
      final done = await download720(downloads);
      server.licenceStatus = 402;

      await downloads.renewLicences(force: true);
      expect(done.problem, DownloadProblem.noPass);
      expect(downloads.watchable(done), Watchable.checkIn);
      expect(storage.files[movieId], isNotNull, reason: 'kept for later');

      server.licenceStatus = 200;
      await downloads.renewLicences();
      expect(done.problem, isNull);
      expect(downloads.watchable(done), Watchable.yes);
    });

    test('a removed device that can’t register again is locked', () async {
      final done = await download720(downloads);
      server
        ..licenceStatus = 403
        ..licenceCode = 'device_required';

      await downloads.renewLicences(force: true);

      expect(done.problem, DownloadProblem.deviceRemoved);
      expect(downloads.watchable(done), Watchable.checkIn);
    });

    test('a clock turned back needs a check-in', () async {
      final done = await download720(downloads);
      server.now = server.now.add(const Duration(days: 3));
      expect(downloads.watchable(done), Watchable.yes);

      server.now = server.now.subtract(const Duration(days: 2));
      expect(downloads.watchable(done), Watchable.clockChanged);

      await downloads.renewLicences(force: true);
      expect(downloads.watchable(done), Watchable.yes);
    });

    test('no answer changes nothing', () async {
      final done = await download720(downloads);
      server.licenceStatus = 500;

      expect(await downloads.renewLicences(force: true), isFalse);

      expect(done.problem, isNull);
      expect(downloads.watchable(done), Watchable.yes);
    });
  });

  test('item IDs and paths are checked before they touch storage', () {
    expect(() => checkDownloadPath('../etc'), throwsArgumentError);
    expect(
      () => checkDownloadPath(movieId, '../../index.json'),
      throwsArgumentError,
    );
    checkDownloadPath(movieId, '720p/seg_00001.m4s');
  });
}
