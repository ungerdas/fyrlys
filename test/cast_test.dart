import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/cast/cast_protocol.dart';
import 'package:fyrlys/core/cast/cast_proxy.dart';
import 'package:fyrlys/core/cast/caster.dart';
import 'package:fyrlys/core/cast/chromecast.dart';
import 'package:fyrlys/core/cast/mdns.dart';

// ── hjelp til DNS-pakkene ──

List<int> _name(String n) => [
      for (final label in n.split('.')) ...[utf8.encode(label).length, ...utf8.encode(label)],
      0,
    ];

List<int> _u16(int v) => [v >> 8, v & 0xff];

List<int> _record(List<int> owner, int type, List<int> data) =>
    [...owner, ..._u16(type), ..._u16(1), 0, 0, 0, 120, ..._u16(data.length), ...data];

List<int> _txt(List<String> entries) => [
      for (final e in entries) ...[utf8.encode(e).length, ...utf8.encode(e)],
    ];

/// Venter (høyst to sekunder) til [done] er sant.
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'skjedde ikke');
}

/// En Chromecast på 127.0.0.1 uten TLS: svarer på LAUNCH og LOAD som en ekte, og henter strømmen fra
/// mellomstasjonen slik Googles avspiller gjør.
class _FakeChromecast {
  late final ServerSocket server;
  final received = <CastMessage>[];
  final _reader = CastFrameReader();
  final _http = HttpClient();
  Socket? client;

  /// spillelista avspilleren fikk fra mellomstasjonen
  String? fetched;

  /// LOAD svarer LOAD_FAILED
  bool failLoad = false;

  /// etter LOAD: IDLE med ERROR og så ERROR med denne koden (den rekkefølgen kan en ekte sende dem i)
  int? errorCode;

  Future<void> start() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((s) {
      client = s;
      unawaited(s.done.then<void>((_) {}, onError: (Object _) {}));
      s.listen((data) {
        for (final m in _reader.add(data)) {
          unawaited(_on(m));
        }
      }, onError: (Object _) {});
    });
  }

  Future<void> close() async {
    _http.close(force: true);
    client?.destroy();
    await server.close();
  }

  void send(String namespace, Map<String, Object?> json, {String from = 'receiver-0'}) => client!.add(frameMessage(
        CastMessage(source: from, destination: '*', namespace: namespace, payload: jsonEncode(json)),
      ));

  Map<String, Object?> _status({bool app = true}) => {
        'applications': [
          if (app) {'appId': defaultMediaReceiver, 'transportId': 'web-5', 'sessionId': 'okt-1'},
        ],
        'volume': {'level': 0.4, 'muted': false},
      };

  Future<void> _on(CastMessage m) async {
    received.add(m);
    final id = m.requestId;
    switch (m.type) {
      case 'LAUNCH':
        send(nsReceiver, {'type': 'RECEIVER_STATUS', 'requestId': id, 'status': _status()});
      case 'LOAD':
        final media = m.json['media']! as Map;
        final res = await (await _http.getUrl(Uri.parse(media['contentId']! as String))).close();
        fetched = await res.transform(utf8.decoder).join();
        if (failLoad) {
          send(nsMedia, {'type': 'LOAD_FAILED', 'requestId': id}, from: 'web-5');
          return;
        }
        send(
          nsMedia,
          {
            'type': 'MEDIA_STATUS',
            'requestId': id,
            'status': [
              {'mediaSessionId': 3, 'playerState': 'PLAYING', 'currentTime': 12.5, 'media': {'duration': 600}},
            ],
          },
          from: 'web-5',
        );
        final code = errorCode;
        if (code != null) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          send(
            nsMedia,
            {
              'type': 'MEDIA_STATUS',
              'requestId': 0,
              'status': [
                {'mediaSessionId': 3, 'playerState': 'IDLE', 'idleReason': 'ERROR'},
              ],
            },
            from: 'web-5',
          );
          send(nsMedia, {'type': 'ERROR', 'requestId': 0, 'detailedErrorCode': code, 'reason': 'GENERIC'},
              from: 'web-5');
        }
      case 'PAUSE':
        send(
          nsMedia,
          {
            'type': 'MEDIA_STATUS',
            'requestId': id,
            'status': [
              {'mediaSessionId': 3, 'playerState': 'PAUSED', 'currentTime': 20},
            ],
          },
          from: 'web-5',
        );
    }
  }

  /// som når noen andre caster til TV-en, eller den stoppes med fjernkontrollen
  void appGone() => send(nsReceiver, {'type': 'RECEIVER_STATUS', 'requestId': 0, 'status': _status(app: false)});
}

