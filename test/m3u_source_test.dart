import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/m3u_source.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/core/source.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _m3u = '''
#EXTM3U url-tvg="http://epg.example/guide.xml.gz"
#EXTINF:-1 tvg-id="nrk1.no" tvg-name="NRK1" tvg-logo="http://logo.example/nrk1.png" group-title="Norge",NRK 1 HD
http://iptv.example/live/kari/hemmelig/101.m3u8
#EXTINF:-1 tvg-id="" tvg-name="TV 2" group-title="Norge, TV",TV 2 HD
http://iptv.example/live/kari/hemmelig/102.ts
#EXTINF:-1,Sport 1
#EXTGRP:Sport
http://iptv.example/live/kari/hemmelig/103.ts
#EXTINF:-1 group-title="Filmer",Fyrlyset (2024)
http://iptv.example/movie/kari/hemmelig/201.mkv
#EXTINF:-1 tvg-chno="7",Uten gruppe
http://iptv.example/7.ts
''';

/// «20261026120000 +0000»
String _t(DateTime d) {
  final u = d.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)} +0000';
}

String _xmltv(DateTime now) {
  String at(int minutes) => _t(now.add(Duration(minutes: minutes)));
  return '''<?xml version="1.0" encoding="UTF-8"?>
<tv>
  <channel id="nrk1.no"><display-name>NRK1</display-name></channel>
  <channel id="tv2.no"><display-name lang="no">TV 2 HD</display-name></channel>
  <programme start="${at(-10)}" stop="${at(20)}" channel="nrk1.no">
    <title lang="no">Dagsrevyen</title>
    <desc lang="no">Nyheter &amp; v&#230;r</desc>
  </programme>
  <programme start="${at(20)}" stop="${at(45)}" channel="nrk1.no"><title><![CDATA[Sport & mer]]></title></programme>
  <programme start="${at(-300)}" stop="${at(-240)}" channel="nrk1.no"><title>Gammelt</title></programme>
  <programme start="${at(-30)}" stop="${at(30)}" channel="tv2.no"><title>Nyhetene</title></programme>
</tv>
''';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('M3U: kanaler, grupper, nummer og EPG-lenken; filmer tas ikke med', () {
    final list = parseM3u(_m3u);
    expect(list.epgUrls, ['http://epg.example/guide.xml.gz']);
    expect(list.skipped, 1);
    expect(list.entries.map((e) => e.name), ['NRK 1 HD', 'TV 2 HD', 'Sport 1', 'Uten gruppe']);
    final nrk = list.entries[0];
    expect(nrk.tvgId, 'nrk1.no');
    expect(nrk.tvgName, 'NRK1');
    expect(nrk.logo, 'http://logo.example/nrk1.png');
    expect(nrk.group, 'Norge');
    expect(nrk.url, 'http://iptv.example/live/kari/hemmelig/101.m3u8');
    // komma inne i anførselstegn hører til gruppa, ikke navnet
    expect(list.entries[1].group, 'Norge, TV');
    expect(list.entries[2].group, 'Sport');
    expect(list.entries[3].number, '7');
    expect(list.entries[3].group, '');
  });

  test('XMLTV: tider med sone, tekst og bare det som er aktuelt', () {
    expect(xmltvTime('20261026120000 +0100'), DateTime.utc(2026, 10, 26, 11).toLocal());
    expect(xmltvTime('202610261200'), DateTime.utc(2026, 10, 26, 12).toLocal());
    expect(xmltvTime('i går'), isNull);
    expect(xmlText('Nyheter &amp; v&#230;r'), 'Nyheter & vær');

    final now = DateTime.now();
    final guide = parseXmltv(_xmltv(now), now);
    expect(guide.names['nrk1'], 'nrk1.no');
    expect(guide.names['tv 2 hd'], 'tv2.no');
    final nrk = guide.programmes['nrk1.no']!;
    expect(nrk.map((p) => p.title), ['Dagsrevyen', 'Sport & mer']);
    expect(nrk.first.description, 'Nyheter & vær');
  });

  group('M3U-kilden', () {
    final now = DateTime.now();
    final requests = <String>[];
    final client = MockClient((r) async {
      requests.add('${r.url}');
      return switch ('${r.url}') {
        'http://iptv.example/liste.m3u' => http.Response.bytes(utf8.encode(_m3u), 200),
        'http://epg.example/guide.xml.gz' => http.Response.bytes(gzip.encode(utf8.encode(_xmltv(now))), 200),
        'http://iptv.example/side.html' => http.Response('<html><body>Hei</body></html>', 200),
        'http://iptv.example/filmer.m3u' => http.Response(
            '#EXTM3U\n#EXTINF:-1,Fyrlyset\nhttp://iptv.example/movie/a/b/1.mp4\n', 200),
        _ => http.Response('mangler', 404),
      };
    });

    test('kanaler og kategorier fra lista, TV-guide fra XMLTV (gzip), og strømmen rett fra leverandøren', () async {
      final src = await M3uSource.connect('iptv.example/liste.m3u', client: client);
      expect(src.url, 'http://iptv.example/liste.m3u');
      expect(src.kind, 'm3u');
      expect(src.label, 'M3U-liste fra iptv.example');
      expect(src.hasVod, isFalse);

      final cats = await src.categories();
      expect(cats.map((c) => c.name), ['Norge', 'Norge, TV', 'Sport', 'Uten kategori']);
      final channels = await src.channels();
      expect(channels.map((c) => c.name), ['NRK 1 HD', 'TV 2 HD', 'Sport 1', 'Uten gruppe']);
      expect(channels.map((c) => c.number), ['1', '2', '3', '7']);
      expect(channels.first.icon, 'http://logo.example/nrk1.png');
      expect(channels.every((c) => c.hasEpg), isTrue);

      // samme id-er neste gang (favoritter og «sist sett»)
      final again = await M3uSource.connect('http://iptv.example/liste.m3u', client: client);
      expect((await again.channels()).map((c) => c.id), channels.map((c) => c.id));
      expect(channels.map((c) => c.id).toSet().length, 4);

      // tvg-id, ellers navnet
      expect((await src.epg(channels[0].id)).map((p) => p.title), ['Dagsrevyen', 'Sport & mer']);
      expect((await src.epg(channels[1].id)).map((p) => p.title), ['Nyhetene']);
      expect(await src.epg(channels[2].id), isEmpty);
      expect(requests.where((u) => u.contains('guide.xml.gz')), hasLength(1));

      final target = await src.open(channels[0]);
      expect(target.urls, ['http://iptv.example/live/kari/hemmelig/101.m3u8']);
      expect(target.localShift, isTrue);
    });

    test('egen EPG-lenke går foran den i lista', () async {
      final src = await M3uSource.connect('http://iptv.example/liste.m3u', epgUrl: 'epg.example/annen.xml', client: client);
      expect(src.epgUrls, ['http://epg.example/annen.xml']);
      final channels = await src.channels();
      // den finnes ikke: ingen programmer, men ingen feil
      expect(await src.epg(channels[0].id), isEmpty);
    });

    test('feil gir en forklaring', () async {
      Future<String> message(String url) async {
        try {
          await M3uSource.connect(url, client: client);
          return 'ingen feil';
        } on SourceException catch (e) {
          return e.message;
        }
      }

      expect(await message('http://iptv.example/side.html'), 'Fant ingen kanaler i lista');
      expect(await message('http://iptv.example/filmer.m3u'), 'Lista har bare filmer og serier, ingen TV-kanaler');
      expect(await message('http://iptv.example/borte.m3u'), 'Serveren svarte HTTP 404 for M3U-lista');
      expect(await message('   '), 'Lim inn M3U-lenken');
    });

    test('brukernavn og passord i lenken vises ikke', () {
      final src = M3uSource(url: 'http://iptv.example/get.php?username=kari&password=hemmelig&type=m3u_plus');
      expect(src.redact('Feil i http://iptv.example/live/kari/hemmelig/1.ts'), 'Feil i http://iptv.example/live/***/***/1.ts');
      expect(src.toPrefs(), {'kind': 'm3u', 'url': src.url, 'epg': ''});
    });
  });

  group('innloggingen', () {
    Future<Session> session([Map<String, Object> prefs = const {}, http.Client? client]) async {
      SharedPreferences.setMockInitialValues(prefs);
      final s = Session(await SharedPreferences.getInstance(), httpClient: client);
      await s.restore();
      return s;
    }

    // en Xtream-server som også gir M3U-lista fra get.php
    http.Response xtream(http.Request r, {bool auth = true}) {
      if (r.url.path.endsWith('player_api.php')) {
        if (r.url.queryParameters['action'] == null) {
          return http.Response(jsonEncode({'user_info': {'auth': auth ? 1 : 0, 'status': 'Active'}}), 200);
        }
        return http.Response('[]', 200);
      }
      if (r.url.path.endsWith('get.php')) return http.Response.bytes(utf8.encode(_m3u), 200);
      return http.Response('mangler', 404);
    }

    test('en Xtream-lenke (get.php) blir Xtream Codes, med filmer og serier', () async {
      final s = await session();
      await http.runWithClient(
        () => s.loginM3u('xt.example:8080/get.php?username=kari&password=hemmelig&type=m3u_plus&output=ts'),
        () => MockClient((r) async => xtream(r)),
      );
      expect(s.source?.kind, 'xtream');
      expect(s.source?.hasVod, isTrue);
      expect(s.source?.label, 'kari på xt.example');
    });

    test('svarer ikke player_api.php som Xtream, leses lista som M3U', () async {
      final s = await session();
      await http.runWithClient(
        () => s.loginM3u('http://xt.example:8080/get.php?username=kari&password=hemmelig&type=m3u_plus'),
        () => MockClient((r) async => xtream(r, auth: false)),
      );
      expect(s.source?.kind, 'm3u');
      expect(s.source?.hasVod, isFalse);
    });

    test('en vanlig M3U-lenke, med EPG-lenke, huskes til neste gang', () async {
      final s = await session();
      await http.runWithClient(
        () => s.loginM3u('http://iptv.example/liste.m3u', epg: 'http://epg.example/guide.xml'),
        () => MockClient((r) async => http.Response.bytes(utf8.encode(_m3u), 200)),
      );
      expect(s.source?.kind, 'm3u');
      final prefs = await SharedPreferences.getInstance();
      expect(jsonDecode(prefs.getString('source')!),
          {'kind': 'm3u', 'url': 'http://iptv.example/liste.m3u', 'epg': 'http://epg.example/guide.xml'});

      final next = Session(prefs);
      await next.restore();
      expect(next.source, isA<M3uSource>());
      expect((next.source! as M3uSource).epgUrl, 'http://epg.example/guide.xml');
      next.source!.dispose();
    });

    test('innlogging mot Fyrlys-serveren fra før: favorittene tas med, og du logger inn på nytt', () async {
      final asked = <String>[];
      final s = await session(
        {'source': jsonEncode({'kind': 'fyrlys', 'base': 'http://192.168.1.10:8766', 'client': 'abc'})},
        MockClient((r) async {
          asked.add('${r.url}');
          return http.Response(
            jsonEncode({
              'favs': [
                {'id': 101, 'name': 'NRK 1 HD', 'icon': 'http://logo.example/nrk1.png', 'num': 1, 'cat': '5'},
              ],
              'cats': ['5', '7'],
            }),
            200,
          );
        }),
      );
      expect(s.source, isNull);
      // oppdateringene kommer rett fra GitHub
      expect(s.updateServer, isNull);
      expect(asked, ['http://192.168.1.10:8766/api/streams/favs']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('source'), isNull);
      final favs = jsonDecode(prefs.getString('favorites')!) as List;
      expect(favs.single, containsPair('id', '101'));
      expect(favs.single, containsPair('num', '1'));
      expect(prefs.getStringList('favoriteCategories'), ['5', '7']);
    });

    test('oppdateringsserveren: adressen ryddes, og tom = ingen', () async {
      final s = await session();
      expect(s.updateServer, isNull);
      await s.saveUpdateServer(' 192.168.1.10:8766/ ');
      expect(s.updateServer, 'http://192.168.1.10:8766');
      await expectLater(s.saveUpdateServer('http://'), throwsA(isA<SourceException>()));
      expect(s.updateServer, 'http://192.168.1.10:8766');
      await s.saveUpdateServer('');
      expect(s.updateServer, isNull);
    });
  });
}
