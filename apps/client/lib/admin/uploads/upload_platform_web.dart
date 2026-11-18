import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import 'file_names.dart';
import 'tus.dart';
import 'upload_queue.dart';

/// A request with no progress for this long is given up as offline and
/// tried again, so a connection that hangs without failing can't stall an
/// upload for ever.
const Duration _stalled = Duration(seconds: 60);

class _WebFile implements LocalVideoFile {
  _WebFile(this.file);

  final web.File file;

  @override
  String get name => file.name;

  @override
  int get size => file.size;

  @override
  int get lastModified => file.lastModified;
}

class _XhrTransport implements TusTransport {
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
  }) async {
    if (cancel?.isCancelled ?? false) throw const TusCancelled();
    final xhr = web.XMLHttpRequest();
    final done = Completer<TusReply>();
    Timer? watchdog;
    void fail(TusException error) {
      watchdog?.cancel();
      if (!done.isCompleted) done.completeError(error);
    }

    void kick() {
      watchdog?.cancel();
      watchdog = Timer(_stalled, () {
        fail(const TusOffline());
        xhr.abort();
      });
    }

    xhr.open(method, url.toString());
    headers.forEach((name, value) => xhr.setRequestHeader(name, value));
    xhr.upload.onprogress = ((web.ProgressEvent event) {
      kick();
      onProgress?.call(event.loaded);
    }).toJS;
    xhr.onprogress = ((web.ProgressEvent _) => kick()).toJS;
    xhr.onload = ((web.Event _) {
      watchdog?.cancel();
      if (done.isCompleted) return;
      done.complete(
        TusReply(
          xhr.status,
          _headersOf(xhr),
          method == 'HEAD' ? '' : xhr.responseText,
        ),
      );
    }).toJS;
    xhr.onerror = ((web.Event _) => fail(const TusOffline())).toJS;
    xhr.ontimeout = ((web.Event _) => fail(const TusOffline())).toJS;
    xhr.onabort = ((web.Event _) => fail(const TusCancelled())).toJS;
    final stop = cancel?.listen(() {
      fail(const TusCancelled());
      xhr.abort();
    });
    kick();
    try {
      if (file is _WebFile) {
        xhr.send(file.file.slice(start, end));
      } else {
        xhr.send();
      }
      return await done.future;
    } on TusException {
      rethrow;
    } on Object {
      throw const TusOffline();
    } finally {
      watchdog?.cancel();
      stop?.call();
    }
  }

  Map<String, String> _headersOf(web.XMLHttpRequest xhr) => {
    for (final line in xhr.getAllResponseHeaders().split(RegExp(r'\r?\n')))
      if (line.indexOf(':') case final colon when colon > 0)
        line.substring(0, colon).trim().toLowerCase(): line
            .substring(colon + 1)
            .trim(),
  };
}

TusTransport createTusTransport() => _XhrTransport();

// --- Storage -----------------------------------------------------------------

/// Uploads kept in IndexedDB: each a JSON record, with its file handle when
/// the browser gave one. Handles can be kept there and nowhere else.
class _IndexedDbStore implements UploadStore {
  static const _name = 'veloraug-uploads';
  static const _table = 'uploads';

  Future<web.IDBDatabase>? _opening;
  final Map<String, JSObject> _handles = {};

  Future<web.IDBDatabase> _database() => _opening ??= () {
    final request = web.window.indexedDB.open(_name, 1);
    request.onupgradeneeded = ((web.Event _) {
      (request.result as web.IDBDatabase).createObjectStore(_table);
    }).toJS;
    return _result(request).then((value) => value as web.IDBDatabase);
  }();

