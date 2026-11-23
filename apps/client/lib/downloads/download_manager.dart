import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../api/playback_api.dart';
import 'download_api.dart';
import 'download_storage.dart';
import 'hls.dart';

/// Where a download has got to.
enum DownloadState {
  /// Waiting its turn: one download runs at a time.
  queued,
  downloading,

  /// The connection dropped: tried again by itself.
  waiting,
  paused,
  done,

  /// Stopped for a reason the viewer must see: [Download.problem].
  failed,

  /// Taken down, or its video replaced: its files are gone.
  unavailable,
}

/// Why a download stopped, or can't be watched.
enum DownloadProblem {
  /// No pass running.
  noPass,

  /// More devices than the plan allows.
  deviceLimit,

  /// This device was removed from the account.
  deviceRemoved,

  /// The phone is full.
  storageFull,

  /// Signed out.
  signedOut,

  /// Anything else: try again.
  unexpected,
}

/// What a download is of, kept with it for the Downloads screen.
class DownloadInfo {
  const DownloadInfo({
    required this.editionId,
    required this.title,
    required this.label,
    this.season,
    this.episode,
    this.episodeTitle,
    this.posterUrl,
  });

  final String editionId;

  /// The movie's or series' title.
  final String title;

  /// Such as "Luganda · VJ Junior".
  final String label;
  final int? season;
  final int? episode;
  final String? episodeTitle;
  final String? posterUrl;

  bool get isEpisode => season != null && episode != null;
}

/// One downloaded or downloading item.
class Download {
  Download({
    required this.itemId,
    required this.info,
    required this.quality,
    required this.offlineUntil,
    required this.licenceCheckedAt,
    required this.createdAt,
    this.bitsPerSecond = 0,
    this.estimatedBytes,
    this.files,
    this.doneFiles = 0,
    this.bytes = 0,
    this.state = DownloadState.queued,
    this.problem,
    this.hasPoster = false,
  });

  final String itemId;
  final DownloadInfo info;
  final VideoQuality quality;
  final int bitsPerSecond;
  final int? estimatedBytes;
  final DateTime createdAt;

  /// Until when it may be watched offline, as the API last said.
  DateTime offlineUntil;
  DateTime licenceCheckedAt;

  /// Every file of its quality, once its playlist has been read.
  List<String>? files;
  int doneFiles;

  /// Bytes on the phone so far.
  int bytes;
  DownloadState state;
  DownloadProblem? problem;
  bool hasPoster;

  /// From 0 to 1, or null before the playlist is read.
  double? get progress {
    final all = files;
    if (all == null || all.isEmpty) return null;
    return doneFiles / all.length;
  }

  /// The folder its files are in, such as "720p".
  String get folder => quality.path.split('/').first;

  Map<String, Object?> toJson() => {
    'item_id': itemId,
    'edition_id': info.editionId,
    'title': info.title,
    'label': info.label,
    'season': info.season,
    'episode': info.episode,
    'episode_title': info.episodeTitle,
    'poster_url': info.posterUrl,
    'quality_label': quality.label,
    'quality_height': quality.height,
    'quality_path': quality.path,
    'bits_per_second': bitsPerSecond,
    'estimated_bytes': estimatedBytes,
    'offline_until': offlineUntil.toUtc().toIso8601String(),
    'licence_checked_at': licenceCheckedAt.toUtc().toIso8601String(),
    'created_at': createdAt.toUtc().toIso8601String(),
    'files': files,
    'done_files': doneFiles,
    'bytes': bytes,
    'state': state.name,
    'problem': problem?.name,
    'has_poster': hasPoster,
  };