/// Leverandøren: /live/u/p/1.m3u8 sender videre til spillelista, som har to segmenter.
Future<HttpServer> _provider(Map<String, String?> seen) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    seen[req.uri.path] = req.headers.value('user-agent');
    final res = req.response;
    switch (req.uri.path) {
      case '/live/u/p/1.m3u8':
        res
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/hls/abc/index.m3u8');
      case '/hls/abc/index.m3u8':
        res.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
        res.write('#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nseg1.ts\n#EXTINF:6,\n'
            'http://127.0.0.1:${server.port}/hls/abc/seg2.ts\n');
      case '/hls/abc/seg1.ts':
        res.headers.contentType = ContentType('video', 'mp2t');
        res.add(List.filled(1000, 0x47));
      // en leverandør som sender spillelista som tekst, fra en adresse uten .m3u8 (og med BOM)
      case '/live/u/p/2.m3u8':
        res
          ..statusCode = HttpStatus.found
          ..headers.set(HttpHeaders.locationHeader, '/stream/xyz');
      case '/stream/xyz' || '/plain/list':
        res.headers.contentType = ContentType('text', 'plain');
        res.add([0xEF, 0xBB, 0xBF]);
        res.write('#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXTINF:6,\nseg3.ts\n');
      case '/stream/seg3.ts':
        res.headers.contentType = ContentType('application', 'octet-stream');
        res.add(List.filled(500, 0x47));
      default:
        res.statusCode = HttpStatus.notFound;
    }
    await res.close();
  });
  return server;
}