  Future<JSAny?> _result(web.IDBRequest request) {
    final done = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) => done.complete(request.result)).toJS;
    request.onerror = ((web.Event _) {
      if (!done.isCompleted) done.completeError(StateError('IndexedDB failed'));
    }).toJS;
    return done.future;
  }

  Future<void> _write(void Function(web.IDBObjectStore table) change) async {
    final db = await _database();
    final transaction = db.transaction(_table.toJS, 'readwrite');
    final done = Completer<void>();
    transaction.oncomplete = ((web.Event _) => done.complete()).toJS;
    transaction.onerror = ((web.Event _) {
      if (!done.isCompleted) done.completeError(StateError('IndexedDB failed'));
    }).toJS;
    transaction.onabort = ((web.Event _) {
      if (!done.isCompleted) done.completeError(StateError('IndexedDB failed'));
    }).toJS;
    change(transaction.objectStore(_table));
    return done.future;
  }

  @override
  Future<List<StoredUpload>> load() async {
    final db = await _database();
    final table = db.transaction(_table.toJS, 'readonly').objectStore(_table);
    final rows = await _result(table.getAll()) as JSArray<JSObject>;
    final found = <StoredUpload>[];
    for (final row in rows.toDart) {
      try {
        final record = jsonDecode(
          (row['record']! as JSString).toDart,
        ) as Map<String, Object?>;
        final handle = row['handle'];
        final id = record['id'] as String;
        if (handle != null && handle.isA<JSObject>()) {
          _handles[id] = handle as JSObject;
        }
        found.add(StoredUpload(record, canReopen: _handles.containsKey(id)));
      } on Object {
        // A damaged row is left out.
      }
    }
    return found;
  }

  @override
  Future<void> save(String id, Map<String, Object?> record, {Object? handle}) {
    // Only this file makes handles, and they are always JS objects.
    if (handle != null) _handles[id] = handle as JSObject;
    final row = JSObject()
      ..['record'] = jsonEncode(record).toJS
      ..['handle'] = _handles[id];
    return _write((table) => table.put(row, id.toJS));
  }

  @override
  Future<void> delete(String id) {
    _handles.remove(id);
    return _write((table) => table.delete(id.toJS));
  }

  @override
  Future<LocalVideoFile?> reopen(String id) async {
    final handle = _handles[id];
    if (handle == null) return null;
    final options = {'mode': 'read'}.jsify();
    if (handle.has('queryPermission')) {
      var state = await _call<JSString>(handle, 'queryPermission', options);
      if (state.toDart != 'granted' && handle.has('requestPermission')) {
        // Shows Chrome's "Allow access to this file?" for the click on
        // Resume that got here.
        state = await _call<JSString>(handle, 'requestPermission', options);
      }
      if (state.toDart != 'granted') return null;
    }
    return _WebFile(await _call<web.File>(handle, 'getFile'));
  }
}

Future<T> _call<T extends JSAny?>(
  JSObject target,
  String method, [
  JSAny? arg,
]) => target.callMethod<JSPromise<T>>(method.toJS, arg).toDart;

UploadStore createUploadStore() {
  try {
    return _IndexedDbStore();
  } on Object {
    return MemoryUploadStore();
  }
}

// --- Online status and leaving -----------------------------------------------

class _BrowserNetwork implements NetworkStatus {
  _BrowserNetwork() {
    web.window.addEventListener(
      'online',
      ((web.Event _) => _changes.add(true)).toJS,
    );
    web.window.addEventListener(
      'offline',
      ((web.Event _) => _changes.add(false)).toJS,
    );
  }

  final StreamController<bool> _changes = StreamController.broadcast();

  @override
  bool get online => web.window.navigator.onLine;

  @override
  Stream<bool> get changes => _changes.stream;
}

NetworkStatus createNetworkStatus() => _BrowserNetwork();

final JSFunction _beforeUnload = ((web.BeforeUnloadEvent event) {
  // Makes the browser ask "Leave site?". Browsers show their own words.
  event.preventDefault();
  event.returnValue = '';
}).toJS;
bool _warning = false;

void warnBeforeLeaving(bool busy) {
  if (busy == _warning) return;
  _warning = busy;
  if (busy) {
    web.window.addEventListener('beforeunload', _beforeUnload);
  } else {
    web.window.removeEventListener('beforeunload', _beforeUnload);
  }
}

// --- Drops and the file chooser ----------------------------------------------

bool _hasFiles(web.DragEvent event) {
  final types = event.dataTransfer?.types;
  if (types == null) return false;
  return types.toDart.any((type) => type.toDart == 'Files');
}

bool _guarded = false;

void guardAgainstFileDrops() {
  if (_guarded) return;
  _guarded = true;
  void stop(web.DragEvent event) {
    if (_hasFiles(event)) event.preventDefault();
  }

  web.window.addEventListener('dragover', stop.toJS);
  web.window.addEventListener('drop', stop.toJS);
}

