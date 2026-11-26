/// The admin screens' video uploads: a queue that makes each file's draft,
/// uploads it with tus, and carries on after anything that stops it.
///
/// - Two files upload at a time. The rest wait their turn.
/// - Pause stops sending, and keeps the upload's place on the server.
/// - A network failure retries by itself, after 1, 3, 5, 10, 20 and 30
///   seconds, then every minute, and at once when the browser is back online.
/// - Each upload is kept in the browser's storage. After a reload, a closed
///   tab or a power cut, it is listed again. The file is found again from a
///   kept file handle, with one click in Chrome and Edge, or by dropping the
///   same file again. Either way it carries on from the server's offset.
/// - Remove stops it, and deletes the part uploaded from the server.
/// - Pause all, Resume all and Remove all do the same to every upload.
/// - A file can also be added to a draft made already, by New draft.
///
/// Upload keys are kept in memory only, until tusd has used one. An upload
/// that lost its key before starting gets a new one from the API.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../api/admin_api.dart';
import '../../api/catalogue_api.dart' show EditionKind;
import 'file_names.dart';
import 'tus.dart';

/// The label on keys the upload screen makes.
const String browserUploadKeyLabel = 'Browser upload';

const List<Duration> uploadRetryDelays = [
  Duration(seconds: 1),
  Duration(seconds: 3),
  Duration(seconds: 5),
  Duration(seconds: 10),
  Duration(seconds: 20),
  Duration(seconds: 30),
  Duration(minutes: 1),
];

/// A file picked or dropped, with its file handle in Chrome and Edge, which
/// lets it be opened again after a reload.
class PickedVideo {
  const PickedVideo(this.file, {this.handle});

  final LocalVideoFile file;
  final Object? handle;
}

/// Where uploads are kept between visits. The web keeps them in IndexedDB.
abstract class UploadStore {
  Future<List<StoredUpload>> load();

  /// Saves [record]. A [handle] given is kept with it; one given before is
  /// kept when none is given.
  Future<void> save(String id, Map<String, Object?> record, {Object? handle});

  Future<void> delete(String id);

  /// The file again, from its kept handle, asking the browser for access if
  /// needed. Null without a handle, or when access is refused.
  Future<LocalVideoFile?> reopen(String id);
}

class StoredUpload {
  const StoredUpload(this.record, {this.canReopen = false});

  final Map<String, Object?> record;
  final bool canReopen;
}

/// Kept in memory only: for tests, and builds without browser storage.
class MemoryUploadStore implements UploadStore {
  final Map<String, Map<String, Object?>> records = {};
  final Map<String, Object> handles = {};

  /// What [reopen] gives, by ID, in tests.
  final Map<String, LocalVideoFile> reopenable = {};

  @override
  Future<List<StoredUpload>> load() async => [
    for (final MapEntry(:key, :value) in records.entries)
      StoredUpload(Map.of(value), canReopen: handles.containsKey(key)),
  ];

  @override
  Future<void> save(
    String id,
    Map<String, Object?> record, {
    Object? handle,
  }) async {
    records[id] = Map.of(record);
    if (handle != null) handles[id] = handle;
  }

  @override
  Future<void> delete(String id) async {
    records.remove(id);
    handles.remove(id);
  }

  @override
  Future<LocalVideoFile?> reopen(String id) async =>
      handles.containsKey(id) ? reopenable[id] : null;
}

/// Whether the browser thinks it is online, and when that changes.
abstract class NetworkStatus {
  bool get online;
  Stream<bool> get changes;
}

class AlwaysOnline implements NetworkStatus {
  const AlwaysOnline();

  @override
  bool get online => true;

  @override
  Stream<bool> get changes => const Stream.empty();
}

/// What a row in the review list becomes: the draft to make, or the series
/// to add an episode to.
@immutable
class UploadPlan {
  const UploadPlan({
    required this.kind,
    required this.title,
    this.year,
    this.language,
    this.season,
    this.episode,
    this.vjId,
    this.vjName,
    this.seriesEditionId,
    this.seriesTitle,
  });

