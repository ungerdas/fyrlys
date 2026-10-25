import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/fyrlys_source.dart';
import 'package:fyrlys/core/models.dart';
import 'package:fyrlys/core/source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const busyBody = {
  'error': 'Alle 1 tilkoblingene til leverandøren er i bruk (TV 2 HD).',
  'code': 'busy',
  'busy': ['TV 2 HD'],
  'max': 1,
};

void main() {
  test('adressen gjøres om til en full lenke', () {
    expect(FyrlysSource.normalize('192.168.1.10:8766'), 'http://192.168.1.10:8766');
    expect(FyrlysSource.normalize('https://tv.example.no/'), 'https://tv.example.no');
    expect(() => FyrlysSource.normalize(''), throwsA(isA<SourceException>()));
  });

  test('kobler til, henter alle sidene, og «ta over» bare i første forespørsel', () async {
    final calls = <String>[];
    var busy = true;
    final client = MockClient((req) async {
      calls.add('${req.method} ${req.url.path}?${req.url.query}');
      final p = req.url.path;
      if (p == '/api/streams/info') return json({'name': 'Fyrlys', 'ffmpeg': true});
      if (p == '/api/xtream/status') return json({'linked': true, 'host': 'iptv.example:8080', 'user': 'bob', 'status': 'Active', 'max': 1});
      if (p == '/api/xtream/categories') {
        return json({
          'categories': [
            {'id': '1', 'name': 'Norge', 'count': 250},
          ],
          'total': 250,
        });
      }
      if (p == '/api/xtream/streams') {
        final start = int.parse(req.url.queryParameters['start'] ?? '0');
        return json({
          'items': [
            for (var i = start; i < start + 120 && i < 250; i++)
              {'id': '${1000 + i}', 'name': 'Kanal $i', 'cat': '1', 'icon': i == 0 ? 'http://logo/k0.png' : null, 'num': i + 1, 'epg': true},
          ],
          'total': 250,
          'start': start,
          'page': 120,
        });
      }
      if (p.startsWith('/api/live/') && p.endsWith('/index.m3u8')) {
        if (busy && req.url.queryParameters['force'] != '1') return json(busyBody, 409);
        busy = false;
        return http.Response('#EXTM3U\n', 200);
      }
      if (p.endsWith('/stop')) return http.Response('', 204);
      return http.Response('ukjent', 404);
    });

    final src = await FyrlysSource.connect('192.168.1.10:8766', client: client);
    expect(src.base, 'http://192.168.1.10:8766');
    expect((await src.account()).user, 'bob');

    final chans = await src.channels();
    expect(chans.length, 250);
    expect(chans.first.id, '1000');
    expect(chans.last.id, '1249');
    expect(src.logoUrl(chans.first.icon), 'http://192.168.1.10:8766/api/xtream/img?u=http%3A%2F%2Flogo%2Fk0.png');

    await expectLater(
      src.open(chans.first),
      throwsA(isA<BusyException>().having((e) => e.busy, 'busy', ['TV 2 HD'])),
    );
    final target = await src.open(chans.first, takeOver: true);
    expect(calls.where((c) => c.contains('force=1')), hasLength(1));
    expect(target.urls, ['http://192.168.1.10:8766/api/live/1000/index.m3u8?c=${src.clientId}']);

    await src.close(chans.first);
    expect(calls.last, startsWith('POST /api/live/1000/stop'));
  });

  test('uten ffmpeg på serveren går strømmen rett fra leverandøren via serveren', () async {
    final src = FyrlysSource(base: 'http://fyrlys:8766', client: MockClient((req) async => http.Response('', 404)), ffmpeg: false);
    final target = await src.open(const Channel(id: '7', name: 'Sju'));
    expect(target.urls, ['http://fyrlys:8766/api/xtream/hls/7.m3u8', 'http://fyrlys:8766/api/xtream/file/live/7.ts']);
  });

  test('ikke Fyrlys på adressen', () async {
    final client = MockClient((req) async => http.Response('<html>', 200));
    await expectLater(
      FyrlysSource.connect('example.org', client: client),
      throwsA(isA<SourceException>().having((e) => e.message, 'message', 'Fant ikke Fyrlys på den adressen')),
    );
  });

  test('serveren er ikke logget inn hos leverandøren', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/api/streams/info') return json({'name': 'Fyrlys', 'ffmpeg': true});
      return json({'linked': false});
    });
    await expectLater(FyrlysSource.connect('fyrlys:8766', client: client), throwsA(isA<SourceException>()));
  });

  test('favoritter sendes som endringer, og svaret er hele lista', () async {
    Object? sent;
    final client = MockClient((req) async {
      if (req.method == 'PUT') {
        sent = jsonDecode(req.body);
        return json({
          'favs': [
            {'id': '1', 'name': 'NRK 1', 'icon': null, 'num': 1},
            {'id': '2', 'name': 'TV 2', 'icon': null, 'num': 2},
          ],
          'cats': ['5'],
        });
      }
      return json({'favs': null, 'cats': []});
    });
    final src = FyrlysSource(base: 'http://fyrlys:8766', client: client);
    expect((await src.loadFavorites())!.channels, isEmpty);
    final change = {
      'op': 'add',
      'fav': {'id': '2', 'name': 'TV 2', 'icon': null, 'num': 2},
    };
    final f = await src.changeFavorites(change);
    expect(sent, change);
    expect(f!.channels.map((c) => c.id), ['1', '2']);
    expect(f.categories, ['5']);
  });
}