void Function() listenForVideoDrops({
  required void Function(bool over) onHover,
  required void Function(List<PickedVideo> videos) onDrop,
}) {
  var depth = 0;
  final enter = ((web.DragEvent event) {
    if (!_hasFiles(event)) return;
    event.preventDefault();
    if (depth++ == 0) onHover(true);
  }).toJS;
  final over = ((web.DragEvent event) {
    if (!_hasFiles(event)) return;
    event.preventDefault();
    event.dataTransfer?.dropEffect = 'copy';
  }).toJS;
  final leave = ((web.DragEvent event) {
    if (!_hasFiles(event)) return;
    depth = math.max(0, depth - 1);
    if (depth == 0) onHover(false);
  }).toJS;
  final drop = ((web.DragEvent event) {
    if (!_hasFiles(event)) return;
    event.preventDefault();
    depth = 0;
    onHover(false);
    final transfer = event.dataTransfer;
    if (transfer == null) return;
    // Handles and files must be asked for now, during the drop event.
    final waiting = <Future<PickedVideo?>>[];
    final items = transfer.items;
    for (var i = 0; i < items.length; i++) {
      final item = (items as JSObject).getProperty<web.DataTransferItem>(
        i.toJS,
      );
      if (item.kind != 'file') continue;
      final file = item.getAsFile();
      final JSPromise<JSObject?>? handle =
          (item as JSObject).has('getAsFileSystemHandle')
          ? item.callMethod<JSPromise<JSObject?>>('getAsFileSystemHandle'.toJS)
          : null;
      waiting.add(_picked(file, handle));
    }
    Future.wait(waiting).then((videos) => onDrop(videos.nonNulls.toList()));
  }).toJS;
  web.window
    ..addEventListener('dragenter', enter)
    ..addEventListener('dragover', over)
    ..addEventListener('dragleave', leave)
    ..addEventListener('drop', drop);
  return () {
    web.window
      ..removeEventListener('dragenter', enter)
      ..removeEventListener('dragover', over)
      ..removeEventListener('dragleave', leave)
      ..removeEventListener('drop', drop);
  };
}

Future<PickedVideo?> _picked(
  web.File? file,
  JSPromise<JSObject?>? handlePromise,
) async {
  JSObject? handle;
  if (handlePromise != null) {
    try {
      handle = await handlePromise.toDart;
    } on Object {
      handle = null;
    }
  }
  final kind = (handle?['kind'] as JSString?)?.toDart;
  if (kind == 'directory' || file == null) return null;
  return PickedVideo(_WebFile(file), handle: kind == 'file' ? handle : null);
}

Future<List<PickedVideo>> pickVideos() async {
  final window = web.window as JSObject;
  if (window.has('showOpenFilePicker')) {
    try {
      final handles = await window
          .callMethod<JSPromise<JSArray<JSObject>>>(
            'showOpenFilePicker'.toJS,
            {
              'multiple': true,
              'types': [
                {
                  'accept': {
                    'video/*': [for (final ext in videoExtensions) '.$ext'],
                  },
                },
              ],
            }.jsify(),
          )
          .toDart;
      return [
        for (final handle in handles.toDart)
          PickedVideo(
            _WebFile(await _call<web.File>(handle, 'getFile')),
            handle: handle,
          ),
      ];
    } on Object {
      // Cancelled, or blocked: nothing picked.
      return const [];
    }
  }
  final done = Completer<List<PickedVideo>>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true
    ..accept = [
      'video/*',
      for (final ext in videoExtensions) '.$ext',
    ].join(',');
  input.addEventListener(
    'cancel',
    ((web.Event _) {
      if (!done.isCompleted) done.complete(const []);
    }).toJS,
  );
  input.addEventListener(
    'change',
    ((web.Event _) {
      final files = input.files;
      if (done.isCompleted) return;
      done.complete([
        if (files != null)
          for (var i = 0; i < files.length; i++)
            if (files.item(i) case final file?) PickedVideo(_WebFile(file)),
      ]);
    }).toJS,
  );
  input.click();
  return done.future;
}
