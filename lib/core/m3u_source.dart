import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cache.dart' show stableHash;
import 'models.dart';
import 'source.dart';
import 'vod.dart';
import 'xtream_source.dart' show xtreamUserAgent;

/// Én kanal i en M3U-liste.
class M3uEntry {
  const M3uEntry({
    required this.name,
    required this.url,
    this.tvgId = '',
    this.tvgName = '',
    this.logo,
    this.group = '',
    this.number,
  });

  final String name;
  final String url;
  final String tvgId;
  final String tvgName;
  final String? logo;
  final String group;

  /// tvg-chno når lista har det
  final String? number;
}

/// Det som står i en M3U-liste: kanalene, EPG-lenkene i toppen (url-tvg / x-tvg-url), og hvor mange som var
/// filmer eller episoder (de tas ikke med).
typedef M3uList = ({List<M3uEntry> entries, List<String> epgUrls, int skipped});

final _attr = RegExp(r'([\w-]+)="([^"]*)"');
final _vodPath = RegExp(r'/(movie|movies|series|vod)/', caseSensitive: false);
final _vodExt = RegExp(r'\.(mp4|mkv|avi|mov|m4v|wmv)(\?|$)', caseSensitive: false);

Map<String, String> _attributes(String text) => {for (final m in _attr.allMatches(text)) m.group(1)!.toLowerCase(): m.group(2)!.trim()};

/// Leser en M3U-liste (også «extended» med tvg-id, tvg-logo, group-title og #EXTGRP).
M3uList parseM3u(String text) {
  final entries = <M3uEntry>[];
  final epg = <String>[];
  var skipped = 0;
  String? info;
  String? group;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.startsWith('#EXTM3U')) {
      final a = _attributes(line);
      for (final key in const ['url-tvg', 'x-tvg-url', 'tvg-url']) {
        for (final u in (a[key] ?? '').split(',')) {
          final url = u.trim();
          if (url.startsWith('http') && !epg.contains(url)) epg.add(url);
        }
      }
    } else if (line.startsWith('#EXTINF')) {
      info = line;
      group = null;
    } else if (line.startsWith('#EXTGRP:')) {
      group = line.substring(8).trim();
    } else if (line.startsWith('#')) {
      continue;
    } else {
      final i = info;
      info = null;
      if (i == null) continue;
      if (_vodPath.hasMatch(line) || _vodExt.hasMatch(line)) {
        skipped++;
        continue;
      }
      // navnet står etter det første kommaet utenfor anførselstegn
      var quoted = false;
      var comma = -1;
      for (var k = 0; k < i.length; k++) {
        final c = i[k];
        if (c == '"') quoted = !quoted;
        if (c == ',' && !quoted) {
          comma = k;
          break;
        }
      }
      final head = comma >= 0 ? i.substring(0, comma) : i;
      final a = _attributes(head);
      var name = comma >= 0 ? i.substring(comma + 1).trim() : '';
      if (name.isEmpty) name = a['tvg-name'] ?? '';
      if (name.isEmpty) continue;
      final logo = a['tvg-logo'] ?? '';
      final chno = a['tvg-chno'] ?? '';
      entries.add(M3uEntry(
        name: name,
        url: line,
        tvgId: a['tvg-id'] ?? '',
        tvgName: a['tvg-name'] ?? '',
        logo: logo.startsWith('http') ? logo : null,
        group: (a['group-title'] ?? '').isNotEmpty ? a['group-title']! : (group ?? ''),
        number: chno.isEmpty ? null : chno,
      ));
    }
  }
  return (entries: entries, epgUrls: epg, skipped: skipped);
}

/// Programmene i en XMLTV-fil per kanal-id, og kanalenes visningsnavn (små bokstaver) → id.
typedef XmltvGuide = ({Map<String, List<EpgEntry>> programmes, Map<String, String> names});

final _channelRe = RegExp(r'<channel\s+id="([^"]*)"[^>]*>(.*?)</channel>', dotAll: true);
final _displayRe = RegExp(r'<display-name[^>]*>(.*?)</display-name>', dotAll: true);
final _programmeRe = RegExp(r'<programme\s([^>]*)>(.*?)</programme>', dotAll: true);
final _titleRe = RegExp(r'<title[^>]*>(.*?)</title>', dotAll: true);
final _descRe = RegExp(r'<desc[^>]*>(.*?)</desc>', dotAll: true);
final _timeRe = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{4})?');

