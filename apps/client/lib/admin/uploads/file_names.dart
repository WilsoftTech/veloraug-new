/// Reading a video file's name for the upload screen: the title, year,
/// season and episode, and the VJ.
///
/// The naming guide, also shown on the screen:
///
///     VJ Junior - Commando (1985).mp4
///     VJ Junior - Prison Break S01E02.mp4
///
/// Names in other styles, such as "Fast.X.2023.VJ.Junior.Luganda.mp4", are
/// read as well as they can be, and the admin checks every row before
/// uploading.
library;

import '../../api/admin_api.dart' show AdminVj;

/// The file types the upload screen accepts. FFprobe decides later whether
/// the file is really a video it can use.
const Set<String> videoExtensions = {
  'mp4', 'm4v', 'mkv', 'mov', 'avi', 'webm', 'ts', 'm2ts', 'mpg', 'mpeg', //
  'wmv', 'flv', '3gp',
};

/// tusd's -max-size, and the upload hooks' limit.
const int maxVideoBytes = 50 * 1024 * 1024 * 1024;

bool isVideoFileName(String name) {
  final dot = name.lastIndexOf('.');
  return dot > 0 &&
      videoExtensions.contains(name.substring(dot + 1).toLowerCase());
}

class ParsedName {
  const ParsedName({
    required this.title,
    this.year,
    this.season,
    this.episode,
    this.vj,
  });

  /// The title as the VJ's edition is known. Empty when nothing was left.
  final String title;
  final int? year;
  final int? season;
  final int? episode;

  /// The VJ's name as the file gives it, such as "VJ Junior".
  final String? vj;

  bool get isEpisode => season != null && episode != null;
}

/// Words describing a file rather than the film, dropped from the title.
final RegExp _noise = RegExp(
  r'\b(luganda|translated|full ?movie|hd|hdrip|hdtv|web[ -]?dl|webrip|bluray|'
  r'brrip|dvdrip|x264|x265|h264|h265|hevc|aac|mp3|\d{3,4}p)\b',
  caseSensitive: false,
);

/// "VJ Junior - Title": the guide's style, VJ first.
final RegExp _vjFirst = RegExp(
  r'^\s*(vj\s+[^\s-][^-]*?)\s+-\s+(.+)$',
  caseSensitive: false,
);

/// "[VJ Junior]" or "(VJ Junior)" anywhere.
final RegExp _vjBracket = RegExp(
  r'[\[(]\s*(vj\s+[^\])]+?)\s*[\])]',
  caseSensitive: false,
);

/// "VJ Junior" anywhere: "VJ" and the one word after it.
final RegExp _vjWord = RegExp(r'\bvj\s+([a-z0-9]+)', caseSensitive: false);

final RegExp _episode = RegExp(
  r'\bs(\d{1,3})\s*[ .-]?\s*e(\d{1,4})\b',
  caseSensitive: false,
);

final RegExp _yearBracketed = RegExp(r'[(\[]\s*((?:19|20)\d{2})\s*[)\]]');
final RegExp _yearBare = RegExp(r'\b((?:19|20)\d{2})\b');