  static Download? fromJson(Object? json) {
    if (json case {
      'item_id': final String itemId,
      'edition_id': final String editionId,
      'title': final String title,
      'label': final String label,
      'quality_label': final String qualityLabel,
      'quality_height': final int qualityHeight,
      'quality_path': final String qualityPath,
      'offline_until': final String offlineUntil,
      'licence_checked_at': final String checkedAt,
      'created_at': final String createdAt,
      'state': final String state,
    }) {
      final until = DateTime.tryParse(offlineUntil);
      final checked = DateTime.tryParse(checkedAt);
      final created = DateTime.tryParse(createdAt);
      final files = json['files'];
      if (until == null ||
          checked == null ||
          created == null ||
          !safeDownloadPath.hasMatch(qualityPath)) {
        return null;
      }
      try {
        checkDownloadPath(itemId, qualityPath);
      } on ArgumentError {
        return null;
      }
      return Download(
        itemId: itemId,
        info: DownloadInfo(
          editionId: editionId,
          title: title,
          label: label,
          season: _int(json['season']),
          episode: _int(json['episode']),
          episodeTitle: _string(json['episode_title']),
          posterUrl: _string(json['poster_url']),
        ),
        quality: VideoQuality(
          label: qualityLabel,
          height: qualityHeight,
          path: qualityPath,
        ),
        bitsPerSecond: _int(json['bits_per_second']) ?? 0,
        estimatedBytes: _int(json['estimated_bytes']),
        offlineUntil: until.toUtc(),
        licenceCheckedAt: checked.toUtc(),
        createdAt: created.toUtc(),
        files: files is List
            ? [
                for (final name in files)
                  if (name is String && safeDownloadPath.hasMatch(name)) name,
              ]
            : null,
        doneFiles: _int(json['done_files']) ?? 0,
        bytes: _int(json['bytes']) ?? 0,
        state: DownloadState.values.asNameMap()[state] ?? DownloadState.failed,
        problem: DownloadProblem.values.asNameMap()[json['problem']],
        hasPoster: json['has_poster'] == true,
      );
    }
    return null;
  }
}

/// Whether a download can be watched now.
enum Watchable {
  yes,

  /// Still downloading, paused or failed.
  notFinished,

  /// Its licence ran out: the app must check in, online.
  checkIn,

  /// The phone's clock was turned back: the app must check in, online.
  clockChanged,
}

/// What's offered once the viewer asks to download: a grant, and each
/// quality with about how much room it takes.
class DownloadOffer {
  const DownloadOffer({
    required this.itemId,
    required this.grant,
    required this.master,
    required this.qualities,
  });

  final String itemId;
  final DownloadGrant grant;
  final String master;
  final List<DownloadQuality> qualities;
}

/// Downloads movies and episodes for watching offline, on Android.
///
/// One download runs at a time, three files at once. Each file is written
/// whole, so a download stopped by a pause, a lost connection or the app
/// closing carries on from the last whole file. A lost connection is tried
/// again by itself, sooner at first, then every few minutes.
///
/// A download's grant has no playback session, so downloading never takes
/// a stream or stops the player. When the grant runs out, a new one is
/// asked for, and the download carries on.
///
/// Each download may be watched offline until its licence's date, which the
/// API sets: a week at most, and never past the viewer's passes. The app
/// renews every licence at once when it is online, at most every few hours.
/// A title taken down is deleted. A removed device, an ended pass or too
/// many devices stops every download playing until that is fixed. This is
/// enforced by the app, not by encryption: see docs/step-12a-downloads.md.
class DownloadManager extends ChangeNotifier {
  DownloadManager({
    required this.storage,
    required this.api,
    this.clock = DateTime.now,
    this.parallel = 3,
    this.retryAfter = _defaultRetryAfter,
    this.fileRetries = 2,
    this.fileRetryDelay = const Duration(seconds: 1),
  });

  final DownloadStorage storage;

  /// Null when this build has no playback: then nothing new downloads, and
  /// nothing is renewed, but what is here can still be watched.
  final PlaybackApi? api;
  final DateTime Function() clock;

  /// Files fetched at once.
  final int parallel;

  /// How long to wait before the [attempt]th try after a lost connection.
  final Duration Function(int attempt) retryAfter;

