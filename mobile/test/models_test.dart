import 'package:anilab/core/utils/formatters.dart';
import 'package:anilab/data/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Model parsing (kontrak Projectnext)', () {
    test('SearchResponse agregat dengan errors', () {
      final res = SearchResponse.fromJson({
        'query': 'naruto',
        'count': 1,
        'results': [
          {
            'provider': 'gogo',
            'id': 'naruto',
            'title': 'Naruto',
            'url': 'https://example.com/category/naruto',
            'image': 'https://example.com/naruto.jpg',
            'releaseDate': 'Released: 2002',
          }
        ],
        'errors': [
          {'provider': 'samehadaku', 'message': 'Semua mirror gagal'}
        ],
      });
      expect(res.count, 1);
      expect(res.results.first.key, 'gogo/naruto');
      expect(yearOf(res.results.first.releaseDate), '2002');
      expect(res.errors.single.provider, 'samehadaku');
    });

    test('AnimeInfo: episode diurutkan & tetangga', () {
      final info = AnimeInfo.fromJson({
        'provider': 'gogo',
        'id': 'naruto',
        'title': 'Naruto',
        'url': '',
        'image': '',
        'totalEpisodes': 3,
        'episodes': [
          {'id': 'naruto-episode-3', 'number': 3, 'url': ''},
          {'id': 'naruto-episode-1', 'number': 1, 'url': ''},
          {'id': 'naruto-episode-2', 'number': 2, 'url': ''},
        ],
      });
      expect(info.firstEpisode?.number, 1);
      expect(info.latestEpisode?.number, 3);
      expect(info.neighbour('naruto-episode-2', 1)?.id, 'naruto-episode-3');
      expect(info.neighbour('naruto-episode-3', 1), isNull);
      expect(info.episodes.first.label, '03');
    });

    test('WatchData: hls diprioritaskan, embed dikenali', () {
      final w = WatchData.fromJson({
        'provider': 'gogo',
        'episodeId': 'naruto-episode-1',
        'headers': {'Referer': 'https://embed.example/'},
        'sources': [
          {'url': 'https://cdn/x.mp4', 'type': 'mp4', 'quality': '720p'},
          {'url': 'https://cdn/x.m3u8', 'type': 'hls', 'quality': 'auto'},
          {'url': 'https://embed/x', 'type': 'embed', 'quality': 'default', 'isEmbed': true},
        ],
        'subtitles': [
          {'url': 'https://cdn/en.vtt', 'lang': 'en', 'label': 'English'}
        ],
      });
      expect(w.bestSource?.isHls, isTrue);
      expect(w.playableSources.length, 2);
      expect(w.referer, 'https://embed.example/');
      expect(w.subtitles.single.display, 'English');
    });

    test('DownloadGroup toleran terhadap field hilang', () {
      final g = DownloadGroup.fromJson({
        'resolution': '1080p',
        'links': [
          {'server': 'Mega', 'url': 'https://mega.nz/x'},
          {'server': 'Torrent', 'url': 'magnet:?xt=urn:btih:abc'},
        ],
      });
      expect(g.title, '1080p');
      expect(g.links.last.isMagnet, isTrue);
      expect(resolutionRank(g.resolution), 1080);
    });
  });

  group('Formatter', () {
    test('formatDuration', () {
      expect(formatDuration(const Duration(seconds: 59)), '0:59');
      expect(formatDuration(const Duration(minutes: 12, seconds: 5)), '12:05');
      expect(formatDuration(const Duration(hours: 2, minutes: 18, seconds: 39)), '2:18:39');
    });

    test('parseLooseDate berbagai format', () {
      expect(parseLooseDate('2026-10-14')?.day, 14);
      expect(parseLooseDate('14 Oktober 2026')?.month, 10);
      expect(parseLooseDate('October 14, 2026')?.year, 2026);
      expect(parseLooseDate('14/10/2026')?.month, 10);
      expect(parseLooseDate('kapan-kapan'), isNull);
    });

    test('hostOf & cleanScore', () {
      expect(hostOf('https://www.mega.nz/file/abc'), 'mega.nz');
      expect(hostOf('magnet:?xt=urn:btih:abc'), 'magnet');
      expect(cleanScore('Rating 8,7 / 10'), '8.7');
    });
  });
}
