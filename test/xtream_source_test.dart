import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/source.dart';
import 'package:fyrlys/core/xtream_source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

String b64(String s) => base64.encode(utf8.encode(s));

void main() {
  group('serveradressen', () {
    test('host:port', () {
      final l = cleanServer('iptv.example:8080');
      expect(l.server, 'http://iptv.example:8080');
      expect(l.user, isNull);
    });

    test('hele M3U-lenken gir server, brukernavn og passord', () {
      final l = cleanServer('http://iptv.example:8080/get.php?username=bob&password=hemmelig&type=m3u_plus');
      expect(l.server, 'http://iptv.example:8080');
      expect(l.user, 'bob');
      expect(l.password, 'hemmelig');
    });

    test('tom adresse', () {
      expect(() => cleanServer('  '), throwsA(isA<SourceException>()));
    });
  });

  test('EPG-tekst er base64, ellers brukes den som den er', () {
    expect(decodeBase64Text(b64('Dagsrevyen')), 'Dagsrevyen');
    expect(decodeBase64Text('Vanlig tekst!'), 'Vanlig tekst!');
    expect(decodeBase64Text(null), '');
  });

  test('innlogging, kanaler, EPG og strømadresser', () async {
    final client = MockClient((req) async {
      expect(req.headers['User-Agent'], xtreamUserAgent);
      final q = req.url.queryParameters;
      if (q['username'] != 'bob' || q['password'] != 'hemmelig') {
        return json({
          'user_info': {'auth': 0},
        });
      }
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      switch (q['action']) {
        case null:
          return json({
            'user_info': {'auth': 1, 'status': 'Active', 'exp_date': '1893456000', 'max_connections': '1', 'active_cons': '0'},
          });
        case 'get_live_categories':
          return json([
            {'category_id': '1', 'category_name': 'Norge'},
          ]);
        case 'get_live_streams':
          return json([
            {'num': 1, 'name': 'NRK 1 HD', 'stream_id': 101, 'stream_icon': 'http://logo/nrk1.png', 'epg_channel_id': 'nrk1', 'category_id': '1'},
            {'num': 2, 'name': 'Uten id'},
            {'num': '3', 'name': ' TV 2 ', 'stream_id': '102', 'stream_icon': '', 'epg_channel_id': null, 'category_id': 1},
          ]);
        case 'get_short_epg':
          return json({
            'epg_listings': [
              {'title': b64('Senere'), 'start_timestamp': '${now + 600}', 'stop_timestamp': '${now + 1200}'},
              {'title': b64('Dagsrevyen'), 'description': b64('Nyheter'), 'start_timestamp': '${now - 600}', 'stop_timestamp': '${now + 600}'},
              {'title': b64('Ferdig'), 'start_timestamp': '${now - 7200}', 'stop_timestamp': '${now - 3600}'},
            ],
          });
      }
      return json([]);
    });
    final src = await XtreamSource.login('iptv.example:8080', 'bob', 'hemmelig', client: client);

    final account = await src.account();
    expect(account.status, 'Active');
    expect(account.maxConnections, 1);
    expect(account.expires, isNotNull);

    expect((await src.categories()).single.name, 'Norge');

    final chans = await src.channels();
    expect(chans.map((c) => c.id), ['101', '102']);
    expect(chans.first.icon, 'http://logo/nrk1.png');
    expect(chans.first.hasEpg, isTrue);
    expect(chans[1].name, 'TV 2');
    expect(chans[1].icon, isNull);
    expect(chans[1].hasEpg, isFalse);
    expect(chans[1].categoryId, '1');

    final epg = await src.epg('101');
    expect(epg.map((e) => e.title), ['Dagsrevyen', 'Senere']);
    expect(epg.first.description, 'Nyheter');

    final target = await src.open(chans.first);
    expect(target.urls, [
      'http://iptv.example:8080/live/bob/hemmelig/101.m3u8',
      'http://iptv.example:8080/live/bob/hemmelig/101.ts',
    ]);
    expect(src.toPrefs(), {'kind': 'xtream', 'server': 'http://iptv.example:8080', 'user': 'bob', 'password': 'hemmelig'});
  });

  test('feil passord', () async {
    final client = MockClient((req) async => json({
          'user_info': {'auth': 0},
        }));
    await expectLater(
      XtreamSource.login('iptv.example', 'bob', 'feil', client: client),
      throwsA(isA<SourceException>().having((e) => e.message, 'message', 'Feil brukernavn eller passord')),
    );
  });

  test('ingen kontakt med serveren', () async {
    final client = MockClient((req) async => throw http.ClientException('nede'));
    await expectLater(
      XtreamSource.login('iptv.example', 'bob', 'x', client: client),
      throwsA(isA<SourceException>().having((e) => e.message, 'message', contains('kontakt'))),
    );
  });

  test('serveren svarer ikke med JSON', () async {
    final client = MockClient((req) async => http.Response('<html>hei</html>', 200));
    await expectLater(
      XtreamSource.login('iptv.example', 'bob', 'x', client: client),
      throwsA(isA<SourceException>().having((e) => e.message, 'message', contains('Xtream'))),
    );
  });
}
