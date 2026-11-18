import 'tus.dart';
import 'upload_queue.dart';

class _NoTransport implements TusTransport {
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
  }) async => throw const TusOffline();
}

TusTransport createTusTransport() => _NoTransport();

UploadStore createUploadStore() => MemoryUploadStore();

NetworkStatus createNetworkStatus() => const AlwaysOnline();

void warnBeforeLeaving(bool busy) {}

/// Stops a file dropped anywhere on the page from replacing the app.
void guardAgainstFileDrops() {}

Future<List<PickedVideo>> pickVideos() async => const [];

/// Calls [onDrop] with video files dropped on the page while listening.
/// Returns a function that stops listening.
void Function() listenForVideoDrops({
  required void Function(bool over) onHover,
  required void Function(List<PickedVideo> videos) onDrop,
}) => () {};