  /// Tries of one file before the download waits for the connection, and
  /// the pause between them.
  final int fileRetries;
  final Duration fileRetryDelay;

  /// The API's OFFLINE_DAYS: the longest a download plays between
  /// check-ins. The API decides; this is only for saying so.
  static const int offlineDays = 7;

  /// Licences are renewed when the oldest was checked this long ago.
  static const Duration renewEvery = Duration(hours: 6);

  /// A clock this far behind the latest time the app has seen was turned
  /// back.
  static const Duration clockSlack = Duration(hours: 1);

  /// A grant this close to its end is renewed before use.
  static const Duration grantMargin = Duration(minutes: 2);

  static Duration _defaultRetryAfter(int attempt) =>
      Duration(seconds: (15 * (1 << attempt.clamp(0, 4))).clamp(15, 300));

  final Map<String, Download> _downloads = {};
  DateTime? _latestSeen;
  bool _loaded = false;
  Future<void>? _loading;

  /// The download running, and its run.
  String? _active;
  Future<void>? _run;

  PlaybackGrant? _grant;
  String? _grantItem;
  Future<PlaybackGrant>? _granting;

  Timer? _retry;
  int _attempt = 0;
  bool _writing = false;
  String? _unsaved;
  Future<void>? _renewing;

  bool _disposed = false;

  bool get loaded => _loaded;

  /// Newest first.
  List<Download> get downloads =>
      _downloads.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  Download? operator [](String itemId) => _downloads[itemId];

  /// Room the downloads take on the phone.
  int get usedBytes => _downloads.values.fold(0, (sum, d) => sum + d.bytes);