  final EditionKind kind;
  final String title;
  final int? year;

  /// A language code. The API's default, Luganda, when null.
  final String? language;
  final int? season;
  final int? episode;

  /// A known VJ, credited when the draft is made. Choosing them in the
  /// review list, and pressing Start, is the admin's confirmation.
  final String? vjId;
  final String? vjName;

  /// For an episode of a series that already exists.
  final String? seriesEditionId;
  final String? seriesTitle;

  /// Episodes of one new series dropped together share a draft: the first
  /// to start makes it, and the others are added to it.
  String get group => kind == EditionKind.series && seriesEditionId == null
      ? 'new:${titleKey(title)}:${vjId ?? ''}:${language ?? ''}'
      : '';

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'title': title,
    'year': year,
    'language': language,
    'season': season,
    'episode': episode,
    'vj_id': vjId,
    'vj_name': vjName,
    'series_edition_id': seriesEditionId,
    'series_title': seriesTitle,
  };

  static UploadPlan fromJson(Map<String, Object?> json) => UploadPlan(
    kind: json['kind'] == 'series' ? EditionKind.series : EditionKind.movie,
    title: json['title'] as String? ?? '',
    year: json['year'] as int?,
    language: json['language'] as String?,
    season: json['season'] as int?,
    episode: json['episode'] as int?,
    vjId: json['vj_id'] as String?,
    vjName: json['vj_name'] as String?,
    seriesEditionId: json['series_edition_id'] as String?,
    seriesTitle: json['series_title'] as String?,
  );
}

enum UploadPhase {
  /// Listed again after a reload: needs its file before it can carry on.
  needsFile,
  queued,

  /// Making the draft, the key or the upload on the server.
  preparing,
  uploading,
  paused,

  /// Waiting to try again after a failure.
  retrying,

  /// Waiting for the browser to be back online.
  offline,
  finished,
  failed,
  removing,
}

enum UploadProblem {
  /// The upload key was refused twice.
  keyRefused,
  tooLarge,

  /// The API refused the draft or key: see [UploadTask.adminError].
  refused,

  /// The file dropped or reopened isn't the one that was uploading.
  fileChanged,

  /// The browser didn't give the file back.
  fileUnreadable,

  /// Remove couldn't reach the server. Remove again to retry.
  removeFailed,
  unexpected,
}

class UploadTask {
  UploadTask._({
    required this.id,
    required this.plan,
    required this.fileName,
    required this.size,
    required this.lastModified,
    this.file,
    this.canReopen = false,
    this.phase = UploadPhase.queued,
  });

  final String id;
  final UploadPlan plan;
  final String fileName;
  final int size;
  final int lastModified;

  LocalVideoFile? file;

  /// A file handle is kept, so the file can be opened again with one click.
  bool canReopen;
  UploadPhase phase;

  /// Set once the series exists: the plan's, or the one a sibling made.
  String? seriesEditionId;
  String? editionId;
  String? itemId;
  Uri? uploadUrl;

  /// Bytes the server has, as far as this screen knows.
  int sent = 0;

  /// Bytes a second, over the last few seconds, while uploading.
  double? speed;
  DateTime? retryAt;
  UploadProblem? problem;
  AdminException? adminError;

  /// Crediting the VJ failed, though the draft was made and uploads.
  AdminException? creditError;

  /// The server had lost the upload, so it started again from the start.
  bool restarted = false;

  /// Paused when the page was left, so it stays paused once its file is back.
  bool _wasPaused = false;
  String? _key;
  TusCancel? _cancel;
  Timer? _timer;
  Future<void>? _running;
  int _attempt = 0;
  int _keyRefusals = 0;
  int _gone = 0;
  final List<(DateTime, int)> _samples = [];

  double get fraction => size == 0 ? 0 : math.min(1, sent / size);

  /// A whole percentage, never 100 until the server has every byte.
  int get percent {
    final value = (fraction * 100).floor();
    return phase == UploadPhase.finished ? 100 : math.min(value, 99);
  }

