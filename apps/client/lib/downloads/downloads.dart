import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../api/playback_api.dart';

/// Downloads, Step 12A: a movie's or an episode's video as one .mp4 file,
/// saved where the viewer keeps their own files and theirs to keep.
///
/// - In a browser, the browser's own downloader saves it to the computer's
///   Downloads folder, as any download.
/// - On Android, Android's own download manager saves it to the phone's
///   Downloads/VeloraUG folder, with a notification, in the background, and
///   carrying on after a dropped connection. The Downloads tab follows its
///   progress and opens it in the phone's video player.
///
/// The API checks the pass and the device when the download starts. Once
/// downloaded, the file is the viewer's: nothing checks it again. See
/// docs/step-12a-downloads.md.

/// What a download is of, shown in the Downloads tab.
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

/// One quality's file, offered for download.
class DownloadFile {
  const DownloadFile({
    required this.quality,
    required this.url,
    required this.fileName,
    this.bytes,
  });

  final VideoQuality quality;

  /// On the media gateway, with the grant, asking for [fileName].
  final Uri url;

  /// Such as "Fast X - VJ Junior - 720p.mp4".
  final String fileName;

  /// Its size, when the gateway said.
  final int? bytes;
}

/// What can be downloaded of one item: each quality's file, highest first.
class DownloadOffer {
  const DownloadOffer({required this.itemId, required this.files});

  final String itemId;
  final List<DownloadFile> files;
}

/// Where a download on the phone has got to, as Android says.
enum FileState { waiting, running, paused, done, failed }

/// Android's answer about one download.
class FileStatus {
  const FileStatus({
    required this.state,
    this.bytes = 0,
    this.total,
    this.noRoom = false,
  });

  final FileState state;
  final int bytes;

  /// The whole file's size, once known.
  final int? total;

  /// Failed because the phone is full.
  final bool noRoom;

  /// Not found: removed outside the app, in Android's Downloads app.
  static const FileStatus gone = FileStatus(state: FileState.failed);
}

/// Where downloads go: the browser, or Android's download manager.
abstract interface class DownloadTarget {
  /// Whether downloads are followed in the app: on Android. A browser
  /// follows its own.
  bool get followed;

  /// Starts saving [file]. Answers its ID with the target, if followed.
  /// Throws [DownloadRefused] if it can't start.
  Future<String?> start(DownloadFile file, String title);

  /// The status of each ID asked about. An ID left out is gone.
  Future<Map<String, FileStatus>> status(List<String> ids);

  /// Opens a finished file in the phone's video player. False if nothing
  /// can open it, or it was deleted outside the app.
  Future<bool> open(String id);

  /// Stops it if running, and deletes its file.
  Future<void> remove(String id);
}

/// Why a download couldn't start on the phone.
enum DownloadRefusal {
  /// Android 9 or older: the viewer didn't allow saving to storage.
  noPermission,

  /// Anything else.
  failed,
}

class DownloadRefused implements Exception {
  const DownloadRefused(this.reason);

  final DownloadRefusal reason;
}

/// Where the list of followed downloads is kept between launches.
abstract interface class DownloadRecords {
  Future<String?> read();
  Future<void> write(String text);
}

class MemoryDownloadRecords implements DownloadRecords {
  MemoryDownloadRecords([this.text]);

  String? text;

  @override
  Future<String?> read() async => text;

  @override
  Future<void> write(String text) async => this.text = text;
}

/// One download followed on the phone.
class Download {
  Download({
    required this.id,
    required this.itemId,
    required this.info,
    required this.quality,
    required this.fileName,
    required this.startedAt,
    this.status = const FileStatus(state: FileState.waiting),
  });

  /// Android's ID for it.
  final String id;
  final String itemId;
  final DownloadInfo info;

  /// Such as "720p".
  final String quality;
  final String fileName;
  final DateTime startedAt;
  FileStatus status;

