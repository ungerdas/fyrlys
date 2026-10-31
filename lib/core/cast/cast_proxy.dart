import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

/// Skriver om adressene i en HLS-spilleliste (segmentene, variantene, og URI="…" i #EXT-X-KEY/MEDIA/MAP) med [map],
/// etter at de er gjort hele ut fra [base] (der spillelista faktisk kom fra).
String rewritePlaylist(String text, Uri base, String Function(Uri uri) map) {
  final attribute = RegExp(r'URI="([^"]*)"');
  final out = StringBuffer();
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty) {
      out.writeln();
    } else if (line.startsWith('#')) {
      out.writeln(line.replaceAllMapped(attribute, (m) => 'URI="${map(base.resolve(m[1]!))}"'));
    } else {
      out.writeln(map(base.resolve(line)));
    }
  }
  return out.toString();
}

/// Begynner [head] som en HLS-spilleliste (#EXTM3U, etter ev. BOM og blanktegn)? For leverandører som sender
/// spillelista med en annen type og fra en adresse uten .m3u8.
bool startsLikePlaylist(List<int> head) {
  var i = 0;
  if (head.length >= 3 && head[0] == 0xEF && head[1] == 0xBB && head[2] == 0xBF) i = 3;
  while (i < head.length && (head[i] == 0x20 || head[i] == 0x09 || head[i] == 0x0D || head[i] == 0x0A)) {
    i++;
  }
  const tag = '#EXTM3U';
  if (head.length - i < tag.length) return false;
  for (var k = 0; k < tag.length; k++) {
    if (head[i + k] != tag.codeUnitAt(k)) return false;
  }
  return true;
}

/// Det som er verdt å vite om en spilleliste i feilrapporten, uten adressene (de kan ha innloggingen i seg):
/// «12 segmenter, mål 10 s» eller «hovedliste, 3 varianter (avc1.64001f,mp4a.40.2)», og om den er slutt (ENDLIST),
/// har fMP4-segmenter (EXT-X-MAP) eller er kryptert.
String describePlaylist(String text) {
  var segments = 0;
  var variants = 0;
  String? target;
  String? type;
  String? key;
  var end = false;
  var map = false;
  final codecs = <String>{};
  final codecPattern = RegExp(r'CODECS="([A-Za-z0-9., ]{1,80})"');
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.startsWith('#EXTINF')) {
      segments++;
    } else if (line.startsWith('#EXT-X-STREAM-INF')) {
      variants++;
      final c = codecPattern.firstMatch(line);
      if (c != null) codecs.add(c[1]!.replaceAll(' ', ''));
    } else if (line.startsWith('#EXT-X-TARGETDURATION:')) {
      final v = line.substring(22).trim();
      if (RegExp(r'^\d{1,4}(\.\d+)?$').hasMatch(v)) target = v;
    } else if (line.startsWith('#EXT-X-PLAYLIST-TYPE:')) {
      final v = line.substring(21).trim().toUpperCase();
      if (RegExp(r'^[A-Z]{1,10}$').hasMatch(v)) type = v;
    } else if (line.startsWith('#EXT-X-ENDLIST')) {
      end = true;
    } else if (line.startsWith('#EXT-X-MAP')) {
      map = true;
    } else if (line.startsWith('#EXT-X-KEY')) {
      final m = RegExp(r'METHOD=([A-Z0-9-]{1,20})').firstMatch(line);
      if (m != null && m[1] != 'NONE') key = m[1];
    }
  }
  final parts = <String>[
    if (variants > 0)
      'hovedliste, $variants ${variants == 1 ? 'variant' : 'varianter'}'
          '${codecs.isEmpty ? '' : ' (${codecs.join(' / ')})'}',
    if (variants == 0)
      '$segments ${segments == 1 ? 'segment' : 'segmenter'}${target == null ? '' : ', mål $target s'}',
    if (type != null) type,
    if (end) 'slutt (ENDLIST)',
    if (map) 'fMP4 (EXT-X-MAP)',
    if (key != null) 'kryptert ($key)',
  ];
  return parts.join(', ');
}