/// Tekst i XML: CDATA og &amp; &lt; &#228; osv.
String xmlText(String raw) {
  var t = raw.trim();
  if (t.startsWith('<![CDATA[') && t.endsWith(']]>')) return t.substring(9, t.length - 3).trim();
  t = t.replaceAllMapped(RegExp(r'&#(x?)([0-9a-fA-F]+);'), (m) {
    final code = int.tryParse(m.group(2)!, radix: m.group(1)!.isEmpty ? 10 : 16);
    return code == null ? m.group(0)! : String.fromCharCode(code);
  });
  return t
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

/// «20261026120000 +0100» → tidspunktet (uten sone: UTC).
DateTime? xmltvTime(String text) {
  final m = _timeRe.firstMatch(text.trim());
  if (m == null) return null;
  int n(int i) => int.parse(m.group(i) ?? '0');
  var t = DateTime.utc(n(1), n(2), n(3), n(4), n(5), m.group(6) == null ? 0 : n(6));
  final zone = m.group(7);
  if (zone != null) {
    final sign = zone.startsWith('-') ? -1 : 1;
    final minutes = int.parse(zone.substring(1, 3)) * 60 + int.parse(zone.substring(3, 5));
    t = t.subtract(Duration(minutes: sign * minutes));
  }
  return t.toLocal();
}

/// Leser XMLTV (også store filer: bare det som går fra to timer siden til et døgn fram, tas med).
XmltvGuide parseXmltv(String xml, DateTime now) {
  final names = <String, String>{};
  for (final m in _channelRe.allMatches(xml)) {
    final id = xmlText(m.group(1)!);
    for (final d in _displayRe.allMatches(m.group(2)!)) {
      final name = xmlText(d.group(1)!).toLowerCase();
      if (name.isNotEmpty) names.putIfAbsent(name, () => id);
    }
  }
  final from = now.subtract(const Duration(hours: 2));
  final to = now.add(const Duration(hours: 24));
  final programmes = <String, List<EpgEntry>>{};
  for (final m in _programmeRe.allMatches(xml)) {
    final a = _attributes(m.group(1)!);
    final start = xmltvTime(a['start'] ?? '');
    final stop = xmltvTime(a['stop'] ?? '');
    final channel = xmlText(a['channel'] ?? '');
    if (start == null || stop == null || channel.isEmpty || !stop.isAfter(from) || start.isAfter(to)) continue;
    final body = m.group(2)!;
    final title = _titleRe.firstMatch(body);
    final desc = _descRe.firstMatch(body);
    (programmes[channel] ??= []).add(EpgEntry(
      title: title == null ? '' : xmlText(title.group(1)!),
      description: desc == null ? '' : xmlText(desc.group(1)!),
      start: start,
      stop: stop,
    ));
  }
  for (final list in programmes.values) {
    list.sort((x, y) => x.start.compareTo(y.start));
  }
  return (programmes: programmes, names: names);
}

/// Pakker ut gzip (EPG-filer er ofte .xml.gz) og gjør bytene om til tekst.
String _decodeText(Uint8List bytes) {
  final raw = bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b ? gzip.decode(bytes) : bytes;
  return utf8.decode(raw, allowMalformed: true);
}

// I bakgrunnen (egen isolate), så bildet ikke henger mens store filer leses. Egne funksjoner, så det bare er
// bytene som sendes over.
Future<M3uList> _parseM3uInBackground(Uint8List bytes) => Isolate.run(() => parseM3u(_decodeText(bytes)));

Future<XmltvGuide> _parseXmltvInBackground(Uint8List bytes, DateTime now) =>
    Isolate.run(() => parseXmltv(_decodeText(bytes), now));

/// En M3U-liste (fra hvilken som helst leverandør) som kilde: kanalene og kategoriene fra lista, og TV-guide fra
/// XMLTV (lenken i lista, eller en du har oppgitt). Filmer og serier tas ikke med; en Xtream-lenke (get.php med
/// brukernavn og passord) blir en Xtream-innlogging i stedet, som har dem.
class M3uSource implements TvSource {
  M3uSource({required this.url, this.epgUrl = '', http.Client? client}) : _http = client ?? http.Client();

  final String url;

  /// EPG-lenken du har oppgitt (tom: den som står i lista)
  final String epgUrl;
  final http.Client _http;

  List<Channel>? _channels;
  List<Category>? _categories;
  final Map<String, M3uEntry> _entries = {};
  List<String> _listEpg = const [];
  DateTime? _loadedAt;
  Future<void>? _loading;

  XmltvGuide? _guide;
  DateTime? _guideAt;
  Future<XmltvGuide?>? _guideLoading;

  /// «http://iptv.example/liste.m3u» (uten http:// legges det til)
  static String normalize(String raw) {
    var text = raw.trim();
    if (text.isEmpty) throw const SourceException('Lim inn M3U-lenken');
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(text)) text = 'http://$text';
    final u = Uri.tryParse(text);
    if (u == null || u.host.isEmpty) throw const SourceException('Ugyldig lenke');
    return text;
  }

  /// Henter lista og sjekker at det er kanaler i den, før innloggingen lagres.
  static Future<M3uSource> connect(String rawUrl, {String epgUrl = '', http.Client? client}) async {
    final epg = epgUrl.trim().isEmpty ? '' : normalize(epgUrl);
    final src = M3uSource(url: normalize(rawUrl), epgUrl: epg, client: client);
    try {
      await src._ensure(force: true);
      return src;
    } on SourceException {
      src.dispose();
      rethrow;
    }
  }

  @override
  String get kind => 'm3u';

  @override
  String get label => 'M3U-liste fra ${Uri.tryParse(url)?.host ?? url}';

  @override
  Map<String, String> get httpHeaders => const {'User-Agent': xtreamUserAgent};

  @override
  bool get hasVod => false;

  /// EPG-lenkene som brukes: din, eller de lista selv oppgir
  List<String> get epgUrls => epgUrl.isNotEmpty ? [epgUrl] : _listEpg;

  Future<Uint8List> _download(String address, String what) async {
    final http.Response r;
    try {
      r = await _http.get(Uri.parse(address), headers: httpHeaders).timeout(const Duration(minutes: 3));
    } on Exception {
      throw SourceException('Får ikke hentet $what');
    }
    if (r.statusCode == 401 || r.statusCode == 403) throw SourceException('Serveren avviste $what (HTTP ${r.statusCode})');
    if (r.statusCode >= 400) throw SourceException('Serveren svarte HTTP ${r.statusCode} for $what');
    return r.bodyBytes;
  }

  /// Lista hentes én gang (og på nytt etter en halvtime eller med [force]).
  Future<void> _ensure({bool force = false}) {
    final at = _loadedAt;
    if (!force && at != null && DateTime.now().difference(at) < const Duration(minutes: 30)) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    final bytes = await _download(url, 'M3U-lista');
    // store lister (titusenvis av linjer) leses i bakgrunnen, så bildet ikke henger imens
    final M3uList list;
    try {
      list = bytes.length > 200000 ? await _parseM3uInBackground(bytes) : parseM3u(_decodeText(bytes));
    } on Object {
      throw const SourceException('Lenken ga ikke en M3U-liste');
    }
    if (list.entries.isEmpty) {
      throw SourceException(
        list.skipped > 0 ? 'Lista har bare filmer og serier, ingen TV-kanaler' : 'Fant ingen kanaler i lista',
      );
    }
    final channels = <Channel>[];
    final groups = <String, Category>{};
    final seen = <String>{};
    _entries.clear();
    for (var i = 0; i < list.entries.length; i++) {
      final e = list.entries[i];
      final group = e.group.isEmpty ? 'Uten kategori' : e.group;
      groups.putIfAbsent(group, () => Category(id: group, name: group));
      // samme id neste gang (favoritter og «sist sett»), selv om adressene i lista skulle endre seg
      final key = e.tvgId.isNotEmpty ? 'id:${e.tvgId}|${e.name}' : 'n:$group|${e.name}';
      var id = stableHash(key);
      for (var n = 2; !seen.add(id); n++) {
        id = stableHash('$key#$n');
      }
      _entries[id] = e;
      channels.add(Channel(
        id: id,
        name: e.name,
        categoryId: group,
        icon: e.logo,
        number: e.number ?? '${i + 1}',
        hasEpg: epgUrl.isNotEmpty || list.epgUrls.isNotEmpty,
      ));
    }
    _channels = channels;
    _categories = groups.values.toList();
    _listEpg = list.epgUrls;
    _loadedAt = DateTime.now();
  }

  @override
  Future<Account> account() async => Account(host: Uri.tryParse(url)?.host ?? '');

  @override
  Future<List<Category>> categories({bool force = false}) async {
    await _ensure(force: force);
    return _categories ?? const [];
  }

  @override
  Future<List<Channel>> channels({bool force = false}) async {
    await _ensure(force: force);
    return _channels ?? const [];
  }

  // ── TV-guide fra XMLTV ──

  /// XMLTV-fila hentes én gang og så hver 6. time; feiler den, prøves det igjen neste gang noen spør.
  Future<XmltvGuide?> _loadGuide() {
    final have = _guide;
    final at = _guideAt;
    if (have != null && at != null && DateTime.now().difference(at) < const Duration(hours: 6)) {
      return Future.value(have);
    }
    return _guideLoading ??= _fetchGuide().whenComplete(() => _guideLoading = null);
  }

  Future<XmltvGuide?> _fetchGuide() async {
    for (final address in epgUrls) {
      try {
        final bytes = await _download(address, 'TV-guiden');
        final now = DateTime.now();
        final guide = await _parseXmltvInBackground(bytes, now);
        _guide = guide;
        _guideAt = DateTime.now();
        return guide;
      } on Object {
        // neste lenke, eller det vi hadde
      }
    }
    return _guide;
  }

  @override
  Future<List<EpgEntry>> epg(String channelId, {int limit = 6}) async {
    await _ensure();
    final e = _entries[channelId];
    if (e == null || epgUrls.isEmpty) return const [];
    final guide = await _loadGuide();
    if (guide == null) return const [];
    var key = e.tvgId;
    if (!guide.programmes.containsKey(key)) {
      key = guide.names[e.name.toLowerCase()] ?? guide.names[e.tvgName.toLowerCase()] ?? '';
    }
    final now = DateTime.now();
    return [
      for (final p in guide.programmes[key] ?? const <EpgEntry>[])
        if (p.stop.isAfter(now)) p,
    ].take(limit).toList();
  }

  @override
  String? logoUrl(String? icon) => icon;

  @override
  Future<PlayTarget> open(Channel channel) async {
    await _ensure();
    final e = _entries[channel.id];
    if (e == null) throw const SourceException('Fant ikke kanalen i lista. Hent listene på nytt i menyen.');
    // rett fra leverandøren: avspilleren tar vare på det siste selv, så det går an å pause og spole tilbake
    return PlayTarget([e.url], localShift: true);
  }

  // ── filmer og serier finnes ikke her (fanene skjules) ──

  @override
  Future<VodCatalog> vodCatalog(VodKind kind, {bool force = false}) async => catalogOf(const [], const []);

  @override
  Future<VodPage> vodPage(VodKind kind,
          {String category = '', String query = '', VodSort sort = VodSort.provider, int start = 0}) async =>
      pageOf(const [], category: category, query: query, sort: sort, start: start);

  @override
  Future<MovieInfo> movieInfo(String id) async => throw const SourceException('M3U-lister har ikke filmer i Fyrlys');

  @override
  Future<SeriesInfo> seriesInfo(String id) async => throw const SourceException('M3U-lister har ikke serier i Fyrlys');

  @override
  String movieUrl(VodItem movie) => '';

  @override
  String episodeUrl(Episode episode) => '';

  /// Brukernavn og passord i lenken (mange lister har dem) byttes med *** i det som vises eller logges.
  @override
  String redact(String text) {
    var out = text;
    final q = Uri.tryParse(url)?.queryParameters ?? const <String, String>{};
    for (final key in const ['password', 'username', 'token']) {
      final secret = q[key];
      if (secret != null && secret.length >= 3) {
        out = out.replaceAll(secret, '***').replaceAll(Uri.encodeComponent(secret), '***');
      }
    }
    return out;
  }

  @override
  Map<String, String> toPrefs() => {'kind': kind, 'url': url, 'epg': epgUrl};

  @override
  void dispose() => _http.close();
}