  /// Time left at the current speed.
  Duration? get timeLeft {
    final rate = speed;
    if (rate == null || rate <= 0 || phase != UploadPhase.uploading) {
      return null;
    }
    return Duration(seconds: ((size - sent) / rate).ceil());
  }

  bool get active => const {
    UploadPhase.queued,
    UploadPhase.preparing,
    UploadPhase.uploading,
    UploadPhase.retrying,
    UploadPhase.offline,
  }.contains(phase);

  bool sameFile(LocalVideoFile other) =>
      other.name == fileName &&
      other.size == size &&
      other.lastModified == lastModified;

  Map<String, Object?> toRecord() => {
    'v': 1,
    'id': id,
    'name': fileName,
    'size': size,
    'modified': lastModified,
    'plan': plan.toJson(),
    'series_edition_id': seriesEditionId,
    'edition_id': editionId,
    'item_id': itemId,
    'upload_url': uploadUrl?.toString(),
    'sent': sent,
    'paused': phase == UploadPhase.paused,
    'restarted': restarted,
  };

  static UploadTask? fromRecord(
    Map<String, Object?> json, {
    bool canReopen = false,
  }) {
    try {
      final url = json['upload_url'] as String?;
      return UploadTask._(
          id: json['id']! as String,
          plan: UploadPlan.fromJson(json['plan']! as Map<String, Object?>),
          fileName: json['name']! as String,
          size: json['size']! as int,
          lastModified: json['modified']! as int,
          canReopen: canReopen,
          phase: UploadPhase.needsFile,
        )
        ..seriesEditionId = json['series_edition_id'] as String?
        ..editionId = json['edition_id'] as String?
        ..itemId = json['item_id'] as String?
        ..uploadUrl = url == null ? null : Uri.parse(url)
        ..sent = json['sent'] as int? ?? 0
        .._wasPaused = json['paused'] == true
        ..restarted = json['restarted'] == true;
    } on Object {
      // A record from another version, or damaged: left out.
      return null;
    }
  }
}