bool _looksLikePlaylist(Uri uri) {
  final path = uri.path.toLowerCase();
  return path.endsWith('.m3u8') || path.endsWith('.m3u');
}

/// En feil uten adressen i (HttpException og SocketException har den i toString).
String _safeError(Object e) => switch (e) {
      SocketException(:final osError, :final message) => 'SocketException ${osError?.message ?? message}',
      HttpException(:final message) => 'HttpException $message',
      TimeoutException() => 'tidsavbrudd',
      FormatException(:final message) => message,
      _ => e.runtimeType.toString(),
    };

class _Entry {
  _Entry(this.id, this.url, this.headers, this.name);

  final String id;
  String url;
  final Map<String, String> headers;

  /// siste del av adressen Chromecasten får («strom.m3u8»)
  final String name;

  /// en spilleliste: skrives om hver gang, uansett hva leverandøren kaller den
  bool playlist = false;

  /// det som er logget om spillelista (logges igjen bare når det endrer seg vesentlig)
  bool described = false;
  bool ended = false;
}

/// Mellomstasjonen på PC-en som Chromecasten henter strømmen fra.
///
/// Chromecasten kan ikke sende leverandørens User-Agent, og Googles avspiller krever CORS-hoder på HLS, som
/// IPTV-leverandører nesten aldri har. Her hentes alt fra leverandøren med de rette hodene og sendes videre med CORS.
/// Spillelistene skrives om så segmentene også går hit. Adressene har et tilfeldig merke og løpenummer, så
/// Chromecasten (og andre på nettverket) aldri ser brukernavnet og passordet hos leverandøren.
///
/// Til feilrapporten logges hvordan spillelista ser ut (første gang), svar fra leverandøren på 400 og over, og hvert
/// 20. sekund hvor mye Chromecasten har hentet (eller at den har sluttet å hente).
class CastProxy {
  CastProxy({HttpClient? client})
      : _client = client ??
            (HttpClient()
              ..connectionTimeout = const Duration(seconds: 10)
              ..autoUncompress = false
              ..userAgent = null);

  final HttpClient _client;
  HttpServer? _server;
  final String _token = _randomToken();
  final Map<String, _Entry> _entries = {};
  final Map<String, String> _ids = {};
  int _next = 0;
  String _host = '127.0.0.1';
  Timer? _statsTimer;

  /// hvor mange forespørsler som har kommet (0 etter en feil: Chromecasten kom ikke fram til PC-en)
  int requests = 0;

  /// siden forrige oppsummering
  int _playlists = 0;
  int _segments = 0;
  int _bytes = 0;
  int _errors = 0;
  bool _quiet = false;

  /// når hver slags beskjed sist ble logget, og hvor mange som er holdt tilbake siden
  final Map<String, DateTime> _noted = {};
  final Map<String, int> _held = {};

  /// Største spilleliste som skrives om.
  static const maxPlaylist = 4 << 20;

  /// Adressene som huskes (de eldste glemmes; en direktesending får nye segmenter hele tiden).
  static const maxEntries = 4000;

  /// Hvor ofte det logges hva Chromecasten har hentet.
  static const statsEvery = Duration(seconds: 20);

  int get port => _server?.port ?? 0;

