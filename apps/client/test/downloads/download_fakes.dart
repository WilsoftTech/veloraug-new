import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/api/device_store.dart';
import 'package:veloraug/api/playback_api.dart';
import 'package:veloraug/downloads/downloads.dart';

const apiBase = 'http://127.0.0.1:8000';
const gateway = 'http://127.0.0.1:8787';
const movieId = '11111111-1111-4111-8111-111111111111';
const episodeId = '22222222-2222-4222-8222-222222222222';

const masterText = '''#EXTM3U
#EXT-X-VERSION:7
#EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=1280x720
720p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=640x360
360p/index.m3u8
''';

/// The API's download route and the media gateway, faked together.
class FakeMediaServer {
  /// The answer to a download grant: 200, or a refusal such as 402.
  int grantStatus = 200;
  String fileName = 'Fast X - VJ Junior';

  /// Each quality's download.mp4 size; a quality left out answers 404, as
  /// for a film whose files haven't been made yet.
  Map<String, int> sizes = {'720p': 1200000000, '360p': 350000000};

  int grants = 0;
  final List<http.Request> requests = [];

  late final http.Client client = MockClient((request) async {
    requests.add(request);
    final url = request.url;
    if (url.toString().startsWith(apiBase)) {
      if (!url.path.endsWith('/download')) return http.Response('', 404);
      grants++;
      if (grantStatus != 200) {
        return http.Response(jsonEncode({'detail': 'No.'}), grantStatus);
      }
      return http.Response(
        jsonEncode({
          'playlist_url': '$gateway/v1/GRANT$grants.sig/master.m3u8',
          'expires_at': '2030-01-01T00:00:00Z',
          'file_name': fileName,
        }),
        200,
      );
    }
    if (url.path.endsWith('/master.m3u8')) {
      return http.Response(masterText, 200);
    }
    if (url.path.endsWith('/download.mp4') && request.method == 'HEAD') {
      final size = sizes[url.pathSegments[2]];
      if (size == null) return http.Response('', 404);
      return http.Response('', 200, headers: {'content-length': '$size'});
    }
    return http.Response('', 404);
  });

  PlaybackApi api() => PlaybackApi(
    baseUrl: Uri.parse(apiBase),
    mediaBaseUrl: Uri.parse(gateway),
    httpClient: client,
    accessToken: () async => 'ACCESS',
    deviceStore: MemoryDeviceStore(),
  );
}

/// Android's download manager, or the browser, faked.
class FakeTarget implements DownloadTarget {
  FakeTarget({this.followed = true});

  @override
  final bool followed;

  final List<DownloadFile> started = [];
  final Map<String, FileStatus> statuses = {};
  final List<String> removed = [];
  final List<String> opened = [];
  DownloadRefusal? refuse;
  bool canOpen = true;

  @override
  Future<String?> start(DownloadFile file, String title) async {
    if (refuse case final reason?) throw DownloadRefused(reason);
    started.add(file);
    if (!followed) return null;
    final id = '${started.length}';
    statuses[id] = const FileStatus(state: FileState.waiting);
    return id;
  }

  @override
  Future<Map<String, FileStatus>> status(List<String> ids) async => {
    for (final id in ids) id: ?statuses[id],
  };

  @override
  Future<bool> open(String id) async {
    opened.add(id);
    return canOpen;
  }

  @override
  Future<void> remove(String id) async {
    removed.add(id);
    statuses.remove(id);
  }
}

const movieInfo = DownloadInfo(
  editionId: 'edition-1',
  title: 'Fast X',
  label: 'Luganda · VJ Junior',
);
