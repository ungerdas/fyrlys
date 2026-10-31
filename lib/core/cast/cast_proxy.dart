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

bool _looksLikePlaylist(Uri uri) {
  final path = uri.path.toLowerCase();
  return path.endsWith('.m3u8') || path.endsWith('.m3u');
}

class _Entry {
  _Entry(this.id, this.url, this.headers);

  final String id;
  String url;
  final Map<String, String> headers;
}

/// Mellomstasjonen på PC-en som Chromecasten henter strømmen fra.
///
/// Chromecasten kan ikke sende leverandørens User-Agent, og Googles avspiller krever CORS-hoder på HLS, som
/// IPTV-leverandører nesten aldri har. Her hentes alt fra leverandøren med de rette hodene og sendes videre med CORS.
/// Spillelistene skrives om så segmentene også går hit. Adressene har et tilfeldig merke og løpenummer, så
/// Chromecasten (og andre på nettverket) aldri ser brukernavnet og passordet hos leverandøren.
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

  /// hvor mange forespørsler som har kommet (0 etter en feil: Chromecasten kom ikke fram til PC-en)
  int requests = 0;

  /// Største spilleliste som skrives om.
  static const maxPlaylist = 4 << 20;

  /// Adressene som huskes (de eldste glemmes; en direktesending får nye segmenter hele tiden).
  static const maxEntries = 4000;

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
  }

  /// Adressen Chromecasten skal hente [url] fra.
  String add(String url, Map<String, String> headers) {
    final known = _ids[url];
    if (known != null) return _local(known, url);
    final id = (_next++).toRadixString(36);
    _entries[id] = _Entry(id, url, headers);
    _ids[url] = id;
    while (_entries.length > maxEntries) {
      final oldest = _entries.keys.first;
      final entry = _entries.remove(oldest);
      if (entry != null && _ids[entry.url] == entry.id) _ids.remove(entry.url);
    }
    return _local(id, url);
  }

  String _local(String id, String url) {
    final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    final last = segments.isEmpty ? '' : segments.last;
    final dot = last.lastIndexOf('.');
    final ext = dot >= 0 ? last.substring(dot) : '';
    final safe = RegExp(r'^\.[A-Za-z0-9]{1,5}$').hasMatch(ext) ? ext : '';
    return 'http://$_host:$port/$_token/$id/strom$safe';
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
    final entry = segments.length >= 2 && segments[0] == _token ? _entries[segments[1]] : null;
    try {
      if (req.method == 'OPTIONS') {
        res.statusCode = HttpStatus.noContent;
        await res.close();
        return;
      }
      if (entry == null || (req.method != 'GET' && req.method != 'HEAD')) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      await _forward(req, res, entry);
    } on Object catch (e) {
      debugPrint('Chromecast-mellomstasjonen: ${e.runtimeType}');
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
    if (range != null) up.headers.set(HttpHeaders.rangeHeader, range);
    final upRes = await up.close();
    var at = original;
    for (final r in upRes.redirects) {
      at = at.resolveUri(r.location);
    }
    final type = upRes.headers.contentType?.mimeType.toLowerCase() ?? '';
    final playlist = type.contains('mpegurl') || _looksLikePlaylist(at) || _looksLikePlaylist(original);
    res.statusCode = upRes.statusCode;
    if (playlist && upRes.statusCode < 300) {
      // neste gang rett til der leverandøren sendte (ellers kan en ny økt startes hver gang lista hentes)
      if (at != original) {
        if (_ids[entry.url] == entry.id) _ids.remove(entry.url);
        entry.url = at.toString();
        _ids.putIfAbsent(entry.url, () => entry.id);
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in upRes) {
        builder.add(chunk);
        if (builder.length > maxPlaylist) throw const FormatException('for stor spilleliste');
      }
      var bytes = builder.takeBytes();
      if ((upRes.headers.value(HttpHeaders.contentEncodingHeader) ?? '').toLowerCase() == 'gzip') {
        bytes = Uint8List.fromList(gzip.decode(bytes));
      }
      final text = rewritePlaylist(
        utf8.decode(bytes, allowMalformed: true),
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
      await upRes.drain<void>();
      await res.close();
      return;
    }
    await res.addStream(upRes);
    await res.close();
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
    _client.close(force: true);
    _entries.clear();
    _ids.clear();
  }
}
