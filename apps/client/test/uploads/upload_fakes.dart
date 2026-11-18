import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:veloraug/admin/uploads/tus.dart';
import 'package:veloraug/admin/uploads/upload_queue.dart';

import '../support.dart';

const uploadEndpoint = 'http://127.0.0.1:1080/files/';

class FakeFile implements LocalVideoFile {
  FakeFile(this.name, {this.size = 25, this.lastModified = 1700000000000});

  @override
  final String name;
  @override
  final int size;
  @override
  final int lastModified;
}

PickedVideo video(
  String name, {
  int size = 25,
  int modified = 1700000000000,
  Object? handle,
}) => PickedVideo(
  FakeFile(name, size: size, lastModified: modified),
  handle: handle,
);

/// tusd, in memory: keys, offsets, and the failures a network can cause.
class FakeTusServer implements TusTransport {
  /// Keys that will be accepted once.
  final keys = <String>{};
  final offsets = <String, int>{};
  final sizes = <String, int>{};
  final names = <String, String>{};

  /// "METHOD /path" of each request, and the Upload-Offset of each PATCH.
  final log = <String>[];
  final patchOffsets = <int>[];

  /// The next requests fail with no answer.
  int failNext = 0;
  bool offline = false;

  /// The next PATCH stores this many bytes, then the connection drops.
  int? dropAfter;

  /// While set, PATCHes wait for it, or for their cancel.
  Completer<void>? hold;

  int _uploads = 0;

  String _id(Uri url) => url.pathSegments.lastWhere((s) => s.isNotEmpty);

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
    log.add('$method ${url.path}');
    if (offline) throw const TusOffline();
    if (failNext > 0) {
      failNext--;
      throw const TusOffline();
    }
    if (headers['Tus-Resumable'] != tusVersion) return const TusReply(412);
    switch (method) {
      case 'POST':
        final key = headers['Upload-Key'];
        if (key == null || !keys.remove(key)) return const TusReply(403);
        final id = 'up${++_uploads}';
        sizes[id] = int.parse(headers['Upload-Length']!);
        offsets[id] = 0;
        names[id] = headers['Upload-Metadata']!;
        return TusReply(201, {'location': '/files/$id'});
      case 'HEAD':
        final offset = offsets[_id(url)];
        if (offset == null) return const TusReply(404);
        return TusReply(200, {'upload-offset': '$offset'});
      case 'PATCH':
        final id = _id(url);
        final have = offsets[id];
        if (have == null) return const TusReply(404);
        final from = int.parse(headers['Upload-Offset']!);
        patchOffsets.add(from);
        if (from != have) return const TusReply(409);
        final waiting = hold;
        if (waiting != null) {
          final stopped = Completer<void>();
          final stop = cancel?.listen(stopped.complete);
          await Future.any([waiting.future, stopped.future]);
          stop?.call();
          if (cancel?.isCancelled ?? false) throw const TusCancelled();
        }
        final drop = dropAfter;
        if (drop != null) {
          dropAfter = null;
          offsets[id] = from + drop;
          onProgress?.call(drop);
          throw const TusOffline();
        }
        offsets[id] = end;
        onProgress?.call(end - from);
        return TusReply(204, {'upload-offset': '$end'});
      case 'DELETE':
        final id = _id(url);
        if (!offsets.containsKey(id)) return const TusReply(404);
        if (offsets[id] == sizes[id]) return const TusReply(403);
        offsets.remove(id);
        return const TusReply(204);
    }
    return const TusReply(405);
  }

  bool finished(String id) => offsets[id] != null && offsets[id] == sizes[id];
}

class FakeNetwork implements NetworkStatus {
  final _changes = StreamController<bool>.broadcast(sync: true);

  @override
  bool online = true;

  void set(bool value) {
    online = value;
    _changes.add(value);
  }

  @override
  Stream<bool> get changes => _changes.stream;
}

/// The admin routes uploads use: drafts and episodes, keys and credit. Each
/// key made is one the fake tusd accepts.
class Admin {
  Admin(this.server) {
    api
      ..isAdmin = true
      ..admin['POST /drafts'] = (request) {
        final body = jsonDecode(request.body) as Map<String, Object?>;
        drafts.add(body);
        final series = body['series_edition_id'] as String?;
        final n = drafts.length;
        return json(
          _key({'edition_id': series ?? 'e$n', 'item_id': 'i$n'}),
          201,
        );
      }
      ..admin['PUT /editions/e1/credit'] = _credit
      ..admin['PUT /editions/e2/credit'] = _credit
      ..admin['PUT /editions/e3/credit'] = _credit;
    for (var i = 1; i <= 9; i++) {
      api.admin['POST /items/i$i/keys'] = (_) {
        newKeys.add('i$i');
        return json(_key({}), 201);
      };
    }
  }

  final FakeTusServer server;
  final api = FakeApi();
  final drafts = <Map<String, Object?>>[];
  final credits = <String>[];
  final newKeys = <String>[];
  int _keys = 0;

  Map<String, Object?> _key(Map<String, Object?> extra) {
    final key = 'key-${++_keys}';
    server.keys.add(key);
    return {
      'key_id': 'k$_keys',
      'upload_key': key,
      'expires_at': '2030-01-01T00:00:00Z',
      ...extra,
    };
  }

  http.Response _credit(http.Request request) {
    credits.add(
      '${request.url.pathSegments[4]}:${jsonDecode(request.body)['vj_id']}',
    );
    return json({
      'id': request.url.pathSegments[4],
      'kind': 'movie',
      'display_title': 'x',
      'language': 'lg',
      'status': 'draft',
      'created_at': '2026-11-18T00:00:00Z',
    });
  }
}
