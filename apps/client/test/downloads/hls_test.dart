import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/downloads/hls.dart';

/// As the media worker writes it.
const master = '''#EXTM3U
#EXT-X-VERSION:7
#EXT-X-STREAM-INF:BANDWIDTH=1004296,AVERAGE-BANDWIDTH=370458,RESOLUTION=640x320,CODECS="avc1.640016,mp4a.40.2"
360p/index.m3u8

#EXT-X-STREAM-INF:BANDWIDTH=2471784,RESOLUTION=1920x960,CODECS="avc1.640028,mp4a.40.2"
1080p/index.m3u8
''';

const media = '''#EXTM3U
#EXT-X-VERSION:7
#EXT-X-TARGETDURATION:6
#EXT-X-PLAYLIST-TYPE:VOD
#EXT-X-MAP:URI="init_0.mp4"
#EXTINF:6.000000,
seg_00000.m4s
#EXTINF:4.5,
seg_00001.m4s
#EXT-X-ENDLIST
''';

void main() {
  test('qualities come highest first, with the average rate if given', () {
    final qualities = parseDownloadQualities(master);

    expect(qualities.map((q) => q.quality.label), ['1080p', '360p']);
    expect(qualities.map((q) => q.bitsPerSecond), [2471784, 370458]);
    expect(qualities.first.estimatedBytes, isNull);
    expect(
      qualities.last.withSeconds(80).estimatedBytes,
      (370458 * 80 / 8).round(),
    );
  });

  test('a quality playlist names its init file then its chunks', () {
    final playlist = parseMediaPlaylist(media);

    expect(playlist.files, ['init_0.mp4', 'seg_00000.m4s', 'seg_00001.m4s']);
    expect(playlist.seconds, 10.5);
  });

  test('anything the media worker never writes is refused', () {
    for (final bad in [
      media.replaceFirst('seg_00000.m4s', 'https://elsewhere.test/seg.m4s'),
      media.replaceFirst('seg_00000.m4s', '../other/seg_00000.m4s'),
      media.replaceFirst('init_0.mp4', '../init.mp4'),
      media.replaceFirst('#EXT-X-MAP', '#EXT-X-KEY:METHOD=AES-128\n#EXT-X-MAP'),
      media.replaceFirst('#EXT-X-ENDLIST', ''),
    ]) {
      expect(() => parseMediaPlaylist(bad), throwsFormatException, reason: bad);
    }
  });

  test('the kept master playlist names only the quality downloaded', () {
    final quality = parseDownloadQualities(master).last.quality;

    final kept = localMasterPlaylist(master, quality);

    expect(kept, contains('#EXTM3U'));
    expect(kept, contains('360p/index.m3u8'));
    expect(kept, isNot(contains('1080p')));
    expect(kept, contains('AVERAGE-BANDWIDTH=370458'));
  });
}
