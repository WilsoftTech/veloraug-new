import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/api/playback_api.dart';

void main() {
  test(
    'the media worker master playlist gives four qualities, highest first',
    () {
      const text = '''
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-STREAM-INF:BANDWIDTH=1088017,AVERAGE-BANDWIDTH=901679,RESOLUTION=640x266,CODECS="avc1.640015,mp4a.40.2"
360p/index.m3u8

#EXT-X-STREAM-INF:BANDWIDTH=3829844,RESOLUTION=1920x800,CODECS="avc1.640028,mp4a.40.2"
1080p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1854833,RESOLUTION=854x356
480p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3582027,RESOLUTION=1280x534
720p/index.m3u8
''';
      final qualities = parseMasterPlaylist(text);

      expect(
        [for (final q in qualities) q.label],
        ['1080p', '720p', '480p', '360p'],
      );
      expect(qualities.first.path, '1080p/index.m3u8');
      // A wide film's 1080p is 800 lines, but named by its quality.
      expect(qualities.first.height, 1080);
    },
  );

  test('anything that could lead elsewhere is ignored', () {
    const text = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=640x360
../other/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=640x360
https://elsewhere.example/360p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=640x360
360p/index.m3u8?x=1
#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1280x720
hd/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1,RESOLUTION=1280x720
hd/index.m3u8
''';
    final qualities = parseMasterPlaylist(text);

    expect(qualities.single.path, 'hd/index.m3u8');
    expect(qualities.single.label, '720p');
  });

  test('a quality plays under the same grant', () {
    final grant = PlaybackGrant(
      playlistUrl: Uri.parse('https://gw.example/v1/abc.sig/master.m3u8'),
      expiresAt: DateTime.utc(2030),
    );
    const quality = VideoQuality(
      label: '720p',
      height: 720,
      path: '720p/index.m3u8',
    );

    expect(
      grant.qualityUrl(quality).toString(),
      'https://gw.example/v1/abc.sig/720p/index.m3u8',
    );
  });

  test('nothing usable gives nothing', () {
    expect(parseMasterPlaylist(''), isEmpty);
    expect(parseMasterPlaylist('<html>no</html>'), isEmpty);
  });
}