  /// Reads what was downloaded before, carries on with anything that was
  /// stopped by the app closing, and renews licences when due.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    String? text;
    try {
      text = await storage.readIndex();
    } on Object {
      text = null;
    }
    if (text != null) {
      try {
        final json = jsonDecode(text);
        if (json case {'downloads': final List<Object?> rows}) {
          for (final row in rows) {
            final download = Download.fromJson(row);
            if (download == null) continue;
            if (download.state == DownloadState.downloading ||
                download.state == DownloadState.waiting) {
              download.state = DownloadState.queued;
            }
            _downloads[download.itemId] = download;
          }
          _latestSeen = switch (json['latest_seen']) {
            final String seen => DateTime.tryParse(seen)?.toUtc(),
            _ => null,
          };
        }
      } on FormatException {
        // An index that can't be read is started again. Folders it named
        // stay until the app is uninstalled or its storage cleared.
      }
    }
    _loaded = true;
    _seeTime();
    _notify();
    _pump();
    unawaited(renewLicences());
  }

  // --- Asking to download ---------------------------------------------------

  /// Asks the API for a grant, and reads which qualities the video comes
  /// in and how long it is. Throws [PlaybackException].
  Future<DownloadOffer> prepare(String itemId) async {
    final playback = api;
    if (playback == null) {
      throw const PlaybackException(PlaybackFailure.unreachable);
    }
    final grant = await playback.downloadGrant(itemId);
    final String master;
    try {
      master = utf8.decode(
        await playback.fetchMedia(
          grant.grant.playlistUrl,
          within: playback.timeout,
        ),
      );
    } on MediaFetchException {
      throw const PlaybackException(PlaybackFailure.unreachable);
    } on FormatException {
      throw const PlaybackException(PlaybackFailure.unexpected);
    }
    final qualities = parseDownloadQualities(master);
    if (qualities.isEmpty) {
      throw const PlaybackException(PlaybackFailure.unexpected);
    }
    // Each quality's length, for its size. Any that can't be read is shown
    // without one.
    final measured = await Future.wait([
      for (final quality in qualities)
        playback
            .fetchMedia(
              grant.grant.qualityUrl(quality.quality),
              within: playback.timeout,
            )
            .then(
              (bytes) => quality.withSeconds(
                parseMediaPlaylist(utf8.decode(bytes)).seconds,
              ),
            )
            .catchError((Object _) => quality),
    ]);
    _grant = grant.grant;
    _grantItem = itemId;
    return DownloadOffer(
      itemId: itemId,
      grant: grant,
      master: master,
      qualities: measured,
    );
  }

  /// Starts downloading [quality] of what [offer] is for. Downloading it
  /// again in another quality replaces the one before.
  Future<void> start(
    DownloadOffer offer,
    DownloadQuality quality,
    DownloadInfo info,
  ) async {
    await load();
    final itemId = offer.itemId;
    checkDownloadPath(itemId, quality.quality.path);
    if (_downloads.containsKey(itemId)) await remove(itemId);
    final now = clock().toUtc();
    final download = Download(
      itemId: itemId,
      info: info,
      quality: quality.quality,
      bitsPerSecond: quality.bitsPerSecond,
      estimatedBytes: quality.estimatedBytes,
      offlineUntil: offer.grant.offlineUntil,
      licenceCheckedAt: now,
      createdAt: now,
    );
    _downloads[itemId] = download;
    _notify();
    try {
      await storage.write(
        itemId,
        'master.m3u8',
        Uint8List.fromList(
          utf8.encode(localMasterPlaylist(offer.master, quality.quality)),
        ),
      );
    } on DownloadStorageFull {
      _fail(download, DownloadProblem.storageFull);
      return;
    } on Object {
      _fail(download, DownloadProblem.unexpected);
      return;
    }
    await _save();
    _pump();
    unawaited(_fetchPoster(download));
  }

  Future<void> _fetchPoster(Download download) async {
    final url = Uri.tryParse(download.info.posterUrl ?? '');
    final playback = api;
    if (url == null || playback == null || url.scheme != 'https') return;
    try {
      final response = await playback.httpClient
          .get(url)
          .timeout(playback.timeout);
      if (response.statusCode != 200 ||
          response.bodyBytes.length > 2 * 1024 * 1024) {
        return;
      }
      await storage.write(download.itemId, 'poster', response.bodyBytes);
      if (_downloads[download.itemId] != download) return;
      download.hasPoster = true;
      _notify();
      await _save();
    } on Object {
      // The download is shown without its poster.
    }
  }

  // --- Pausing, resuming and removing ----------------------------------------

  void pause(String itemId) {
    final download = _downloads[itemId];
    if (download == null) return;
    if (download.state
        case DownloadState.queued ||
            DownloadState.downloading ||
            DownloadState.waiting) {
      download.state = DownloadState.paused;
      _notify();
      unawaited(_save());
    }
  }

  /// Carries on with a paused, failed or waiting download.
  void resume(String itemId) {
    final download = _downloads[itemId];
    if (download == null) return;
    if (download.state
        case DownloadState.paused ||
            DownloadState.failed ||
            DownloadState.waiting) {
      download
        ..state = DownloadState.queued
        ..problem = null;
      _attempt = 0;
      _notify();
      unawaited(_save());
      _pump();
    }
  }

  /// Deletes a download and its files, stopping it first if it's running.
  Future<void> remove(String itemId) async {
    final download = _downloads.remove(itemId);
    if (download == null) return;
    download.state = DownloadState.paused;
    _notify();
    if (_active == itemId) await _run;
    try {
      await storage.delete(itemId);
    } on Object {
      // Left on the phone; the index no longer names it.
    }
    await _save();
  }

  // --- Watching --------------------------------------------------------------

  Watchable watchable(Download download) {
    if (download.state != DownloadState.done) return Watchable.notFinished;
    final now = clock().toUtc();
    final latest = _latestSeen;
    if (latest != null && now.isBefore(latest.subtract(clockSlack))) {
      return Watchable.clockChanged;
    }
    _seeTime();
    if (!now.isBefore(download.offlineUntil)) return Watchable.checkIn;
    return Watchable.yes;
  }

  /// The local playlist the player opens.
  Uri playUri(Download download) => storage.playUri(download.itemId);

  ImageProvider? poster(Download download) =>
      download.hasPoster ? storage.image(download.itemId, 'poster') : null;

  void _seeTime() {
    final now = clock().toUtc();
    final latest = _latestSeen;
    if (latest == null || now.isAfter(latest)) _latestSeen = now;
  }

  // --- Licences ----------------------------------------------------------------

  /// Renews every download's licence with the API, when one is due, or
  /// always with [force]. Answers whether the API was reached.
  Future<bool> renewLicences({bool force = false}) async {
    final running = _renewing;
    if (running != null) {
      await running;
      return true;
    }
    final playback = api;
    final kept = [
      for (final d in _downloads.values)
        if (d.state != DownloadState.unavailable) d,
    ];
    if (playback == null || kept.isEmpty) return false;
    final now = clock().toUtc();
    final due = kept.any(
      (d) =>
          now.difference(d.licenceCheckedAt) >= renewEvery ||
          !now.isBefore(d.offlineUntil) ||
          d.problem == DownloadProblem.noPass ||
          d.problem == DownloadProblem.deviceLimit ||
          d.problem == DownloadProblem.deviceRemoved,
    );
    if (!force && !due) return true;
    var reached = false;
    final renewing = _renewing = () async {
      for (var at = 0; at < kept.length; at += maxLicencesPerRequest) {
        final batch = kept.skip(at).take(maxLicencesPerRequest).toList();
        final answer = await playback.renewLicences([
          for (final d in batch) d.itemId,
        ]);
        if (answer is LicencesUnknown) return;
        reached = true;
        _applyLicences(batch, answer);
      }
    }();
    try {
      await renewing;
    } finally {
      _renewing = null;
    }
    if (reached) {
      // The API answered, so the clock is believed again.
      _latestSeen = clock().toUtc();
      _notify();
      await _save();
    }
    return reached;
  }

  void _applyLicences(List<Download> batch, LicenceAnswer answer) {
    final now = clock().toUtc();
    switch (answer) {
      case LicencesRenewed(:final until):
        for (final download in batch) {
          if (!until.containsKey(download.itemId)) continue;
          final date = until[download.itemId];
          if (date == null) {
            _takeDown(download);
            continue;
          }
          download
            ..offlineUntil = date
            ..licenceCheckedAt = now;
          if (_isLicenceProblem(download.problem)) {
            download.problem = null;
            if (download.state == DownloadState.failed) {
              download.state = DownloadState.paused;
            }
          }
        }
      case LicencesRefused(:final reason):
        final problem = switch (reason) {
          LicenceRefusal.noPass => DownloadProblem.noPass,
          LicenceRefusal.deviceLimit => DownloadProblem.deviceLimit,
          LicenceRefusal.deviceRemoved => DownloadProblem.deviceRemoved,
        };
        for (final download in batch) {
          if (now.isBefore(download.offlineUntil)) download.offlineUntil = now;
          download
            ..licenceCheckedAt = now
            ..problem = problem;
          if (download.state != DownloadState.done) {
            download.state = DownloadState.failed;
          }
        }
      case LicencesUnknown():
        break;
    }
  }

  static bool _isLicenceProblem(DownloadProblem? problem) =>
      problem == DownloadProblem.noPass ||
      problem == DownloadProblem.deviceLimit ||
      problem == DownloadProblem.deviceRemoved;

  /// A title taken down: its files go, and the row says so.
  void _takeDown(Download download) {
    download
      ..state = DownloadState.unavailable
      ..problem = null
      ..bytes = 0
      ..doneFiles = 0
      ..hasPoster = false;
    unawaited(storage.delete(download.itemId).catchError((Object _) {}));
  }

  // --- Downloading -------------------------------------------------------------

  /// Starts the oldest queued download, if none is running.
  void _pump() {
    if (_disposed || _active != null) return;
    final next =
        _downloads.values.where((d) => d.state == DownloadState.queued).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (next.isEmpty) return;
    final download = next.first;
    _active = download.itemId;
    _run = _download(download).whenComplete(() {
      _active = null;
      _run = null;
      _pump();
    });
  }

  bool _stopped(Download download) =>
      _disposed ||
      download.state != DownloadState.downloading ||
      _downloads[download.itemId] != download;

  Future<void> _download(Download download) async {
    final playback = api;
    if (playback == null) {
      _fail(download, DownloadProblem.signedOut);
      return;
    }
    download
      ..state = DownloadState.downloading
      ..problem = null;
    _notify();
    try {
      var grant = await _currentGrant(download);
      if (_stopped(download)) return;
      var files = download.files;
      if (files == null) {
        final bytes = await _fetch(
          playback,
          download,
          download.quality.path,
          grant,
        );
        files = parseMediaPlaylist(utf8.decode(bytes)).files;
        await storage.write(download.itemId, download.quality.path, bytes);
        download.files = files;
        await _save();
      }
      // What is already here, whole: from before a pause or a restart.
      final missing = <String>[];
      var done = 0;
      var bytes = 0;
      for (final name in files) {
        final size = await storage.sizeOf(
          download.itemId,
          '${download.folder}/$name',
        );
        if (size == null) {
          missing.add(name);
        } else {
          done++;
          bytes += size;
        }
      }
      download
        ..doneFiles = done
        ..bytes = bytes;
      _notify();

      var next = 0;
      var sinceSave = 0;
      // The first file to fail stops the others.
      var failed = false;
      Future<void> fetchFiles() async {
        while (!failed && !_stopped(download) && next < missing.length) {
          final name = missing[next++];
          final path = '${download.folder}/$name';
          grant = await _currentGrant(download);
          final data = await _fetch(playback, download, path, grant);
          if (_stopped(download)) return;
          await storage.write(download.itemId, path, data);
          download
            ..doneFiles += 1
            ..bytes += data.length;
          _attempt = 0;
          _notify();
          if (++sinceSave >= 20) {
            sinceSave = 0;
            unawaited(_save());
          }
        }
      }

      Future<void> worker() async {
        try {
          await fetchFiles();
        } on Object {
          failed = true;
          rethrow;
        }
      }

      await Future.wait([for (var i = 0; i < parallel; i++) worker()]);
      if (_stopped(download)) {
        await _save();
        return;
      }
      download
        ..state = DownloadState.done
        ..problem = null;
      _notify();
      await _save();
    } on PlaybackException catch (error) {
      if (_stopped(download)) return;
      switch (error.failure) {
        case PlaybackFailure.unreachable ||
            PlaybackFailure.busy ||
            PlaybackFailure.tooMany:
          _wait(download);
        case PlaybackFailure.needsPass:
          _fail(download, DownloadProblem.noPass);
        case PlaybackFailure.deviceLimit || PlaybackFailure.deviceSwitchLimit:
          _fail(download, DownloadProblem.deviceLimit);
        case PlaybackFailure.signedOut || PlaybackFailure.refused:
          _fail(download, DownloadProblem.signedOut);
        case PlaybackFailure.notFound:
          _takeDown(download);
          _notify();
          await _save();
        default:
          _fail(download, DownloadProblem.unexpected);
      }
    } on MediaFetchException catch (error) {
      if (_stopped(download)) return;
      if (error.status == 404) {
        // The video was replaced since the download started: start again.
        await storage.delete(download.itemId).catchError((Object _) {});
        download
          ..files = null
          ..doneFiles = 0
          ..bytes = 0;
        _fail(download, DownloadProblem.unexpected);
      } else {
        _wait(download);
      }
    } on DownloadStorageFull {
      if (_stopped(download)) return;
      _fail(download, DownloadProblem.storageFull);
    } on FormatException {
      if (_stopped(download)) return;
      _fail(download, DownloadProblem.unexpected);
    } on Object {
      if (_stopped(download)) return;
      _fail(download, DownloadProblem.unexpected);
    }
  }

  /// One file, tried again a little after a dropped connection, and with a
  /// fresh grant once if the gateway refuses the one held.
  Future<Uint8List> _fetch(
    PlaybackApi playback,
    Download download,
    String path,
    PlaybackGrant grant,
  ) async {
    var renewed = false;
    for (var attempt = 0; ; attempt++) {
      try {
        return await playback.fetchMedia(grant.playlistUrl.resolve(path));
      } on MediaFetchException catch (error) {
        if (_stopped(download)) rethrow;
        if (error.refused && !renewed) {
          renewed = true;
          grant = await _currentGrant(download, replacing: grant);
          continue;
        }
        final status = error.status;
        final transient = status == null || status >= 500 || status == 429;
        if (!transient || attempt >= fileRetries) rethrow;
        await Future<void>.delayed(fileRetryDelay);
      }
    }
  }

  /// A grant for [download] with time left on it. One request at a time,
  /// shared by every file being fetched. With [replacing], the gateway
  /// refused that grant, so a new one is asked for unless another file has
  /// already done so.
  Future<PlaybackGrant> _currentGrant(
    Download download, {
    PlaybackGrant? replacing,
  }) async {
    final held = _grant;
    final fresh =
        held != null &&
        _grantItem == download.itemId &&
        !identical(held, replacing) &&
        clock().isBefore(held.expiresAt.subtract(grantMargin));
    if (fresh) return held;
    return _granting ??= () async {
      try {
        final playback = api!;
        final answer = await playback.downloadGrant(download.itemId);
        _grant = answer.grant;
        _grantItem = download.itemId;
        download
          ..offlineUntil = answer.offlineUntil
          ..licenceCheckedAt = clock().toUtc();
        return answer.grant;
      } finally {
        _granting = null;
      }
    }();
  }

  void _fail(Download download, DownloadProblem problem) {
    download
      ..state = DownloadState.failed
      ..problem = problem;
    _notify();
    unawaited(_save());
  }

  /// The connection dropped: try again by itself, later each time.
  void _wait(Download download) {
    download.state = DownloadState.waiting;
    _notify();
    unawaited(_save());
    _retry?.cancel();
    _retry = Timer(retryAfter(_attempt++), () {
      for (final d in _downloads.values) {
        if (d.state == DownloadState.waiting) d.state = DownloadState.queued;
      }
      _notify();
      _pump();
    });
  }

  // --- Keeping the index ---------------------------------------------------------

  /// Writes the index. One write at a time: a save asked for while one is
  /// being written is written straight after, newest only.
  Future<void> _save() async {
    _unsaved = jsonEncode({
      'version': 1,
      'latest_seen': _latestSeen?.toIso8601String(),
      'downloads': [for (final d in _downloads.values) d.toJson()],
    });
    if (_writing) return;
    _writing = true;
    try {
      for (var text = _unsaved; text != null; text = _unsaved) {
        _unsaved = null;
        try {
          await storage.writeIndex(text);
        } on Object {
          // Kept in memory; written with the next change.
        }
      }
    } finally {
      _writing = false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    super.dispose();
  }
}

/// Gives the screens below it downloads. Null on the web, and until the
/// app's storage has been found.
class DownloadsScope extends InheritedNotifier<DownloadManager> {
  const DownloadsScope({
    super.key,
    required DownloadManager? manager,
    required super.child,
  }) : super(notifier: manager);

  /// The manager, rebuilding the caller whenever a download changes.
  static DownloadManager? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DownloadsScope>()?.notifier;

  /// The manager, without rebuilding the caller as downloads change: for
  /// deciding whether downloads are offered at all.
  static DownloadManager? peek(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DownloadsScope>()?.notifier;
}

int? _int(Object? value) => value is int ? value : null;

String? _string(Object? value) => value is String ? value : null;