/// Reads [fileName]. [knownVjs] are matched first, by name or other
/// spelling, so "VJ Ice P" is found whole even without the guide's style.
ParsedName parseVideoName(
  String fileName, {
  Iterable<AdminVj> knownVjs = const [],
}) {
  var text = fileName.replaceAll('\\', '/').split('/').last;
  final dot = text.lastIndexOf('.');
  if (dot > 0 && text.length - dot <= 6) text = text.substring(0, dot);
  // Scene-style names use dots or underscores for spaces.
  if (!text.contains(' ')) text = text.replaceAll(RegExp(r'[._]+'), ' ');
  text = text.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  String? vj;
  final first = _vjFirst.firstMatch(text);
  if (first != null) {
    vj = first[1]!.trim();
    text = first[2]!;
  } else {
    final bracket = _vjBracket.firstMatch(text);
    if (bracket != null) {
      vj = bracket[1]!.trim();
      text = text.replaceRange(bracket.start, bracket.end, ' ');
    } else {
      final known = _findKnown(text, knownVjs);
      if (known != null) {
        vj = known.$1;
        text = text.replaceRange(known.$2, known.$3, ' ');
      } else {
        final word = _vjWord.firstMatch(text);
        if (word != null) {
          vj = 'VJ ${word[1]}';
          text = text.replaceRange(word.start, word.end, ' ');
        }
      }
    }
  }

  int? season;
  int? episode;
  final ep = _episode.firstMatch(text);
  if (ep != null) {
    season = int.parse(ep[1]!);
    episode = int.parse(ep[2]!);
    // Anything after the numbers is the episode's own title or noise.
    text = text.substring(0, ep.start);
  }

  int? year;
  final bracketed = _yearBracketed.firstMatch(text);
  if (bracketed != null) {
    year = int.parse(bracketed[1]!);
    text = text.substring(0, bracketed.start);
  } else {
    // The last bare year, unless it is the whole title, as in "1917".
    final bare = _yearBare.allMatches(text).toList();
    if (bare.isNotEmpty) {
      final last = bare.last;
      final before = text.substring(0, last.start).trim();
      if (before.isNotEmpty) {
        year = int.parse(last[1]!);
        text = before;
      }
    }
  }

  text = text
      .replaceAll(_noise, ' ')
      .replaceAll(RegExp(r'[\[\]()]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAll(RegExp(r'^[\s\-–:]+|[\s\-–:]+$'), '')
      .trim();
  return ParsedName(
    title: _tidyTitle(text),
    year: year,
    season: season,
    episode: episode,
    vj: vj == null ? null : _tidyVj(vj),
  );
}

/// Short words whose dot belongs to them, as in "Mr. Bean".
const Set<String> _abbreviations = {
  'mr', 'mrs', 'ms', 'dr', 'st', 'jr', 'sr', 'vs', 'vol', 'no', //
};

/// I to XXXIX: sequel numbers. Not "CIVIL" or "MIX".
final RegExp _roman = RegExp(r'^(?=[IVX])X{0,3}(IX|IV|V?I{0,3})$');

/// Drops dots left over from file names, such as in
/// "THE PURGE 4 .THE FIRST PURGE.", and turns a title written all in capitals
/// into ordinary capitals. Roman numerals, such as "II", stay capitals.
String _tidyTitle(String title) {
  final words = <String>[];
  for (var word in title.split(' ')) {
    word = word.replaceFirst(RegExp(r'^\.+'), '');
    final bare = word.replaceFirst(RegExp(r'\.+$'), '');
    if (!_abbreviations.contains(bare.toLowerCase())) word = bare;
    if (word.isNotEmpty) words.add(word);
  }
  final shouting =
      RegExp('[A-Z]').hasMatch(title) && !RegExp('[a-z]').hasMatch(title);
  return [
    for (final word in words)
      shouting && !_roman.hasMatch(word)
          ? word[0] + word.substring(1).toLowerCase()
          : word,
  ].join(' ').replaceAll(RegExp(r'^[\s\-–:]+|[\s\-–:]+$'), '').trim();
}

String _tidyVj(String name) {
  final words = name.trim().split(RegExp(r'\s+'));
  return [
    'VJ',
    for (final word in words.skip(1))
      word.isEmpty ? word : word[0].toUpperCase() + word.substring(1),
  ].join(' ');
}

/// A VJ name compared loosely: lower case, letters and digits only, without
/// a leading "vj". "VJ Ice-P" and "vj iceP" are the same.
String vjKey(String name) {
  final compact = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return compact.startsWith('vj') ? compact.substring(2) : compact;
}

/// The known VJ whose name or other spelling is [name], if exactly one is.
AdminVj? matchKnownVj(String? name, Iterable<AdminVj> knownVjs) {
  if (name == null) return null;
  final key = vjKey(name);
  if (key.isEmpty) return null;
  final found = {
    for (final vj in knownVjs)
      if (vjKey(vj.name) == key || vj.matchNames.any((m) => vjKey(m) == key))
        vj.id: vj,
  };
  return found.length == 1 ? found.values.single : null;
}

/// The longest known VJ name in [text], as (the text found, start, end).
(String, int, int)? _findKnown(String text, Iterable<AdminVj> knownVjs) {
  final names = [
    for (final vj in knownVjs) ...[vj.name, ...vj.matchNames],
  ]..sort((a, b) => b.length.compareTo(a.length));
  final lower = text.toLowerCase();
  for (final name in names) {
    final words = name.toLowerCase().trim().split(RegExp(r'[\s._-]+'));
    if (words.isEmpty || words.first.isEmpty) continue;
    final pattern = RegExp(
      r'\b' + words.map(RegExp.escape).join(r'[\s._-]*') + r'\b',
    );
    final match = pattern.firstMatch(lower);
    if (match != null) {
      return (text.substring(match.start, match.end), match.start, match.end);
    }
  }
  return null;
}

/// A title compared loosely, for finding the series an episode belongs to.
String titleKey(String title) =>
    title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
