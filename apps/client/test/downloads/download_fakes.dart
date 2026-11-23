import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloraug/api/device_store.dart';
import 'package:veloraug/api/playback_api.dart';
import 'package:veloraug/downloads/download_manager.dart';
import 'package:veloraug/downloads/download_storage.dart';

const apiBase = 'http://127.0.0.1:8000';
const gateway = 'http://127.0.0.1:8787';
const movieId = '11111111-1111-4111-8111-111111111111';
const episodeId = '22222222-2222-4222-8222-222222222222';

const masterText = '''#EXTM3U
#EXT-X-VERSION:7
#EXT-X-STREAM-INF:BANDWIDTH=900000,AVERAGE-BANDWIDTH=800000,RESOLUTION=1280x720
720p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=400000,AVERAGE-BANDWIDTH=300000,RESOLUTION=640x360
360p/index.m3u8
''';

String mediaText(int chunks) => [
  '#EXTM3U',
  '#EXT-X-VERSION:7',
  '#EXT-X-PLAYLIST-TYPE:VOD',
  '#EXT-X-MAP:URI="init_0.mp4"',
  for (var i = 0; i < chunks; i++) ...['#EXTINF:6.0,', 'seg_0000$i.m4s'],
  '#EXT-X-ENDLIST',
].join('\n');

/// The API and the media gateway, faked together.
class FakeMediaServer {
  FakeMediaServer({this.chunks = 5});

  final int chunks;
  DateTime now = DateTime.utc(2026, 11, 23, 12);
  Duration grantLasts = const Duration(hours: 1);
  DateTime offlineUntil = DateTime.utc(2026, 11, 30, 12);

  /// The answer to a download grant: 200, or a refusal such as 402.
  int grantStatus = 200;

  /// The answer to a licence renewal: 200, or a refusal.
  int licenceStatus = 200;
  String? licenceCode;

  /// Items whose licence comes back null: taken down.
  final Set<String> takenDown = {};

  /// Grants the gateway no longer honours.
  final Set<String> refusedGrants = {};

  /// Files that fail with no answer, once each.
  final Set<String> dropOnce = {};

  /// Gateway answers that aren't a dropped connection, by file.
  final Map<String, int> statusFor = {};

  int grants = 0;
  int posterRequests = 0;
  int licenceRenewals = 0;
  final List<String> fetched = [];

  late final http.Client client = MockClient(_handle);

  PlaybackApi api() => PlaybackApi(
    baseUrl: Uri.parse(apiBase),
    mediaBaseUrl: Uri.parse(gateway),
    httpClient: client,
    accessToken: () async => 'ACCESS',
    deviceStore: MemoryDeviceStore(),
  );

  static Uint8List bytesOf(String name) =>
      Uint8List.fromList(utf8.encode('bytes of $name'));

  Future<http.Response> _handle(http.Request request) async {
    final url = request.url;
    if (url.toString().startsWith(apiBase)) return _api(request);
    if (!url.toString().startsWith(gateway)) {
      // Posters, on TMDB.
      posterRequests++;
      return http.Response('', 404);
    }
    final parts = url.path.split('/');
    // /v1/<grant>/<rest>
    final grant = parts[2];
    final rest = parts.skip(3).join('/');
    if (refusedGrants.contains(grant)) return http.Response('', 403);
    final status = statusFor[rest];
    if (status != null) return http.Response('', status);
    if (dropOnce.remove(rest)) throw http.ClientException('dropped');
    fetched.add(rest);
    if (rest == 'master.m3u8') return http.Response(masterText, 200);
    if (rest.endsWith('index.m3u8')) {
      return http.Response(mediaText(chunks), 200);
    }
    return http.Response.bytes(bytesOf(rest), 200);
  }

  http.Response _api(http.Request request) {
    final path = request.url.path;
    if (path.endsWith('/download')) {
      grants++;
      if (grantStatus != 200) {
        return http.Response(jsonEncode({'detail': 'No.'}), grantStatus);
      }
      return http.Response(
        jsonEncode({
          'playlist_url': '$gateway/v1/GRANT$grants.sig/master.m3u8',
          'expires_at': now.add(grantLasts).toIso8601String(),
          'offline_until': offlineUntil.toIso8601String(),
        }),
        200,
      );
    }
    if (path == '/api/v1/me/offline-licences') {
      licenceRenewals++;
      if (licenceStatus != 200) {
        return http.Response(
          jsonEncode({
            'detail': licenceCode == null
                ? 'No.'
                : {'code': licenceCode, 'message': 'No.'},
          }),
          licenceStatus,
        );
      }
      final items = (jsonDecode(request.body) as Map)['items'] as List;
      return http.Response(
        jsonEncode({
          'licences': [
            for (final id in items)
              {
                'item_id': id,
                'offline_until': takenDown.contains(id)
                    ? null
                    : offlineUntil.toIso8601String(),
              },
          ],
        }),
        200,
      );
    }
    if (path == '/api/v1/me/devices') {
      return http.Response(
        jsonEncode({
          'detail': {'code': 'device_limit', 'limit': 1},
        }),
        409,
      );
    }
    return http.Response('', 404);
  }
}

DownloadManager manager(
  FakeMediaServer server,
  MemoryDownloadStorage storage,
) => DownloadManager(
  storage: storage,
  api: server.api(),
  clock: () => server.now,
  retryAfter: (_) => Duration.zero,
  fileRetryDelay: Duration.zero,
);

const movieInfo = DownloadInfo(
  editionId: 'edition-1',
  title: 'Fast X',
  label: 'Luganda · VJ Junior',
);
