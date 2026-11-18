import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/admin/uploads/file_names.dart';
import 'package:veloraug/api/admin_api.dart';

const junior = AdminVj(id: 'v1', name: 'VJ Junior', slug: 'vj-junior');
const iceP = AdminVj(
  id: 'v2',
  name: 'VJ Ice P',
  slug: 'vj-ice-p',
  matchNames: ['VJ IceP'],
);

void main() {
  group('the naming guide', () {
    test('a movie', () {
      final name = parseVideoName('VJ Junior - Commando (1985).mp4');
      expect(name.vj, 'VJ Junior');
      expect(name.title, 'Commando');
      expect(name.year, 1985);
      expect(name.isEpisode, isFalse);
    });

    test('an episode', () {
      final name = parseVideoName('VJ Junior - Prison Break S01E02.mkv');
      expect(name.vj, 'VJ Junior');
      expect(name.title, 'Prison Break');
      expect((name.season, name.episode), (1, 2));
      expect(name.year, isNull);
    });

    test('a VJ of two words', () {
      final name = parseVideoName('VJ Ice P - The Equalizer 3 (2023).mp4');
      expect(name.vj, 'VJ Ice P');
      expect(name.title, 'The Equalizer 3');
      expect(name.year, 2023);
    });
  });

  group('other styles', () {
    test('scene style, with dots and noise words', () {
      final name = parseVideoName(
        'Fast.X.2023.VJ.Junior.Luganda.720p.mp4',
        knownVjs: [junior],
      );
      expect(name.vj, 'VJ Junior');
      expect(name.title, 'Fast X');
      expect(name.year, 2023);
    });

    test('the VJ in brackets', () {
      final name = parseVideoName('Kabaka s2e10 [vj emmy].mp4');
      expect(name.vj, 'VJ Emmy');
      expect(name.title, 'Kabaka');
      expect((name.season, name.episode), (2, 10));
    });

    test('a known VJ is found whole, by another spelling', () {
      final name = parseVideoName(
        'John Wick 4 VJ IceP translated.mp4',
        knownVjs: [junior, iceP],
      );
      expect(matchKnownVj(name.vj, [junior, iceP]), iceP);
      expect(name.title, 'John Wick 4');
    });

    test('an unknown VJ is "VJ" and one word', () {
      final name = parseVideoName('Rambo VJ Kevo HD.mp4');
      expect(name.vj, 'VJ Kevo');
      expect(name.title, 'Rambo');
    });

    test('a title that is a year stays a title', () {
      expect(parseVideoName('VJ Junior - 1917.mp4').title, '1917');
      expect(parseVideoName('VJ Junior - 1917 (2019).mp4').year, 2019);
    });

    test('stray dots go, and capitals become ordinary', () {
      const ice = AdminVj(id: 'v4', name: 'VJ ICE P', slug: 'vj-ice-p');
      final four = parseVideoName(
        'THE PURGE 4 .THE FIRST PURGE. VJ ICE P.mkv',
        knownVjs: [ice],
      );
      expect(four.title, 'The Purge 4 The First Purge');
      expect(matchKnownVj(four.vj, [ice]), ice);
      expect(
        parseVideoName(
          'THE PURGE 5 .THE FOREVER PURGE.VJ ICE P.mkv',
          knownVjs: [ice],
        ).title,
        'The Purge 5 The Forever Purge',
      );
      expect(parseVideoName('VJ Junior - ROCKY II.mp4').title, 'Rocky II');
      expect(parseVideoName('VJ Junior - CIVIL WAR.mp4').title, 'Civil War');
      expect(parseVideoName('VJ Junior - Mr. Bean.mp4').title, 'Mr. Bean');
      expect(
        parseVideoName('VJ Junior - iPhone Story.mp4').title,
        'iPhone Story',
      );
    });

    test('no VJ and nothing else', () {
      final name = parseVideoName('holiday.mp4');
      expect(name.vj, isNull);
      expect(name.title, 'holiday');
    });
  });

  test('VJ names match loosely, and only one VJ', () {
    expect(matchKnownVj('vj junior', [junior, iceP]), junior);
    expect(matchKnownVj('VJ Ice-P', [junior, iceP]), iceP);
    expect(matchKnownVj('VJ Emmy', [junior, iceP]), isNull);
    expect(matchKnownVj(null, [junior]), isNull);
    const twin = AdminVj(
      id: 'v3',
      name: 'VJ Junior Two',
      slug: 'x',
      matchNames: ['VJ Junior'],
    );
    expect(matchKnownVj('VJ Junior', [junior, twin]), isNull);
  });

  test('only video files are taken', () {
    expect(isVideoFileName('a.MP4'), isTrue);
    expect(isVideoFileName('a.mkv'), isTrue);
    expect(isVideoFileName('notes.txt'), isFalse);
    expect(isVideoFileName('mp4'), isFalse);
  });
}
