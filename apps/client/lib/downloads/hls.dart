import 'dart:convert';

import '../api/playback_api.dart';

/// What a download needs from HLS playlists, and nothing more.
///
/// The media worker writes one master playlist, and per quality a folder
/// with `index.m3u8`, an init file and numbered chunks. Only names the media
/// gateway itself serves are accepted, so a playlist can't make the app
/// fetch anything else, or write outside the download's folder.

/// A quality offered for download: its playlist, and its size per second.
class DownloadQuality {
  const DownloadQuality({
    required this.quality,
    required this.bitsPerSecond,
    this.seconds,
  });

  final VideoQuality quality;

  /// AVERAGE-BANDWIDTH where given, else BANDWIDTH.
  final int bitsPerSecond;

  /// The video's length, once its own playlist has been read.
  final double? seconds;

  /// About how many bytes the download takes, when its length is known.
  int? get estimatedBytes {
    final length = seconds;
    if (length == null || bitsPerSecond <= 0) return null;
    return (bitsPerSecond * length / 8).round();
  }

  DownloadQuality withSeconds(double seconds) => DownloadQuality(
    quality: quality,
    bitsPerSecond: bitsPerSecond,
    seconds: seconds,
  );
}

/// The qualities in a master playlist, highest first, with their rates.
List<DownloadQuality> parseDownloadQualities(String master) {
  final qualities = {
    for (final quality in parseMasterPlaylist(master)) quality.path: quality,
  };
  final found = <DownloadQuality>[];
  int? rate;
  for (final raw in const LineSplitter().convert(master)) {
    final line = raw.trim();
    if (line.startsWith('#EXT-X-STREAM-INF:')) {
      final average = RegExp(r'AVERAGE-BANDWIDTH=(\d+)').firstMatch(line);
      final peak = RegExp(r'(?:^|[:,])BANDWIDTH=(\d+)').firstMatch(line);
      rate = int.tryParse((average ?? peak)?[1] ?? '');
      continue;
    }
    if (line.isEmpty || line.startsWith('#')) continue;
    final quality = qualities[line];
    if (quality != null && found.every((q) => q.quality != quality)) {
      found.add(DownloadQuality(quality: quality, bitsPerSecond: rate ?? 0));
    }
    rate = null;
  }
  return found..sort((a, b) => b.quality.height.compareTo(a.quality.height));
}

final RegExp _init = RegExp(r'^init(?:_\d{1,2})?\.mp4$');
final RegExp _chunk = RegExp(r'^seg_\d{1,6}\.m4s$');

/// One quality's playlist: the files to fetch, in order, and its length.
class MediaPlaylist {
  const MediaPlaylist({required this.files, required this.seconds});

  /// Names beside the playlist, such as `init_0.mp4` and `seg_00012.m4s`.
  final List<String> files;
  final double seconds;
}

/// Reads one quality's playlist. Throws [FormatException] for anything the
/// media worker doesn't write: another kind of file, a folder, an address,
/// encryption, or a playlist that never ends.
MediaPlaylist parseMediaPlaylist(String text) {
  final files = <String>[];
  var seconds = 0.0;
  var ended = false;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXT-X-MAP:')) {
      final uri = RegExp(r'URI="([^"]*)"').firstMatch(line)?[1];
      if (uri == null || !_init.hasMatch(uri)) {
        throw const FormatException('Unexpected init file');
      }
      if (!files.contains(uri)) files.add(uri);
    } else if (line.startsWith('#EXTINF:')) {
      final length = double.tryParse(
        line.substring('#EXTINF:'.length).split(',').first,
      );
      if (length == null || length < 0) {
        throw const FormatException('Unexpected chunk length');
      }
      seconds += length;
    } else if (line.startsWith('#EXT-X-KEY')) {
      throw const FormatException('Encrypted playlists are not expected');
    } else if (line == '#EXT-X-ENDLIST') {
      ended = true;
    } else if (!line.startsWith('#')) {
      if (!_chunk.hasMatch(line)) {
        throw const FormatException('Unexpected chunk name');
      }
      files.add(line);
    }
  }
  if (!ended || !files.any(_chunk.hasMatch)) {
    throw const FormatException('Not a finished playlist');
  }
  return MediaPlaylist(files: files, seconds: seconds);
}

/// The master playlist kept with a download: the one quality downloaded,
/// so the player never looks for another.
String localMasterPlaylist(String master, VideoQuality quality) {
  final out = <String>[];
  String? pending;
  for (final raw in const LineSplitter().convert(master)) {
    final line = raw.trim();
    if (line.startsWith('#EXT-X-STREAM-INF:')) {
      pending = line;
      continue;
    }
    if (line.isEmpty) continue;
    if (line.startsWith('#')) {
      if (line == '#EXTM3U' || line.startsWith('#EXT-X-VERSION:')) {
        out.add(line);
      }
      continue;
    }
    if (line == quality.path && pending != null) {
      out
        ..add(pending)
        ..add(line);
    }
    pending = null;
  }
  if (!out.contains('#EXTM3U')) out.insert(0, '#EXTM3U');
  if (!out.contains(quality.path)) {
    throw const FormatException('The quality is not in the master playlist');
  }
  return '${out.join('\n')}\n';
}