  static String _randomToken() {
    final r = Random.secure();
    return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  /// Starter på en ledig port. [host] er PC-ens adresse slik Chromecasten ser den.
  Future<void> start(String host) async {
    _host = host;
    if (_server != null) return;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    _server = server;
    server.listen((req) => unawaited(_handle(req)), onError: (Object _) {});
    _statsTimer = Timer.periodic(statsEvery, (_) => _report());
  }

  /// Adressen Chromecasten skal hente [url] fra.
  String add(String url, Map<String, String> headers) {
    final known = _ids[url];
    final existing = known == null ? null : _entries[known];
    if (existing != null) return _local(existing);
    final id = (_next++).toRadixString(36);
    final entry = _Entry(id, url, headers, _nameFor(url));
    _entries[id] = entry;
    _ids[url] = id;
    while (_entries.length > maxEntries) {
      final oldest = _entries.keys.first;
      final gone = _entries.remove(oldest);
      if (gone != null && _ids[gone.url] == gone.id) _ids.remove(gone.url);
    }
    return _local(entry);
  }

  static String _nameFor(String url) {
    final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    final last = segments.isEmpty ? '' : segments.last;
    final dot = last.lastIndexOf('.');
    final ext = dot >= 0 ? last.substring(dot) : '';
    final safe = RegExp(r'^\.[A-Za-z0-9]{1,5}$').hasMatch(ext) ? ext : '';
    return 'strom$safe';
  }

  String _local(_Entry e) => 'http://$_host:$port/$_token/${e.id}/${e.name}';

  /// Logger [text], men samme slags beskjed ([key]) høyst hvert 10. sekund (med hvor mange som ble holdt tilbake).
  void _note(String key, String text) {
    final now = DateTime.now();
    final last = _noted[key];
    if (last != null && now.difference(last) < const Duration(seconds: 10)) {
      _held[key] = (_held[key] ?? 0) + 1;
      return;
    }
    _noted[key] = now;
    final held = _held.remove(key) ?? 0;
    debugPrint('Chromecast-mellomstasjonen: $text${held > 0 ? ' (+$held like)' : ''}');
  }

  void _report() {
    if (_playlists == 0 && _segments == 0 && _errors == 0) {
      // Chromecasten har sluttet å hente: sier det én gang
      if (requests > 0 && !_quiet) {
        _quiet = true;
        debugPrint('Chromecast-mellomstasjonen: ingen forespørsler fra Chromecasten de siste '
            '${statsEvery.inSeconds} s');
      }
      return;
    }
    _quiet = false;
    final mb = (_bytes / 1e6).toStringAsFixed(1);
    debugPrint('Chromecast-mellomstasjonen: siste ${statsEvery.inSeconds} s: $_playlists spillelister, '
        '$_segments segmenter ($mb MB)${_errors > 0 ? ', $_errors feil' : ''}');
    _playlists = 0;
    _segments = 0;
    _bytes = 0;
    _errors = 0;
  }

  void _cors(HttpResponse res) {
    res.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS')
      ..set('Access-Control-Allow-Headers', '*')
      ..set('Access-Control-Expose-Headers', 'Content-Length, Content-Range, Accept-Ranges');
  }

  Future<void> _handle(HttpRequest req) async {
    requests++;
    final res = req.response;
    _cors(res);
    final segments = req.uri.pathSegments;
    _Entry? entry;
    if (segments.length == 3 && segments[0] == _token) {
      final known = _entries[segments[1]];
      if (known != null && segments[2] == known.name) {
        entry = known;
      } else if (known != null) {
        // en adresse i spillelista som ikke ble skrevet om, gjort hel ut fra vår adresse
        _note('ukjent navn', 'Chromecasten ba om en ukjent adresse under en kjent strøm');
      }
    }
    try {
      if (req.method == 'OPTIONS') {
        res.statusCode = HttpStatus.noContent;
        await res.close();
        return;
      }
      if (entry == null || (req.method != 'GET' && req.method != 'HEAD')) {
        if (entry == null && segments.isNotEmpty && segments[0] == _token && segments.length != 3) {
          _note('ukjent sti', 'Chromecasten ba om en adresse med ${segments.length} ledd (venter 3)');
        } else if (entry == null &&
            segments.length == 3 &&
            segments[0] == _token &&
            !_entries.containsKey(segments[1])) {
          _note('glemt', 'Chromecasten ba om en adresse som er glemt eller aldri fantes');
        }
        _errors++;
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      await _forward(req, res, entry);
    } on Object catch (e) {
      _errors++;
      _note('feil', 'feil under videresending: ${_safeError(e)}');
      try {
        res.statusCode = HttpStatus.badGateway;
      } on Object {
        // svaret er alt på vei: bare lukk
      }
      try {
        await res.close();
      } on Object {
        // Chromecasten har gått
      }
    }
  }

  Future<void> _forward(HttpRequest req, HttpResponse res, _Entry entry) async {
    final original = Uri.parse(entry.url);
    final up = await _client.openUrl(req.method, original);
    entry.headers.forEach(up.headers.set);
    final range = req.headers.value(HttpHeaders.rangeHeader);
    if (range != null && !entry.playlist) up.headers.set(HttpHeaders.rangeHeader, range);
    final upRes = await up.close();
    var at = original;
    for (final r in upRes.redirects) {
      at = at.resolveUri(r.location);
    }
    final ok = upRes.statusCode < 300;
    final type = upRes.headers.contentType?.mimeType.toLowerCase() ?? '';
    if (!ok) {
      _errors++;
      _note('svar ${upRes.statusCode}',
          'leverandøren svarte ${upRes.statusCode} på ${entry.playlist ? 'spillelista' : 'et segment'}');
    }
    final input = StreamIterator<List<int>>(upRes);
    try {
      var playlist =
          ok && (entry.playlist || type.contains('mpegurl') || _looksLikePlaylist(at) || _looksLikePlaylist(original));
      List<int> head = const [];
      if (ok && !playlist && req.method != 'HEAD') {
        // sendt med en annen type fra en adresse uten .m3u8: se etter #EXTM3U i begynnelsen (den kan komme i flere
        // små biter, f.eks. BOM for seg)
        final first = BytesBuilder(copy: false);
        while (first.length < 32 && await input.moveNext()) {
          first.add(input.current);
        }
        head = first.takeBytes();
        playlist = startsLikePlaylist(head);
      }
      res.statusCode = upRes.statusCode;
      if (playlist) {
        entry.playlist = true;
        // neste gang rett til der leverandøren sendte (ellers kan en ny økt startes hver gang lista hentes)
        if (at != original) {
          if (_ids[entry.url] == entry.id) _ids.remove(entry.url);
          entry.url = at.toString();
          _ids.putIfAbsent(entry.url, () => entry.id);
        }
        final builder = BytesBuilder(copy: false)..add(head);
        while (await input.moveNext()) {
          builder.add(input.current);
          if (builder.length > maxPlaylist) throw const FormatException('for stor spilleliste');
        }
        var bytes = builder.takeBytes();
        if ((upRes.headers.value(HttpHeaders.contentEncodingHeader) ?? '').toLowerCase() == 'gzip') {
          bytes = Uint8List.fromList(gzip.decode(bytes));
        }
        final source = utf8.decode(bytes, allowMalformed: true);
        _describe(entry, source, type);
        final text = rewritePlaylist(
          source,
          at,
          (u) => u.isScheme('http') || u.isScheme('https') ? add(u.toString(), entry.headers) : u.toString(),
        );
        final body = utf8.encode(text);
        res.headers
          ..contentType = ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8')
          ..set(HttpHeaders.cacheControlHeader, 'no-cache');
        res.contentLength = body.length;
        if (req.method != 'HEAD') res.add(body);
        await res.close();
        _playlists++;
        return;
      }
      for (final name in const [
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
        HttpHeaders.contentEncodingHeader,
      ]) {
        final value = upRes.headers.value(name);
        if (value != null) res.headers.set(name, value);
      }
      if (req.method == 'HEAD') {
        await res.close();
        return;
      }
      Stream<List<int>> rest() async* {
        if (head.isNotEmpty) {
          _bytes += head.length;
          yield head;
        }
        while (await input.moveNext()) {
          _bytes += input.current.length;
          yield input.current;
        }
      }

      await res.addStream(rest());
      await res.close();
      if (ok) _segments++;
    } finally {
      await input.cancel();
    }
  }

  /// Logger hvordan spillelista ser ut første gang, og hvis den plutselig er slutt (ENDLIST).
  void _describe(_Entry entry, String text, String type) {
    final ended = text.contains('#EXT-X-ENDLIST');
    if (entry.described && (entry.ended || !ended)) return;
    final first = !entry.described;
    entry
      ..described = true
      ..ended = ended;
    final kind = type.isEmpty ? 'uten type' : type;
    debugPrint('Chromecast-mellomstasjonen: ${first ? 'spilleliste' : 'spillelista er nå'} '
        '${entry.id} ($kind): ${describePlaylist(text)}');
  }

  Future<void> close() async {
    _statsTimer?.cancel();
    _statsTimer = null;
    final server = _server;
    _server = null;
    await server?.close(force: true);
    _client.close(force: true);
    _entries.clear();
    _ids.clear();
  }
}