void main() {
  test('meldingene til og fra Chromecasten: fram og tilbake, i biter og flere om gangen', () {
    final long = 'x' * 300;
    final a = CastMessage(
      source: 'sender-0',
      destination: 'receiver-0',
      namespace: nsReceiver,
      payload: jsonEncode({'type': 'LAUNCH', 'appId': defaultMediaReceiver, 'requestId': 7, 'pad': long}),
    );
    final b = CastMessage(source: 'receiver-0', destination: 'sender-0', namespace: nsHeartbeat, payload: '{"type":"PING"}');
    final bytes = [...frameMessage(a), ...frameMessage(b)];
    final reader = CastFrameReader();
    final got = <CastMessage>[];
    for (var i = 0; i < bytes.length; i += 7) {
      got.addAll(reader.add(bytes.sublist(i, math.min(i + 7, bytes.length))));
    }
    expect(got, hasLength(2));
    expect(got[0].namespace, nsReceiver);
    expect(got[0].type, 'LAUNCH');
    expect(got[0].requestId, 7);
    expect(got[0].json['pad'], long);
    expect(got[1].source, 'receiver-0');
    expect(got[1].type, 'PING');
    expect(CastMessage.decode([0xff, 0xff]), isNull);
    expect(CastMessage(source: 'a', destination: 'b', namespace: 'c', payload: 'ikke json').json, isEmpty);
  });

  test('mDNS: spørsmålet etter Chromecaster', () {
    final q = mdnsQuery(castService);
    expect(q.sublist(0, 12), [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
    expect(q.sublist(12, q.length - 4), _name(castService));
    expect(q.sublist(q.length - 4), [0, 12, 0x80, 1]);
  });

  test('mDNS: navn, adresse og port fra svaret (også med pekere i navnene)', () {
    const instance = 'Chromecast-abc123._googlecast._tcp.local';
    final ptrOwner = _name(castService);
    // instansnavnet i PTR-posten begynner her: SRV- og TXT-postene peker dit
    final instanceAt = 12 + ptrOwner.length + 10;
    final pointer = [0xC0 | (instanceAt >> 8), instanceAt & 0xff];
    final packet = Uint8List.fromList([
      ..._u16(0), ..._u16(0x8400), ..._u16(0), ..._u16(1), ..._u16(0), ..._u16(3),
      ..._record(ptrOwner, 12, _name(instance)),
      ..._record(pointer, 33, [..._u16(0), ..._u16(0), ..._u16(8009), ..._name('abc123.local')]),
      ..._record(pointer, 16, _txt(['id=abc123', 'md=Chromecast', 'fn=Stue'])),
      ..._record(_name('abc123.local'), 1, [192, 168, 1, 20]),
    ]);
    final device = parseCastResponse(packet).single;
    expect(device.name, 'Stue');
    expect(device.id, 'abc123');
    expect(device.model, 'Chromecast');
    expect(device.host, '192.168.1.20');
    expect(device.port, 8009);
    // bare PTR-posten: avsenderens adresse og navnet fra instansen
    final short = Uint8List.fromList([
      ..._u16(0), ..._u16(0x8400), ..._u16(0), ..._u16(1), ..._u16(0), ..._u16(0),
      ..._record(ptrOwner, 12, _name(instance)),
    ]);
    final fallback = parseCastResponse(short, from: InternetAddress('192.168.1.30')).single;
    expect(fallback.name, 'Chromecast-abc123');
    expect(fallback.host, '192.168.1.30');
    expect(fallback.port, 8009);
    // et spørsmål (ikke et svar) og søppel gir ingenting
    expect(parseCastResponse(mdnsQuery(castService)), isEmpty);
    expect(parseCastResponse(Uint8List.fromList([0, 0, 0x84, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0xC0])), isEmpty);
  });

  test('spillelister skrives om: segmenter, varianter og URI="…"', () {
    const master = '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=800000\nlow/index.m3u8\n'
        '#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="a",URI="audio/a.m3u8"\nhttp://cdn.example/high.m3u8\n';
    final out = rewritePlaylist(master, Uri.parse('http://iptv.example/live/u/p/1.m3u8'), (u) => 'L[$u]');
    expect(out, contains('#EXT-X-STREAM-INF:BANDWIDTH=800000\n'));
    expect(out, contains('L[http://iptv.example/live/u/p/low/index.m3u8]'));
    expect(out, contains('URI="L[http://iptv.example/live/u/p/audio/a.m3u8]"'));
    expect(out, contains('L[http://cdn.example/high.m3u8]'));
  });

  test('CastItem: HLS foretrekkes, og innholdstypen etter filen', () {
    const live = CastItem(urls: ['http://x/1.ts', 'http://x/1.m3u8'], title: 'Kanal', live: true);
    expect(live.url, 'http://x/1.m3u8');
    expect(live.isHls, isTrue);
    expect(live.contentType, 'application/x-mpegurl');
    expect(const CastItem(urls: ['http://x/1.ts'], title: '').contentType, 'video/mp2t');
    expect(const CastItem(urls: ['http://x/film.mkv'], title: '').contentType, 'video/x-matroska');
    expect(const CastItem(urls: ['http://x/film.mp4'], title: '').contentType, 'video/mp4');
  });

  test('mellomstasjonen: spillelister skrives om, segmenter sendes videre med CORS, ukjente adresser avvises',
      () async {
    final seen = <String, String?>{};
    final provider = await _provider(seen);
    final proxy = CastProxy();
    await proxy.start('127.0.0.1');
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await proxy.close();
      await provider.close(force: true);
    });
    final local = proxy.add('http://127.0.0.1:${provider.port}/live/u/p/1.m3u8', {'User-Agent': 'VLC/3.0.21'});
    // brukernavn og passord står ikke i adressen Chromecasten får
    expect(local, isNot(contains('/u/p/')));
    expect(local, endsWith('.m3u8'));

    Future<({int code, String body, HttpHeaders headers})> get(String url, {String method = 'GET'}) async {
      final res = await (await client.openUrl(method, Uri.parse(url))).close();
      final body = await res.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
      return (code: res.statusCode, body: latin1.decode(body), headers: res.headers);
    }

    final playlist = await get(local);
    expect(playlist.code, 200);
    expect(playlist.headers.value('access-control-allow-origin'), '*');
    expect(playlist.headers.contentType?.mimeType, 'application/vnd.apple.mpegurl');
    final lines = playlist.body.split('\n').where((l) => l.isNotEmpty && !l.startsWith('#')).toList();
    expect(lines, hasLength(2));
    expect(lines.every((l) => l.startsWith('http://127.0.0.1:${proxy.port}/')), isTrue);
    expect(seen['/live/u/p/1.m3u8'], 'VLC/3.0.21');
    expect(seen['/hls/abc/index.m3u8'], 'VLC/3.0.21');

    final segment = await get(lines.first);
    expect(segment.code, 200);
    expect(segment.body.length, 1000);
    expect(segment.headers.value('access-control-allow-origin'), '*');
    expect(seen['/hls/abc/seg1.ts'], 'VLC/3.0.21');

    // neste gang hentes lista rett fra der leverandøren sendte den
    seen.clear();
    await get(local);
    expect(seen.keys, ['/hls/abc/index.m3u8']);

    expect((await get(local, method: 'OPTIONS')).code, 204);
    expect((await get('http://127.0.0.1:${proxy.port}/feil/0/strom.m3u8')).code, 404);
    expect(proxy.requests, greaterThanOrEqualTo(5));
  });

  test('spillelista beskrives uten adressene: segmenter, varianter med kodeker, slutt, fMP4 og kryptering', () {
    expect(
      describePlaylist('#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nhttp://iptv.example/live/u/p/1.ts\n'
          '#EXTINF:10,\n2.ts\n'),
      '2 segmenter, mål 10 s',
    );
    expect(
      describePlaylist('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=1,CODECS="avc1.64001f,mp4a.40.2"\nlow.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=2,CODECS="avc1.640028,mp4a.40.2"\nhigh.m3u8\n'),
      'hovedliste, 2 varianter (avc1.64001f,mp4a.40.2 / avc1.640028,mp4a.40.2)',
    );
    expect(
      describePlaylist('#EXTM3U\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXT-X-MAP:URI="init.mp4"\n'
          '#EXT-X-KEY:METHOD=AES-128,URI="http://iptv.example/key"\n#EXTINF:6,\na.m4s\n#EXT-X-ENDLIST\n'),
      '1 segment, VOD, slutt (ENDLIST), fMP4 (EXT-X-MAP), kryptert (AES-128)',
    );
    expect(startsLikePlaylist(utf8.encode('#EXTM3U\n')), isTrue);
    expect(startsLikePlaylist([0xEF, 0xBB, 0xBF, ...utf8.encode('\r\n#EXTM3U')]), isTrue);
    expect(startsLikePlaylist(List.filled(10, 0x47)), isFalse);
    expect(startsLikePlaylist(utf8.encode('#EXT')), isFalse);
  });

  test('mellomstasjonen: en spilleliste sendt som tekst fra en adresse uten .m3u8 skrives om hver gang, '
      'og adresser som ikke ble skrevet om, avvises', () async {
    final seen = <String, String?>{};
    final provider = await _provider(seen);
    final proxy = CastProxy();
    await proxy.start('127.0.0.1');
    final client = HttpClient();
    addTearDown(() async {
      client.close(force: true);
      await proxy.close();
      await provider.close(force: true);
    });

    Future<({int code, String body})> get(String url) async {
      final res = await (await client.getUrl(Uri.parse(url))).close();
      final body = await res.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
      return (code: res.statusCode, body: utf8.decode(body, allowMalformed: true));
    }

    List<String> uris(String body) => body.split('\n').where((l) => l.isNotEmpty && !l.startsWith('#')).toList();

    final local = proxy.add('http://127.0.0.1:${provider.port}/live/u/p/2.m3u8', {'User-Agent': 'VLC/3.0.21'});
    var segment = '';
    // første gang via .m3u8-adressen, så rett fra /stream/xyz (uten .m3u8, sendt som text/plain)
    for (var i = 0; i < 3; i++) {
      final list = await get(local);
      expect(list.code, 200);
      expect(list.body, startsWith('#EXTM3U'));
      segment = uris(list.body).single;
      expect(segment, startsWith('http://127.0.0.1:${proxy.port}/'));
    }
    expect(seen.keys, containsAll(['/live/u/p/2.m3u8', '/stream/xyz']));
    final ts = await get(segment);
    expect(ts.code, 200);
    expect(ts.body.length, 500);

    // en adresse rett til en slik liste: kjennes igjen på #EXTM3U
    final plain = await get(proxy.add('http://127.0.0.1:${provider.port}/plain/list', const {}));
    expect(uris(plain.body).single, startsWith('http://127.0.0.1:${proxy.port}/'));

    // et relativt segment som ikke ble skrevet om, gjort helt ut fra vår adresse: ikke spillelista
    expect((await get(local.replaceFirst(RegExp(r'strom\.m3u8$'), 'seg3.ts'))).code, 404);
  });

  group('Chromecasten', () {
    late _FakeChromecast tv;
    late HttpServer provider;
    late ChromecastCaster caster;
    late CastDevice device;

    setUp(() async {
      tv = _FakeChromecast();
      await tv.start();
      provider = await _provider({});
      caster = ChromecastCaster(socket: (host, port) => Socket.connect(host, port));
      device = CastDevice(id: 'x', name: 'Stue', host: '127.0.0.1', port: tv.server.port);
    });

    tearDown(() async {
      await caster.stop();
      await tv.close();
      await provider.close(force: true);
    });

    CastItem channel() => CastItem(
          urls: ['http://127.0.0.1:${provider.port}/live/u/p/1.m3u8', 'http://127.0.0.1:${provider.port}/live/u/p/1.ts'],
          title: 'Kanal 1',
          subtitle: 'Nyhetene',
          live: true,
          headers: const {'User-Agent': 'VLC/3.0.21'},
        );

    test('kobler til, starter avspilleren, spiller via mellomstasjonen, pause og stopp', () async {
      await caster.connect(device);
      expect(caster.active, isTrue);
      expect(caster.state, CastState.ready);
      expect(caster.volume, closeTo(0.4, 0.001));
      await _until(() => tv.received.where((m) => m.type == 'CONNECT').length == 2);
      expect(tv.received.map((m) => m.type), containsAllInOrder(['CONNECT', 'LAUNCH', 'CONNECT']));
      expect(tv.received.lastWhere((m) => m.type == 'CONNECT').destination, 'web-5');

      await caster.load(channel());
      expect(caster.state, CastState.playing);
      expect(tv.fetched, startsWith('#EXTM3U'));
      final load = tv.received.firstWhere((m) => m.type == 'LOAD');
      expect(load.destination, 'web-5');
      expect(load.json['sessionId'], 'okt-1');
      final media = load.json['media']! as Map;
      expect(media['streamType'], 'LIVE');
      // direktesending: begynner der sendingen er nå, ikke ved det eldste segmentet i lista
      expect(load.json.containsKey('currentTime'), isFalse);
      expect(media['contentType'], 'application/x-mpegurl');
      expect(media['hlsSegmentFormat'], 'ts');
      expect(media['contentId'], isNot(contains('/u/p/')));
      expect((media['metadata']! as Map)['title'], 'Kanal 1');
      expect(caster.duration, const Duration(minutes: 10));
      expect(caster.position, greaterThanOrEqualTo(const Duration(milliseconds: 12500)));

      await caster.pause();
      await _until(() => caster.state == CastState.paused);
      expect(tv.received.any((m) => m.type == 'PAUSE' && m.json['mediaSessionId'] == 3), isTrue);

      await caster.setVolume(0.7);
      await _until(() => tv.received.any((m) => m.type == 'SET_VOLUME'));

      await caster.stop();
      expect(caster.active, isFalse);
      expect(caster.state, CastState.off);
      await _until(() => tv.received.any((m) => m.type == 'STOP' && m.json['sessionId'] == 'okt-1'));
    });

    test('svarer på hjerteslag', () async {
      await caster.connect(device);
      tv.send(nsHeartbeat, {'type': 'PING'});
      await _until(() => tv.received.any((m) => m.namespace == nsHeartbeat && m.type == 'PONG'));
    });

    test('avspilleren på TV-en er borte: castingen stopper og sier fra', () async {
      await caster.connect(device);
      await caster.load(channel());
      tv.appGone();
      await _until(() => !caster.active);
      expect(caster.error, 'Castingen til Stue ble stoppet.');
    });

    test('forbindelsen brytes: castingen stopper og sier fra', () async {
      await caster.connect(device);
      tv.client!.destroy();
      await _until(() => !caster.active);
      expect(caster.error, 'Mistet kontakten med Stue.');
    });

    test('TV-en kan ikke spille det: feil med forklaring', () async {
      tv.failLoad = true;
      await caster.connect(device);
      await caster.load(channel());
      expect(caster.state, CastState.failed);
      expect(caster.error, startsWith('Chromecasten kunne ikke spille dette.'));
    });

    test('Googles avspiller stopper med en feilkode: forklaringen etter koden, også når koden kommer sist', () async {
      tv.errorCode = 104;
      await caster.connect(device);
      await caster.load(channel());
      await _until(() => caster.state == CastState.failed && (caster.error ?? '').contains('104'));
      expect(caster.error, 'Chromecasten støtter ikke formatet denne kanalen sendes i (kode 104).');
    });

    test('får ikke kontakt: feil med navnet', () async {
      final nobody = CastDevice(id: 'y', name: 'Kjøkken', host: '127.0.0.1', port: await _freePort());
      await expectLater(caster.connect(nobody), throwsA(anything));
      expect(caster.active, isFalse);
      expect(caster.error, contains('Kjøkken'));
    });
  });
}

/// En port ingen lytter på.
Future<int> _freePort() async {
  final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = s.port;
  await s.close();
  return port;
}