  FileState get state => status.state;

  /// From 0 to 1, or null while the size isn't known.
  double? get progress {
    final total = status.total;
    if (total == null || total <= 0) return null;
    return (status.bytes / total).clamp(0, 1).toDouble();
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'item_id': itemId,
    'edition_id': info.editionId,
    'title': info.title,
    'label': info.label,
    'season': info.season,
    'episode': info.episode,
    'episode_title': info.episodeTitle,
    'quality': quality,
    'file_name': fileName,
    'started_at': startedAt.toUtc().toIso8601String(),
  };

  static Download? fromJson(Object? json) {
    if (json case {
      'id': final String id,
      'item_id': final String itemId,
      'edition_id': final String editionId,
      'title': final String title,
      'label': final String label,
      'quality': final String quality,
      'file_name': final String fileName,
      'started_at': final String started,
    }) {
      final at = DateTime.tryParse(started);
      if (at == null) return null;
      return Download(
        id: id,
        itemId: itemId,
        info: DownloadInfo(
          editionId: editionId,
          title: title,
          label: label,
          season: json['season'] is int ? json['season'] as int : null,
          episode: json['episode'] is int ? json['episode'] as int : null,
          episodeTitle: json['episode_title'] is String
              ? json['episode_title'] as String
              : null,
        ),
        quality: quality,
        fileName: fileName,
        startedAt: at.toUtc(),
      );
    }
    return null;
  }
}

/// Offers and starts downloads, and on Android follows them.
class Downloads extends ChangeNotifier {
  Downloads({
    required this.target,
    required this.api,
    DownloadRecords? records,
    this.clock = DateTime.now,
    this.checkEvery = const Duration(seconds: 1),
  }) : records = records ?? MemoryDownloadRecords();

  final DownloadTarget target;

  /// Null without playback in this build: nothing can be downloaded.
  final PlaybackApi? api;
  final DownloadRecords records;
  final DateTime Function() clock;

  /// How often Android is asked about running downloads.
  final Duration checkEvery;

  final List<Download> _downloads = [];
  Timer? _checking;
  bool _loaded = false;
  bool _disposed = false;

  bool get followed => target.followed;
  bool get loaded => _loaded;

  /// Newest first.
  List<Download> get downloads => List.unmodifiable(_downloads);

  /// The newest download of [itemId], if any.
  Download? latestOf(String itemId) {
    for (final download in _downloads) {
      if (download.itemId == itemId) return download;
    }
    return null;
  }

  /// Room the finished downloads take.
  int get usedBytes => _downloads
      .where((d) => d.state == FileState.done)
      .fold(0, (sum, d) => sum + (d.status.total ?? d.status.bytes));

  /// Reads the downloads followed before, and asks Android about them.
  Future<void> load() async {
    if (_loaded || !followed) {
      _loaded = true;
      return;
    }
    try {
      final text = await records.read();
      if (text != null) {
        final json = jsonDecode(text);
        if (json case {'downloads': final List<Object?> rows}) {
          for (final row in rows) {
            final download = Download.fromJson(row);
            if (download != null) _downloads.add(download);
          }
        }
      }
    } on Object {
      // A list that can't be read starts again; the files stay in Downloads.
    }
    _loaded = true;
    _notify();
    await refresh();
  }

  /// Each quality's file for [itemId], with its size. Throws
  /// [PlaybackException], as playback would be refused.
  Future<DownloadOffer> offer(String itemId) async {
    final playback = api;
    if (playback == null) {
      throw const PlaybackException(PlaybackFailure.unreachable);
    }
    final grant = await playback.downloadGrant(itemId);
    final qualities = await playback.qualities(grant.grant);
    if (qualities.isEmpty) {
      throw const PlaybackException(PlaybackFailure.unreachable);
    }
    final sized = await Future.wait([
      for (final quality in qualities) _sizeOf(playback, _file(grant, quality)),
    ]);
    final files = [for (final file in sized) ?file];
    if (files.isEmpty) {
      throw const PlaybackException(PlaybackFailure.notReady);
    }
    return DownloadOffer(itemId: itemId, files: files);
  }

