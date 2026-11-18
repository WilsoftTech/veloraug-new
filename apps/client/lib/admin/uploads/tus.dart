/// The tus resumable-upload protocol, version 1.0.0, as tusd speaks it: the
/// same steps as tools/veloraug_upload.py.
///
/// - POST starts an upload, with the one-time upload key. tusd answers with
///   the upload's own address, which is all that is needed from then on.
/// - HEAD asks how many bytes the server already has.
/// - PATCH sends the next part from there.
/// - DELETE removes an unfinished upload.
///
/// tusd keeps every byte it receives, even from a part cut off half way, so
/// after any failure the next HEAD says where to carry on.
library;

import 'dart:async';
import 'dart:convert';

const String tusVersion = '1.0.0';

/// Each PATCH sends at most this much: under Cloudflare's 100 MB limit on a
/// request, for when uploads go through it in Milestone 11.
const int tusChunkBytes = 50 * 1024 * 1024;

/// A file being uploaded. On the web, a File from a drop, the file chooser
/// or a kept file handle.
abstract class LocalVideoFile {
  String get name;
  int get size;

  /// Milliseconds since 1970, as the browser reports it. With [name] and
  /// [size], it recognises the same file dropped again.
  int get lastModified;
}

/// Lets a request in flight be stopped, for Pause and Remove.
class TusCancel {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Calls [listener] on cancel, at once if already cancelled. Returns a
  /// function that stops listening.
  void Function() listen(void Function() listener) {
    if (_cancelled) {
      listener();
      return () {};
    }
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }
}

class TusReply {
  const TusReply(this.status, [this.headers = const {}, this.body = '']);

  final int status;

  /// Lower-case names.
  final Map<String, String> headers;
  final String body;
}

/// One HTTP request. The web version uses XMLHttpRequest, for its upload
/// progress events.
abstract class TusTransport {
  /// Sends a request, with bytes [start] to [end] of [file] as the body
  /// when given. Throws [TusOffline] when no answer comes, and
  /// [TusCancelled] when [cancel] stops it.
  Future<TusReply> send(
    String method,
    Uri url,
    Map<String, String> headers, {
    LocalVideoFile? file,
    int start = 0,
    int end = 0,
    void Function(int sent)? onProgress,
    TusCancel? cancel,
  });
}

sealed class TusException implements Exception {
  const TusException();
}

/// No answer: the network, or the server, is down. Worth trying again.
class TusOffline extends TusException {
  const TusOffline();
}

/// The request was stopped on purpose.
class TusCancelled extends TusException {
  const TusCancelled();
}

/// An answer that may pass if tried again, such as a 500 or 503.
class TusRetry extends TusException {
  const TusRetry(this.status);

  final int status;
}

/// The upload key was refused: used, expired, revoked or mistyped.
class TusKeyRefused extends TusException {
  const TusKeyRefused();
}

/// The file is larger than the server takes.
class TusTooLarge extends TusException {
  const TusTooLarge();
}

/// The upload's address no longer works, so it must start again.
class TusGone extends TusException {
  const TusGone();
}

/// The server refused to remove an upload, because it has finished.
class TusNotRemovable extends TusException {
  const TusNotRemovable();
}

class TusClient {
  TusClient(this.transport);

  final TusTransport transport;

  Map<String, String> _headers([Map<String, String> extra = const {}]) => {
    'Tus-Resumable': tusVersion,
    ...extra,
  };

  /// Starts an upload at [endpoint], tusd's base address, and returns its
  /// own address. The key is sent here only.
  Future<Uri> create({
    required Uri endpoint,
    required LocalVideoFile file,
    required String key,
    TusCancel? cancel,
  }) async {
    final name = base64.encode(utf8.encode(file.name));
    final reply = await transport.send(
      'POST',
      endpoint,
      _headers({
        'Upload-Length': '${file.size}',
        'Upload-Metadata': 'filename $name',
        'Upload-Key': key,
      }),
      cancel: cancel,
    );
    final location = reply.headers['location'];
    if (reply.status == 201 && location != null && location.isNotEmpty) {
      final url = endpoint.resolve(location);
      // Only ever send the file back to the same server.
      if (url.origin != endpoint.origin) throw const TusRetry(201);
      return url;
    }
    throw switch (reply.status) {
      403 => const TusKeyRefused(),
      413 => const TusTooLarge(),
      _ => TusRetry(reply.status),
    };
  }

  /// How many bytes the server has.
  Future<int> offset(Uri upload, {TusCancel? cancel}) async {
    final reply = await transport.send(
      'HEAD',
      upload,
      _headers(),
      cancel: cancel,
    );
    if (reply.status == 200 || reply.status == 204) {
      final offset = int.tryParse(reply.headers['upload-offset'] ?? '');
      if (offset != null && offset >= 0) return offset;
    }
    throw switch (reply.status) {
      403 || 404 || 410 => const TusGone(),
      _ => TusRetry(reply.status),
    };
  }

  /// Sends bytes [from] up to [to] and returns the server's new offset.
  /// [onProgress] gets the bytes of this part sent so far.
  Future<int> patch(
    Uri upload,
    LocalVideoFile file, {
    required int from,
    required int to,
    void Function(int sent)? onProgress,
    TusCancel? cancel,
  }) async {
    final reply = await transport.send(
      'PATCH',
      upload,
      _headers({
        'Upload-Offset': '$from',
        'Content-Type': 'application/offset+octet-stream',
      }),
      file: file,
      start: from,
      end: to,
      onProgress: onProgress,
      cancel: cancel,
    );
    if (reply.status == 204 || reply.status == 200) {
      final offset = int.tryParse(reply.headers['upload-offset'] ?? '');
      if (offset != null && offset >= from) return offset;
    }
    throw switch (reply.status) {
      403 || 404 || 410 => const TusGone(),
      // 409: the server has a different offset. The next HEAD says which.
      _ => TusRetry(reply.status),
    };
  }

  /// Removes an unfinished upload and its bytes from the server. One
  /// already gone counts as removed.
  Future<void> terminate(Uri upload) async {
    final reply = await transport.send('DELETE', upload, _headers());
    switch (reply.status) {
      case 204 || 200 || 404 || 410:
        return;
      case 403:
        throw const TusNotRemovable();
      default:
        throw TusRetry(reply.status);
    }
  }
}