class UploadQueue extends ChangeNotifier {
  UploadQueue({
    required this.api,
    required this.tus,
    required this.endpoint,
    required this.store,
    this.network = const AlwaysOnline(),
    this.maxParallel = 2,
    this.chunkBytes = tusChunkBytes,
    this.onBusyChanged,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _online = network.changes.listen(_onlineChanged);
  }

  final AdminApi api;
  final TusClient tus;

  /// tusd's base address, from UPLOAD_BASE_URL.
  final Uri endpoint;
  final UploadStore store;
  final NetworkStatus network;
  final int maxParallel;
  final int chunkBytes;

  /// Told when uploads start or stop running, to warn before leaving the page.
  final void Function(bool busy)? onBusyChanged;
  final DateTime Function() _now;

  final List<UploadTask> _tasks = [];
  final Map<String, Future<void>> _groupLocks = {};
  late final StreamSubscription<bool> _online;
  Future<void>? _restoring;
  int _running = 0;
  int _ids = 0;
  bool _busy = false;
  bool _disposed = false;

  List<UploadTask> get tasks => List.unmodifiable(_tasks);

  /// Something is uploading or waiting to.
  bool get busy => _tasks.any((t) => t.active);

  /// Lists the uploads kept from before, each waiting for its file. Once
  /// only.
  Future<void> restore() => _restoring ??= () async {
    final List<StoredUpload> stored;
    try {
      stored = await store.load();
    } on Object {
      return;
    }
    for (final entry in stored) {
      final task = UploadTask.fromRecord(
        entry.record,
        canReopen: entry.canReopen,
      );
      if (task == null || _tasks.any((t) => t.id == task.id)) continue;
      _tasks.add(task);
    }
    _changed();
  }();

  /// Queues new uploads, in order.
  Future<void> add(List<(PickedVideo, UploadPlan)> uploads) async {
    for (final (picked, plan) in uploads) {
      final task = UploadTask._(
        id: '${_now().microsecondsSinceEpoch}-${_ids++}',
        plan: plan,
        fileName: picked.file.name,
        size: picked.file.size,
        lastModified: picked.file.lastModified,
        file: picked.file,
        canReopen: picked.handle != null,
      )..seriesEditionId = plan.seriesEditionId;
      if (task.size > maxVideoBytes) {
        task
          ..phase = UploadPhase.failed
          ..problem = UploadProblem.tooLarge;
      }
      _tasks.add(task);
      await _persist(task, handle: picked.handle);
    }
    _pump();
  }

  /// Queues a file for a draft made already, such as by New draft: no new
  /// draft is made. [key] is the upload key the draft came with, if unused.
  Future<void> addToItem(
    PickedVideo picked,
    UploadPlan plan, {
    required String editionId,
    required String itemId,
    String? key,
  }) async {
    final task =
        UploadTask._(
            id: '${_now().microsecondsSinceEpoch}-${_ids++}',
            plan: plan,
            fileName: picked.file.name,
            size: picked.file.size,
            lastModified: picked.file.lastModified,
            file: picked.file,
            canReopen: picked.handle != null,
          )
          ..editionId = editionId
          ..itemId = itemId
          ..seriesEditionId = plan.seriesEditionId
          .._key = key;
    if (task.size > maxVideoBytes) {
      task
        ..phase = UploadPhase.failed
        ..problem = UploadProblem.tooLarge;
    }
    _tasks.add(task);
    await _persist(task, handle: picked.handle);
    _pump();
  }

  /// Gives files back to uploads listed after a reload, matched by name,
  /// size and date. Returns the files that matched none.
  Future<List<PickedVideo>> attach(List<PickedVideo> picked) async {
    final unmatched = <PickedVideo>[];
    for (final video in picked) {
      final task = _tasks
          .where(
            (t) =>
                t.file == null &&
                t.phase != UploadPhase.finished &&
                t.sameFile(video.file),
          )
          .firstOrNull;
      if (task == null) {
        unmatched.add(video);
        continue;
      }
      task
        ..file = video.file
        ..problem = null
        ..phase = task._wasPaused ? UploadPhase.paused : UploadPhase.queued;
      if (video.handle != null) task.canReopen = true;
      await _persist(task, handle: video.handle);
    }
    _pump();
    return unmatched;
  }

  void pause(String id) {
    final task = _find(id);
    if (task == null || !task.active) return;
    task
      ..phase = UploadPhase.paused
      ..speed = null
      ..retryAt = null;
    task._timer?.cancel();
    task._cancel?.cancel();
    unawaited(_persist(task));
    _changed();
  }

  /// Carries on a paused, failed or waiting upload, at once. One listed
  /// after a reload opens its file again from its kept handle.
  Future<void> resume(String id) async {
    final task = _find(id);
    if (task == null) return;
    if (task.file == null) {
      if (!task.canReopen) return;
      final LocalVideoFile? file;
      try {
        file = await store.reopen(id);
      } on Object {
        task.problem = UploadProblem.fileUnreadable;
        _changed();
        return;
      }
      if (file == null) {
        task.problem = UploadProblem.fileUnreadable;
        _changed();
        return;
      }
      if (!task.sameFile(file)) {
        task.problem = UploadProblem.fileChanged;
        _changed();
        return;
      }
      task.file = file;
    }
    if (!const {
      UploadPhase.paused,
      UploadPhase.failed,
      UploadPhase.retrying,
      UploadPhase.offline,
      UploadPhase.needsFile,
    }.contains(task.phase)) {
      return;
    }
    if (task.phase == UploadPhase.failed &&
        task.problem == UploadProblem.removeFailed) {
      return remove(id);
    }
    task._timer?.cancel();
    if (task.problem == UploadProblem.keyRefused) task._keyRefusals = 0;
    task
      ..phase = UploadPhase.queued
      ..problem = null
      ..adminError = null
      ..retryAt = null
      .._wasPaused = false
      .._attempt = 0;
    await _persist(task);
    _pump();
  }

  /// Stops an upload and deletes what it uploaded from the server. Its
  /// draft stays in Drafts.
  Future<void> remove(String id) async {
    final task = _find(id);
    if (task == null) return;
    task
      ..phase = UploadPhase.removing
      ..problem = null;
    task._timer?.cancel();
    task._cancel?.cancel();
    _changed();
    await task._running;
    final url = task.uploadUrl;
    if (url != null && task.sent < task.size) {
      try {
        await tus.terminate(url);
      } on TusNotRemovable {
        // It finished just now: it is the draft's video, and stays.
      } on TusException {
        task
          ..phase = UploadPhase.failed
          ..problem = UploadProblem.removeFailed;
        _changed();
        return;
      }
    }
    try {
      await store.delete(id);
    } on Object {
      // Listed again after a reload at worst, and removable then.
    }
    _tasks.remove(task);
    _changed();
  }

  /// Something Pause all would pause.
  bool get canPauseAll => _tasks.any((t) => t.active);

  /// Something Resume all would carry on.
  bool get canResumeAll => _tasks.any(_resumable);

  /// Something Remove all would remove.
  bool get canRemoveAll => _tasks.any((t) => t.phase != UploadPhase.removing);

  bool _resumable(UploadTask t) => switch (t.phase) {
    UploadPhase.paused || UploadPhase.retrying || UploadPhase.offline => true,
    UploadPhase.needsFile => t.canReopen,
    UploadPhase.failed =>
      t.problem != UploadProblem.tooLarge &&
          t.problem != UploadProblem.removeFailed,
    _ => false,
  };

  /// Pauses every upload that is running or waiting to.
  void pauseAll() {
    for (final task in List.of(_tasks)) {
      if (task.active) pause(task.id);
    }
  }

  /// Carries on every paused, failed or waiting upload. Two run at a time;
  /// the rest wait their turn.
  Future<void> resumeAll() async {
    for (final task in List.of(_tasks)) {
      if (_resumable(task)) await resume(task.id);
    }
  }

  /// Removes every upload, deleting what each sent from the server, and
  /// clears the finished ones from the list. Their drafts stay.
  Future<void> removeAll() async {
    clearFinished();
    await Future.wait([
      for (final task in List.of(_tasks))
        if (task.phase != UploadPhase.removing) remove(task.id),
    ]);
  }

  /// Removes the uploads for an edition, as it is deleted.
  /// Removes the uploads for an edition, as it is deleted: its own, and
  /// episodes of the same new series still waiting to learn its ID, which
  /// would otherwise make the series again.
  Future<void> removeForEdition(String editionId) async {
    bool ofIt(UploadTask t) =>
        t.editionId == editionId || t.seriesEditionId == editionId;
    final groups = {
      for (final t in _tasks)
        if (ofIt(t) && t.plan.group.isNotEmpty) t.plan.group,
    };
    bool doomed(UploadTask t) =>
        ofIt(t) ||
        (t.editionId == null &&
            t.seriesEditionId == null &&
            groups.contains(t.plan.group));
    _tasks.removeWhere((t) => t.phase == UploadPhase.finished && doomed(t));
    await Future.wait([
      for (final task in List.of(_tasks))
        if (doomed(task)) remove(task.id),
    ]);
    _changed();
  }

  void clearFinished() {
    _tasks.removeWhere((t) => t.phase == UploadPhase.finished);
    _changed();
  }

  UploadTask? _find(String id) => _tasks.where((t) => t.id == id).firstOrNull;

  void _pump() {
    while (_running < maxParallel) {
      final next = _tasks
          .where((t) => t.phase == UploadPhase.queued)
          .firstOrNull;
      if (next == null) break;
      _running++;
      next.phase = UploadPhase.preparing;
      next._running = _run(next).whenComplete(() {
        _running--;
        next._running = null;
        if (!_disposed) _pump();
      });
    }
    _changed();
  }

  bool _stopped(UploadTask task) =>
      task.phase == UploadPhase.paused || task.phase == UploadPhase.removing;

  Future<void> _run(UploadTask task) async {
    final cancel = task._cancel = TusCancel();
    try {
      final file = task.file;
      if (file == null) {
        task.phase = UploadPhase.needsFile;
        return;
      }
      final fresh = await _prepare(task, file, cancel);
      if (cancel.isCancelled) return;
      task
        ..phase = UploadPhase.uploading
        ..retryAt = null;
      task._samples.clear();
      final url = task.uploadUrl!;
      var offset = fresh ? 0 : await tus.offset(url, cancel: cancel);
      task.sent = offset;
      _sample(task);
      _changed();
      while (offset < task.size) {
        final from = offset;
        final to = math.min(from + chunkBytes, task.size);
        offset = await tus.patch(
          url,
          file,
          from: from,
          to: to,
          cancel: cancel,
          onProgress: (sent) {
            if (cancel.isCancelled) return;
            task.sent = math.min(from + sent, task.size);
            _sample(task);
            _changed();
          },
        );
        task
          ..sent = offset
          .._attempt = 0;
        _sample(task);
        await _persist(task);
        _changed();
      }
      if (cancel.isCancelled) return;
      task
        ..phase = UploadPhase.finished
        ..sent = task.size
        ..speed = null;
      await _forget(task);
    } on TusCancelled {
      // Paused or removed: they set the phase.
    } on TusGone {
      if (_stopped(task)) return;
      // The server lost the upload: start again with a new key.
      task
        ..uploadUrl = null
        ..sent = 0
        ..restarted = true
        .._gone += 1;
      await _persist(task);
      if (task._gone > 2) {
        _fail(task, UploadProblem.unexpected);
      } else {
        task.phase = UploadPhase.queued;
      }
    } on TusKeyRefused {
      if (_stopped(task)) return;
      task._key = null;
      if (++task._keyRefusals > 1) {
        _fail(task, UploadProblem.keyRefused);
      } else {
        task.phase = UploadPhase.queued;
      }
    } on TusTooLarge {
      if (!_stopped(task)) _fail(task, UploadProblem.tooLarge);
    } on TusException {
      if (!_stopped(task)) _retryLater(task);
    } on AdminException catch (error) {
      if (_stopped(task)) return;
      if (error.failure == AdminFailure.unreachable ||
          error.failure == AdminFailure.busy) {
        _retryLater(task);
      } else {
        _fail(task, UploadProblem.refused, error);
      }
    } on Object catch (error) {
      if (kDebugMode) debugPrint('upload failed: $error');
      if (!_stopped(task)) _fail(task, UploadProblem.unexpected);
    } finally {
      if (identical(task._cancel, cancel)) task._cancel = null;
      _changed();
    }
  }

  /// Makes the draft and the upload on the server, as far as not done
  /// before. True when the upload was just made, so has nothing yet.
  Future<bool> _prepare(
    UploadTask task,
    LocalVideoFile file,
    TusCancel cancel,
  ) async {
    if (task.itemId == null) {
      await _inGroup(task.plan.group, () async {
        final plan = task.plan;
        if (plan.kind == EditionKind.series && task.seriesEditionId == null) {
          task.seriesEditionId = _tasks
              .where(
                (t) =>
                    t != task &&
                    t.plan.group == plan.group &&
                    t.editionId != null,
              )
              .firstOrNull
              ?.editionId;
        }
        final series = task.seriesEditionId;
        final made = await api.createDraft(
          kind: plan.kind,
          title: series == null ? plan.title : null,
          year: series == null ? plan.year : null,
          language: series == null ? plan.language : null,
          seriesEditionId: series,
          season: plan.season,
          episode: plan.episode,
        );
        task
          ..itemId = made.itemId
          ..editionId = made.editionId
          .._key = made.uploadKey;
        await _persist(task);
        if (series == null && plan.vjId != null && made.editionId != null) {
          try {
            await api.setCredit(made.editionId!, vjId: plan.vjId);
          } on AdminException catch (error) {
            task.creditError = error;
          }
        }
      });
    }
    if (cancel.isCancelled) throw const TusCancelled();
    if (task.uploadUrl != null) return false;
    final key =
        task._key ??
        (await api.newKey(
          task.itemId!,
          label: browserUploadKeyLabel,
        )).uploadKey;
    task._key = key;
    if (cancel.isCancelled) throw const TusCancelled();
    task.phase = UploadPhase.preparing;
    final url = await tus.create(
      endpoint: endpoint,
      file: file,
      key: key,
      cancel: cancel,
    );
    task
      ..uploadUrl = url
      .._key = null;
    await _persist(task);
    return true;
  }

  /// Runs [body] for one group at a time, so the first episode of a new
  /// series makes it before the next is added to it.
  Future<void> _inGroup(String group, Future<void> Function() body) async {
    if (group.isEmpty) return body();
    final before = _groupLocks[group];
    final done = Completer<void>();
    _groupLocks[group] = done.future;
    try {
      if (before != null) await before;
      await body();
    } finally {
      done.complete();
      if (identical(_groupLocks[group], done.future)) _groupLocks.remove(group);
    }
  }

  void _retryLater(UploadTask task) {
    final delay =
        uploadRetryDelays[math.min(
          task._attempt,
          uploadRetryDelays.length - 1,
        )];
    task
      .._attempt += 1
      ..speed = null
      ..phase = network.online ? UploadPhase.retrying : UploadPhase.offline
      ..retryAt = _now().add(delay);
    // Keeps how far it got, to show after a reload.
    unawaited(_persist(task));
    task._timer?.cancel();
    task._timer = Timer(delay, () {
      if (task.phase == UploadPhase.retrying ||
          task.phase == UploadPhase.offline) {
        task
          ..phase = UploadPhase.queued
          ..retryAt = null;
        _pump();
      }
    });
  }

  void _onlineChanged(bool online) {
    for (final task in _tasks) {
      if (online &&
          (task.phase == UploadPhase.offline ||
              task.phase == UploadPhase.retrying)) {
        task._timer?.cancel();
        task
          ..phase = UploadPhase.queued
          ..retryAt = null;
      } else if (!online && task.phase == UploadPhase.retrying) {
        task.phase = UploadPhase.offline;
      }
    }
    _pump();
  }

  void _fail(UploadTask task, UploadProblem problem, [AdminException? error]) {
    task
      ..phase = UploadPhase.failed
      ..problem = problem
      ..adminError = error
      ..speed = null
      ..retryAt = null;
  }

  void _sample(UploadTask task) {
    final now = _now();
    final samples = task._samples..add((now, task.sent));
    while (samples.length > 2 &&
        now.difference(samples.first.$1) > const Duration(seconds: 10)) {
      samples.removeAt(0);
    }
    final (start, bytes) = samples.first;
    final seconds = now.difference(start).inMilliseconds / 1000;
    if (seconds >= 1) task.speed = (task.sent - bytes) / seconds;
  }

  Future<void> _persist(UploadTask task, {Object? handle}) async {
    if (task.phase == UploadPhase.finished ||
        task.phase == UploadPhase.removing) {
      return;
    }
    try {
      await store.save(task.id, task.toRecord(), handle: handle);
    } on Object {
      // Storage full or blocked: the upload carries on, but won't be listed
      // after a reload.
    }
  }

  Future<void> _forget(UploadTask task) async {
    try {
      await store.delete(task.id);
    } on Object {
      // Listed again after a reload, and removed then once it is finished.
    }
  }

  void _changed() {
    if (_disposed) return;
    final busy = this.busy;
    if (busy != _busy) {
      _busy = busy;
      onBusyChanged?.call(busy);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _online.cancel();
    for (final task in _tasks) {
      task._timer?.cancel();
      task._cancel?.cancel();
    }
    onBusyChanged?.call(false);
    super.dispose();
  }
}
