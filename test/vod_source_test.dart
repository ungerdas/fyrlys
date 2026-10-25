import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/fyrlys_source.dart';
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

  test('Fyrlys-serveren: lister, info og filer', () async {
    final calls = <String>[];
    final client = MockClient((req) async {
      calls.add('${req.url.path}?${req.url.query}');
      final p = req.url.path;
      final q = req.url.queryParameters;
      if (p == '/api/xtream/categories') {
        return json({
          'categories': [
            {'id': '11', 'name': 'Action', 'count': 2},
          ],
          'total': 2,
        });
      }
      if (p == '/api/xtream/streams' && q['kind'] == 'vod') {
        return json({
          'items': [
            {'id': '201', 'name': 'Fyrlyset', 'cat': '11', 'icon': 'http://img/p.jpg', 'ext': 'mkv', 'rating': 7.5, 'added': 3},
            {'id': '202', 'name': 'Nordlys', 'cat': '11', 'icon': null, 'ext': 'mp4', 'rating': null, 'added': 1},
          ],
          'total': 2,
          'start': 0,
          'page': 120,
        });
      }
      if (p == '/api/xtream/vod') return json({'plot': 'Om et fyr.', 'genre': 'Drama', 'year': '2024', 'duration': '01:45:00'});
      if (p == '/api/xtream/series') {
        return json({
          'name': 'Kystvakten',
          'cover': 'http://img/c.jpg',
          'plot': 'Kysten.',
          'genre': '',
          'year': '2023',
          'rating': 8,
          'seasons': [
            {
              'season': '1',
              'episodes': [
                {'id': '401', 'ep': 1, 'title': 'Første', 'ext': 'mkv', 'img': null, 'plot': 'Start.', 'duration': '00:45:00'},
                {'id': '402', 'ep': '2', 'title': 'Andre', 'ext': 'mp4', 'img': 'http://img/e.jpg', 'plot': '', 'duration': null},
              ],
            },
          ],
        });
      }
      return json({'error': 'nei'}, 404);
    });
    final src = FyrlysSource(base: 'http://192.168.1.10:8766', client: client);

    final cat = await src.vodCatalog(VodKind.movies);
    expect(cat.categories.single.name, 'Action');
    expect(cat.total, 2);

    final page = await src.vodPage(VodKind.movies, category: '11', query: 'fyr lys', sort: VodSort.newest, start: 0);
    expect(calls.last, '/api/xtream/streams?kind=vod&cat=11&q=fyr+lys&sort=added&start=0');
    expect(page.total, 2);
    expect(page.items.first.ext, 'mkv');
    expect(page.items.first.rating, 7.5);
    expect(page.items.last.icon, isNull);
    expect(src.movieUrl(page.items.first), 'http://192.168.1.10:8766/api/xtream/file/vod/201.mkv');

    expect((await src.movieInfo('201')).plot, 'Om et fyr.');

    final info = await src.seriesInfo('301');
    expect(info.seasons.single.episodes.map((e) => e.number), [1, 2]);
    expect(info.seasons.single.episodes.last.image, 'http://img/e.jpg');
    expect(info.seasons.single.episodes.last.duration, '');
    expect(src.episodeUrl(info.seasons.single.episodes.first), 'http://192.168.1.10:8766/api/xtream/file/series/401.mkv');
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