  DownloadFile _file(DownloadGrant grant, VideoQuality quality) {
    final folder = quality.path.split('/').first;
    final name = '${grant.fileName} - ${quality.label}.mp4';
    final url = grant.grant.playlistUrl
        .resolve('$folder/download.mp4')
        .replace(queryParameters: {'name': name});
    return DownloadFile(quality: quality, url: url, fileName: name);
  }

  /// The file with its size, or null if the gateway hasn't got it: a film
  /// whose download files haven't been made yet.
  Future<DownloadFile?> _sizeOf(PlaybackApi playback, DownloadFile file) async {
    try {
      final response = await playback.httpClient
          .head(file.url)
          .timeout(playback.timeout);
      if (response.statusCode == 404) return null;
      final length = int.tryParse(response.headers['content-length'] ?? '');
      return DownloadFile(
        quality: file.quality,
        url: file.url,
        fileName: file.fileName,
        bytes: response.statusCode == 200 ? length : null,
      );
    } on Exception {
      return file;
    }
  }

  /// Starts saving [file]. On Android it is then followed here.
  Future<void> start(
    String itemId,
    DownloadFile file,
    DownloadInfo info,
  ) async {
    final title = info.isEpisode
        ? '${info.title} S${info.season} E${info.episode}'
        : info.title;
    final id = await target.start(file, title);
    if (id == null || !followed) return;
    _downloads.insert(
      0,
      Download(
        id: id,
        itemId: itemId,
        info: info,
        quality: file.quality.label,
        fileName: file.fileName,
        startedAt: clock().toUtc(),
      ),
    );
    _notify();
    await _save();
    _keepChecking();
  }

  /// Opens a finished download in the phone's video player.
  Future<bool> open(Download download) => target.open(download.id);

  /// Stops a download if running, and deletes its file.
  Future<void> remove(Download download) async {
    try {
      await target.remove(download.id);
    } on Object {
      // Already gone.
    }
    _downloads.remove(download);
    _notify();
    await _save();
  }

  /// Asks Android where each download has got to.
  Future<void> refresh() async {
    if (!followed || _downloads.isEmpty) return;
    Map<String, FileStatus> found;
    try {
      found = await target.status([for (final d in _downloads) d.id]);
    } on Object {
      return;
    }
    for (final download in _downloads) {
      download.status = found[download.id] ?? FileStatus.gone;
    }
    _notify();
    _keepChecking();
  }

  /// Checks again every [checkEvery] while anything is downloading.
  void _keepChecking() {
    final busy = _downloads.any(
      (d) =>
          d.state == FileState.waiting ||
          d.state == FileState.running ||
          d.state == FileState.paused,
    );
    if (!busy || _disposed) {
      _checking?.cancel();
      _checking = null;
      return;
    }
    _checking ??= Timer(checkEvery, () {
      _checking = null;
      refresh();
    });
  }

  Future<void> _save() async {
    try {
      await records.write(
        jsonEncode({
          'downloads': [for (final d in _downloads) d.toJson()],
        }),
      );
    } on Object {
      // Kept in memory; written with the next change.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _checking?.cancel();
    super.dispose();
  }
}

/// Gives the screens below it downloads. Null where this build can't save
/// files.
class DownloadsScope extends InheritedNotifier<Downloads> {
  const DownloadsScope({
    super.key,
    required Downloads? downloads,
    required super.child,
  }) : super(notifier: downloads);

  /// The downloads, rebuilding the caller as they change.
  static Downloads? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DownloadsScope>()?.notifier;

  /// The downloads, without rebuilding the caller as they change.
  static Downloads? peek(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DownloadsScope>()?.notifier;
}
