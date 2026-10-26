import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/vod.dart';
import 'package:fyrlys/core/xtream_source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

const _items = [
  VodItem(id: '1', name: 'Bølgen', categoryId: 'a', added: 5),
  VodItem(id: '2', name: 'Anna', categoryId: 'b', added: 9),
  VodItem(id: '3', name: 'Cirkus Bølgen', categoryId: 'a', added: 1),
];

void main() {
  group('lister', () {
    test('kategori, søk og sortering, som på serveren', () {
      expect(pageOf(_items, category: 'a').items.map((i) => i.id), ['1', '3']);
      expect(pageOf(_items, query: 'bølgen').items.map((i) => i.id), ['1', '3']);
      expect(pageOf(_items, query: 'cirkus bølgen').total, 1);
      expect(pageOf(_items, sort: VodSort.name).items.map((i) => i.name), ['Anna', 'Bølgen', 'Cirkus Bølgen']);
      expect(pageOf(_items, sort: VodSort.newest).items.map((i) => i.id), ['2', '1', '3']);
    });

    test('sider à 120', () {
      final many = [for (var i = 0; i < 250; i++) VodItem(id: '$i', name: 'Film $i')];
      final second = pageOf(many, start: 120);
      expect(second.items.length, 120);
      expect(second.items.first.id, '120');
      expect(second.total, 250);
      expect(pageOf(many, start: 240).items.length, 10);
      expect(pageOf(many, start: 999).items, isEmpty);
    });

    test('kategoriene får antall, og tomme tas bort', () {
      final c = catalogOf(
        const [VodCategory(id: 'a', name: 'A'), VodCategory(id: 'b', name: 'B'), VodCategory(id: 'c', name: 'Tom')],
        _items,
      );
      expect(c.categories.map((x) => '${x.name}:${x.count}'), ['A:2', 'B:1']);
      expect(c.total, 3);
    });

    test('titler uten merker, episodetitler uten koden, spilletid og kvalitet', () {
      final c = cleanTitle('Matchbox the Movie [PRE] [2026]');
      expect(c.title, 'Matchbox the Movie');
      expect(c.tags, ['PRE']);
      expect(c.year, '2026');
      expect(cleanTitle('Fyrlyset').title, 'Fyrlyset');
      expect(cleanTitle('[4K]').title, '[4K]');
      expect(cleanTitle('Film (2019) [MULTI]').tags, ['MULTI']);

      expect(episodeTitle('9-1-1 - S01E01 - Pilot'), 'Pilot');
      expect(episodeTitle('S01E02 Let Go'), 'Let Go');
      expect(episodeTitle('9-1-1 - S01E03'), '');
      expect(episodeTitle('Kystvakten - Første', series: 'Kystvakten'), 'Første');
      expect(episodeTitle('Første'), 'Første');

      expect(runtimeText(7567), '2 t 6 min');
      expect(runtimeText(0, '00:43:11'), '43 min');
      expect(runtimeText(0, '02:00:00'), '2 t');
      expect(runtimeText(0, ''), '');

      expect(const MediaTech(height: 2160, videoCodec: 'hevc', hdr: true, audioCodec: 'eac3', channels: 6).badges,
          ['4K', 'HDR', 'H.265', '5.1', 'Dolby Digital+']);
      expect(const MediaTech(height: 1080, videoCodec: 'h264', audioCodec: 'aac', channels: 2).badges,
          ['1080p', 'H.264', 'Stereo']);
      expect(const MediaTech().badges, isEmpty);
    });

    test('episodekode og vurdering', () {
      expect(episodeCode('1', 2), 'S01E02');
      expect(episodeCode('Spesial', 2), '');
      expect(episodeCode('3', null), '');
      expect(ratingText(7.5), '★ 7,5');
      expect(ratingText(8), '★ 8');
      expect(ratingText(null), '');
      expect(ratingText(0), '');
    });
  });

  group('leverandøren direkte', () {
    test('filmer og serier fra player_api.php', () {
      final movies = parseVodItems(VodKind.movies, [
        {'stream_id': 5, 'name': ' Film ', 'category_id': '3', 'stream_icon': 'http://img/a.jpg', 'container_extension': 'MKV', 'rating': '6.8', 'added': '1700000000'},
        {'stream_id': 6, 'name': 'Rar', 'category_id': '3', 'stream_icon': 'ikke-en-lenke', 'container_extension': '../x'},
        {'name': 'uten id'},
      ]);
      expect(movies.length, 2);
      expect(movies.first.name, 'Film');
      expect(movies.first.ext, 'mkv');
      expect(movies.first.rating, 6.8);
      expect(movies.first.added, 1700000000);
      expect(movies.last.icon, isNull);
      expect(movies.last.ext, 'mp4');

      final series = parseVodItems(VodKind.series, [
        {'series_id': 9, 'name': 'Serie', 'category_id': '4', 'cover': 'http://img/s.jpg', 'releaseDate': '2021-05-01', 'plot': 'Om noe', 'rating': 7},
      ]);
      expect(series.single.year, '2021');
      expect(series.single.icon, 'http://img/s.jpg');
    });

    test('filminfo og serieinfo med bakgrunnsbilde og kvalitet', () {
      final info = {
        'backdrop_path': ['', 'https://img/bak.jpg'],
        'video': {'codec_name': 'hevc', 'height': 2160, 'color_transfer': 'smpte2084'},
        'audio': {'codec_name': 'eac3', 'channels': 6},
      };
      expect(firstBackdrop(info), 'https://img/bak.jpg');
      expect(firstBackdrop({'backdrop_path': 'http://img/b.jpg'}), 'http://img/b.jpg');
      expect(firstBackdrop({}), isNull);
      expect(mediaTech(info).badges, ['4K', 'HDR', 'H.265', '5.1', 'Dolby Digital+']);
      final series = parseSeriesInfo({
        'info': {'name': 'S', 'backdrop_path': ['http://img/s.jpg'], 'cast': 'A', 'director': 'B'},
        'episodes': {
          '1': [
            {'id': '1', 'episode_num': 1, 'title': 'S - S01E01 - Pilot', 'info': {'duration_secs': 2591}},
          ],
        },
      });
      expect(series.backdrop, 'http://img/s.jpg');
      expect(series.cast, 'A');
      expect(series.seasons.single.episodes.single.seconds, 2591);
    });

    test('sesonger som kart eller som liste', () {
      final asMap = parseSeriesInfo({
        'info': {'name': 'Serie', 'releaseDate': '2020-01-01', 'rating': '7.1'},
        'episodes': {
          '2': [
            {'id': '22', 'episode_num': 1, 'title': 'S2E1', 'container_extension': 'mp4'},
          ],
          '1': [
            {'id': '11', 'episode_num': '1', 'title': 'S1E1', 'container_extension': 'mkv', 'info': {'plot': 'Start', 'duration': '00:40:00', 'movie_image': 'http://img/1.jpg'}},
            {'id': '12', 'episode_num': 2, 'title': 'S1E2', 'container_extension': 'mkv'},
          ],
        },
      });
      expect(asMap.seasons.map((s) => s.number), ['1', '2']);
      expect(asMap.seasons.first.episodes.first.image, 'http://img/1.jpg');
      expect(asMap.seasons.first.episodes.first.number, 1);
      expect(asMap.year, '2020');
      expect(asMap.rating, 7.1);

      final asList = parseSeriesInfo({
        'info': {'name': 'Serie'},
        'episodes': [
          [
            {'id': '1', 'episode_num': 1, 'title': 'A'},
          ],
          [
            {'id': '2', 'episode_num': 1, 'title': 'B'},
          ],
        ],
      });
      expect(asList.seasons.map((s) => s.number), ['1', '2']);
    });

    test('lister lastes én gang, filtreres i appen, og filene har riktige adresser', () async {
      var listCalls = 0;
      final client = MockClient((req) async {
        final action = req.url.queryParameters['action'];
        if (action == 'get_vod_categories') {
          return json([
            {'category_id': '3', 'category_name': 'Action'},
          ]);
        }
        if (action == 'get_vod_streams') {
          listCalls++;
          return json([
            {'stream_id': 5, 'name': 'Fyrlyset', 'category_id': '3', 'container_extension': 'mkv'},
            {'stream_id': 6, 'name': 'Nordlys', 'category_id': '3', 'container_extension': 'mp4'},
          ]);
        }
        if (action == 'get_vod_info') return json({'info': {'plot': 'Om et fyr', 'releasedate': '2024-02-02'}});
        return json({}, 404);
      });
      final src = XtreamSource(server: 'http://iptv.example:8080', user: 'bob', password: 'hemmelig', client: client);
      expect((await src.vodCatalog(VodKind.movies)).categories.single.count, 2);
      final page = await src.vodPage(VodKind.movies, query: 'nord');
      expect(page.items.single.name, 'Nordlys');
      expect(listCalls, 1);
      expect(src.movieUrl(page.items.single), 'http://iptv.example:8080/movie/bob/hemmelig/6.mp4');
      expect((await src.movieInfo('5')).year, '2024');
      expect(src.episodeUrl(const Episode(id: '7', title: 'x', ext: 'mkv')), 'http://iptv.example:8080/series/bob/hemmelig/7.mkv');
    });
  });
}
