import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/models.dart';
import 'package:fyrlys/core/source.dart';
import 'package:fyrlys/core/vod.dart';
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

  test('passord med spesialtegn kodes i adressene, og innloggingen vises aldri i feiltekster', () {
    final src = XtreamSource(server: 'http://iptv.example:8080', user: 'bob', password: 'p#ss/1 x');
    expect(src.movieUrl(const VodItem(id: '6', name: 'Film', ext: 'mkv')), 'http://iptv.example:8080/movie/bob/p%23ss%2F1%20x/6.mkv');
    final msg = src.redact('Failed to open http://iptv.example:8080/live/bob/p%23ss%2F1%20x/101.ts.');
    expect(msg, isNot(contains('p%23ss')));
    expect(msg, isNot(contains('/bob/')));
    expect(msg, contains('***'));
    expect(XtreamSource(server: 's', user: 'bob', password: 'hemmelig').redact('?username=bob&password=hemmelig'),
        '?username=***&password=***');
  });

  group('TV-arkivet', () {
    test('serverens klokke fra server_info', () {
      // 20:00 hos serveren da klokka var 19:00 UTC
      final stamp = DateTime.utc(2026, 10, 26, 19).millisecondsSinceEpoch ~/ 1000;
      expect(serverClockOffset({'time_now': '2026-10-26 20:00:07', 'timestamp_now': stamp}), const Duration(hours: 1));
      expect(serverClockOffset({'time_now': '2026-10-26 19:00:00', 'timestamp_now': '$stamp'}), Duration.zero);
      // halvtimer finnes (India): kvarteret nærmest
      expect(serverClockOffset({'time_now': '2026-10-27 00:29:55', 'timestamp_now': stamp}), const Duration(hours: 5, minutes: 30));
      expect(serverClockOffset({'timezone': 'Europe/Oslo'}), isNull);
      expect(serverClockOffset(null), isNull);
    });

    test('starten i serverens tid', () {
      final t = DateTime.utc(2026, 10, 25, 22, 5, 30);
      expect(xtreamTime(t, const Duration(hours: 1)), '2026-10-25:23-05');
      expect(xtreamTime(t, const Duration(hours: 2)), '2026-10-26:00-05');
      expect(xtreamTime(t, Duration.zero), '2026-10-25:22-05');
    });

    test('tidssonen: PC-ens (med sommertid) når serveren går likt, ellers serverens', () {
      final now = DateTime.now();
      final t = now.subtract(const Duration(days: 3));
      expect(archiveOffset(t, null, now: now), t.timeZoneOffset);
      expect(archiveOffset(t, now.timeZoneOffset, now: now), t.timeZoneOffset);
      final other = now.timeZoneOffset + const Duration(hours: 3);
      expect(archiveOffset(t, other, now: now), other);
    });

    test('programmene: de siste dagene, det som går nå, og has_archive', () {
      final now = DateTime(2026, 10, 26, 20, 30);
      int at(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
      Map<String, Object?> p(String title, DateTime a, DateTime b, [Object? has]) => {
            'title': b64(title),
            'description': b64('Om $title'),
            'start_timestamp': '${at(a)}',
            'stop_timestamp': '${at(b)}',
            if (has != null) 'has_archive': has,
          };
      final list = parseArchive({
        'epg_listings': [
          p('Senere', DateTime(2026, 10, 26, 21), DateTime(2026, 10, 26, 22), 0),
          p('Nå', DateTime(2026, 10, 26, 20), DateTime(2026, 10, 26, 21), 0),
          p('I går', DateTime(2026, 10, 25, 20), DateTime(2026, 10, 25, 21), 1),
          p('Uten merke', DateTime(2026, 10, 25, 18), DateTime(2026, 10, 25, 19)),
          p('Ikke lagret', DateTime(2026, 10, 25, 19), DateTime(2026, 10, 25, 20), '0'),
          p('For gammelt', DateTime(2026, 10, 18, 20), DateTime(2026, 10, 18, 21), 1),
        ],
      }, now: now, days: 7);
      expect(list.map((e) => e.title), ['Uten merke', 'Ikke lagret', 'I går', 'Nå']);
      expect(list.map((e) => e.inArchive), [true, false, true, true]);
      expect(list.first.description, 'Om Uten merke');
      expect(parseArchive(null, now: now, days: 7), isEmpty);
    });

    test('kanaler med arkiv, programmene og adressene', () async {
      final requests = <String>[];
      // serverens klokke går ikke likt med denne maskinen: dens forskjell fra UTC brukes som den er
      final offset = DateTime.now().timeZoneOffset + const Duration(hours: 3);
      final serverNow = DateTime.now().toUtc();
      final wall = serverNow.add(offset);
      String two(int n) => n.toString().padLeft(2, '0');
      final timeNow = '${wall.year}-${two(wall.month)}-${two(wall.day)} ${two(wall.hour)}:${two(wall.minute)}:${two(wall.second)}';
      final client = MockClient((req) async {
        final q = req.url.queryParameters;
        requests.add(q['action'] ?? 'info');
        switch (q['action']) {
          case null:
            return json({
              'user_info': {'auth': 1},
              'server_info': {'timezone': 'Europe/Berlin', 'time_now': timeNow, 'timestamp_now': serverNow.millisecondsSinceEpoch ~/ 1000},
            });
          case 'get_live_streams':
            return json([
              {'name': 'NRK 1', 'stream_id': 101, 'category_id': '1', 'tv_archive': 1, 'tv_archive_duration': '7'},
              {'name': 'TV 2', 'stream_id': 102, 'category_id': '1', 'tv_archive': 0, 'tv_archive_duration': 0},
              {'name': 'Sport', 'stream_id': 103, 'category_id': '1', 'tv_archive': '1'},
            ]);
          case 'get_simple_data_table':
            expect(q['stream_id'], '101');
            final start = DateTime.now().subtract(const Duration(days: 1));
            return json({
              'epg_listings': [
                {
                  'title': b64('Dagsrevyen'),
                  'start_timestamp': '${start.millisecondsSinceEpoch ~/ 1000}',
                  'stop_timestamp': '${start.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000}',
                  'has_archive': 1,
                },
              ],
            });
        }
        return json([]);
      });
      // logget inn fra før (ikke spurt om serveren ennå)
      final src = XtreamSource(server: 'http://iptv.example:8080', user: 'bob', password: 'p#ss', client: client);
      final chans = await src.channels();
      expect(chans.map((c) => c.archiveDays), [7, 0, 1]);
      expect(await src.archive(chans[1]), isEmpty);
      final programs = await src.archive(chans[0]);
      expect(programs.single.title, 'Dagsrevyen');

      // et program fra 18:00:20 til 19:00 UTC
      final program = EpgEntry(
        title: 'Debatten',
        start: DateTime.utc(2026, 10, 20, 18, 0, 20).toLocal(),
        stop: DateTime.utc(2026, 10, 20, 19).toLocal(),
        inArchive: true,
      );
      final clip = await src.archiveClip(chans[0], program);
      expect(requests.where((r) => r == 'info'), hasLength(1));
      expect(clip.length, const Duration(minutes: 59, seconds: 40));
      final fromStart = clip.urlsAt(Duration.zero);
      final start = xtreamTime(DateTime.utc(2026, 10, 20, 18), offset);
      expect(fromStart.urls, [
        'http://iptv.example:8080/timeshift/bob/p%23ss/60/$start/101.m3u8',
        'http://iptv.example:8080/timeshift/bob/p%23ss/60/$start/101.ts',
      ]);
      // strømmen begynner på minuttet, litt før programmet
      expect(fromStart.from, const Duration(seconds: -20));
      final later = clip.urlsAt(const Duration(minutes: 12, seconds: 50));
      expect(later.urls.first,
          'http://iptv.example:8080/timeshift/bob/p%23ss/47/${xtreamTime(DateTime.utc(2026, 10, 20, 18, 13), offset)}/101.m3u8');
      expect(later.from, const Duration(minutes: 12, seconds: 40));
      await expectLater(src.archiveClip(chans[1], program), throwsA(isA<SourceException>()));
    });
  });

  test('IPv6-adresser beholder klammene', () {
    expect(cleanServer('http://[fe80::1]:8080/get.php?username=a&password=b').server, 'http://[fe80::1]:8080');
  });
}
