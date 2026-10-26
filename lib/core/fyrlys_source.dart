import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'source.dart';
import 'vod.dart';

String _randomId() {
  final r = Random.secure();
  return List.generate(24, (_) => '0123456789abcdef'[r.nextInt(16)]).join();
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

int? _intOrNull(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

double? _double(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

String _text(Object? v) => v == null ? '' : '$v'.trim();

String? _url(Object? v) => v is String && (v.startsWith('http://') || v.startsWith('https://')) ? v : null;

/// Fyrlys-serveren (Docker-versjonen) som kilde. Innloggingen hos leverandøren, favorittene og «Ta over»
/// deles med nettsiden, og serveren holder styr på hvem som bruker tilkoblingene.
class FyrlysSource implements TvSource {
  FyrlysSource({required this.base, http.Client? client, String? clientId, this.ffmpeg = true})
      : _http = client ?? http.Client(),
        clientId = (clientId == null || clientId.isEmpty) ? _randomId() : clientId;

  final String base;
  final http.Client _http;

  /// hvem appen er overfor serveren (som en fane i nettleseren), så den teller seere riktig
  final String clientId;

  /// serveren har ffmpeg: kanalene går via den (tilbakespoling, seere og «Ta over»)
  bool ffmpeg;

  /// serveren lar appen se TV direkte: leverandørens strøm uendret (videresendt, så passordet blir på serveren),
  /// mens serveren holder styr på tilkoblingen («Ta over» og seere). Brukes når serveren kan det (2.1.4).
  bool direct = false;

  /// hvor mange minutter serveren tar vare på (PEAG_TIMESHIFT_MIN), så du kan pause og spole tilbake
  int timeshiftMinutes = 0;

  List<Channel>? _channels;
  DateTime? _channelsAt;
  List<Category>? _categories;
  final Map<VodKind, VodCatalog> _catalogs = {};

  /// «192.168.1.10:8766» → «http://192.168.1.10:8766»
  static String normalize(String raw) {
    var text = raw.trim();
    if (text.isEmpty) throw const SourceException('Skriv inn adressen til Fyrlys-serveren');
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(text)) text = 'http://$text';
    final u = Uri.tryParse(text);
    if (u == null || u.host.isEmpty) throw const SourceException('Ugyldig adresse');
    var path = u.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final host = u.host.contains(':') ? '[${u.host}]' : u.host;
    return '${u.scheme.toLowerCase()}://$host${u.hasPort ? ':${u.port}' : ''}$path';
  }

  static Future<FyrlysSource> connect(String address, {http.Client? client}) async {
    final src = FyrlysSource(base: normalize(address), client: client);
    try {
      await src.prepare();
      final status = await src._get('/api/xtream/status');
      if (status is! Map || status['linked'] != true) {
        throw const SourceException('Fyrlys-serveren er ikke logget inn hos IPTV-leverandøren ennå. Logg inn på nettsiden først.');
      }
      return src;
    } on SourceException {
      src.dispose();
      rethrow;
    }
  }

  @override
  String get kind => 'fyrlys';

  @override
  String get label => 'Fyrlys-server ${Uri.tryParse(base)?.authority ?? base}';

  @override
  Map<String, String> get httpHeaders => const {};

  @override
  bool get sharedFavorites => true;

  static Object? _json(http.Response r) {
    try {
      return jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
    } on FormatException {
      return null;
    }
  }

  static String _error(Object? body, int status) =>
      body is Map && body['error'] != null ? '${body['error']}' : 'Fyrlys-serveren svarte HTTP $status';

  Future<Object?> _get(String path, {Duration timeout = const Duration(seconds: 30)}) async {
    final http.Response r;
    try {
      r = await _http.get(Uri.parse('$base$path')).timeout(timeout);
    } on Exception {
      throw const SourceException('Får ikke kontakt med Fyrlys-serveren');
    }
    final body = _json(r);
    if (r.statusCode >= 400) throw SourceException(_error(body, r.statusCode));
    return body;
  }

  @override
  Future<void> prepare() async {
    final http.Response r;
    try {
      r = await _http.get(Uri.parse('$base/api/streams/info')).timeout(const Duration(seconds: 15));
    } on Exception {
      throw const SourceException('Får ikke kontakt med Fyrlys-serveren');
    }
    final info = _json(r);
    if (r.statusCode != 200 || info is! Map || info['name'] != 'Fyrlys') {
      throw const SourceException('Fant ikke Fyrlys på den adressen');
    }
    ffmpeg = info['ffmpeg'] == true;
    direct = info['direct'] == true;
    final shift = info['timeshift_min'];
    timeshiftMinutes = shift is num ? shift.toInt() : 0;
  }

  @override
  Future<Account> account() async {
    final s = await _get('/api/xtream/status');
    final m = s is Map ? s : const <Object?, Object?>{};
    final exp = _int(m['exp']);
    return Account(
      user: '${m['user'] ?? ''}',
      host: '${m['host'] ?? ''}',
      status: '${m['status'] ?? ''}',
      expires: exp > 0 ? DateTime.fromMillisecondsSinceEpoch(exp * 1000) : null,
      maxConnections: _int(m['max']),
      activeConnections: _int(m['active']),
    );
  }

  @override
  Future<List<Category>> categories({bool force = false}) async {
    final cached = _categories;
    if (!force && cached != null) return cached;
    final d = await _get('/api/xtream/categories?kind=live', timeout: const Duration(minutes: 2));
    final cats = d is Map ? d['categories'] : null;
    final list = [
      for (final c in cats is List ? cats : const [])
        if (c is Map) Category(id: '${c['id']}', name: '${c['name'] ?? ''}', count: _int(c['count'])),
    ];
    _categories = list;
    return list;
  }

  static Channel _channel(Map<Object?, Object?> it) => Channel(
        id: '${it['id']}',
        name: '${it['name'] ?? ''}',
        categoryId: '${it['cat'] ?? ''}',
        icon: it['icon'] is String ? it['icon'] as String : null,
        number: it['num']?.toString(),
        hasEpg: it['epg'] != false,
      );

  @override
  Future<List<Channel>> channels({bool force = false}) async {
    final at = _channelsAt;
    final cached = _channels;
    if (!force && cached != null && at != null && DateTime.now().difference(at) < const Duration(minutes: 30)) {
      return cached;
    }
    // Serveren deler lista i sider. Den første sier hvor mange det er; resten hentes seks om gangen.
    final first = await _get('/api/xtream/streams?kind=live&start=0', timeout: const Duration(minutes: 2));
    if (first is! Map) throw const SourceException('Uventet svar fra Fyrlys-serveren');
    final items = <Object?>[if (first['items'] is List) ...first['items'] as List];
    final total = _int(first['total']);
    final page = _int(first['page']) > 0 ? _int(first['page']) : 120;
    final starts = [for (var s = page; s < total; s += page) s];
    for (var i = 0; i < starts.length; i += 6) {
      final chunk = starts.sublist(i, min(i + 6, starts.length));
      final pages = await Future.wait(chunk.map((s) => _get('/api/xtream/streams?kind=live&start=$s')));
      for (final p in pages) {
        if (p is Map && p['items'] is List) items.addAll(p['items'] as List);
      }
    }
    final list = [for (final it in items) if (it is Map) _channel(it)];
    _channels = list;
    _channelsAt = DateTime.now();
    return list;
  }

  @override
  Future<List<EpgEntry>> epg(String channelId, {int limit = 6}) async {
    final d = await _get('/api/xtream/epg?id=${Uri.encodeQueryComponent(channelId)}&limit=$limit');
    final list = d is Map ? d['epg'] : null;
    return [
      for (final e in list is List ? list : const [])
        if (e is Map && e['start'] is num && e['stop'] is num)
          EpgEntry(
            title: '${e['title'] ?? ''}',
            description: '${e['desc'] ?? ''}',
            start: DateTime.fromMillisecondsSinceEpoch((e['start'] as num).toInt() * 1000),
            stop: DateTime.fromMillisecondsSinceEpoch((e['stop'] as num).toInt() * 1000),
          ),
    ];
  }

  @override
  String? logoUrl(String? icon) =>
      icon == null || icon.isEmpty ? null : '$base/api/xtream/img?u=${Uri.encodeQueryComponent(icon)}';

  @override
  Future<PlayTarget> open(Channel channel, {bool takeOver = false}) async {
    final id = channel.id;
    if (direct) {
      // Spør først (og «Ta over» bare her); så henter avspilleren strømmen uendret via serverens mellomstasjon,
      // og appen sier fra hvert 10. sekund at den fortsatt ser på.
      final beat = '$base/api/live/$id/direct?c=$clientId';
      final http.Response r;
      try {
        r = await _http.get(Uri.parse(takeOver ? '$beat&force=1' : beat)).timeout(const Duration(seconds: 15));
      } on Exception {
        throw const SourceException('Får ikke kontakt med Fyrlys-serveren');
      }
      if (r.statusCode != 200) _throwFor(r);
      return PlayTarget(
        ['$base/api/xtream/hls/$id.m3u8?c=$clientId', '$base/api/xtream/file/live/$id.ts?c=$clientId'],
        keepAlive: beat,
        localShift: true,
      );
    }
    if (!ffmpeg) {
      return PlayTarget(['$base/api/xtream/hls/$id.m3u8', '$base/api/xtream/file/live/$id.ts'], localShift: true);
    }
    final url = '$base/api/live/$id/index.m3u8?c=$clientId';
    // Spør først. «Alle tilkoblinger i bruk» og «Ta over» håndteres her, én gang. Adressen avspilleren henter
    // spillelista fra, har aldri «ta over» – ellers ville den tatt tilkoblingen tilbake hvert 2. sekund.
    final http.Response r;
    try {
      r = await _http.get(Uri.parse(takeOver ? '$url&force=1' : url)).timeout(const Duration(seconds: 45));
    } on Exception {
      throw const SourceException('Får ikke kontakt med Fyrlys-serveren');
    }
    if (r.statusCode == 200) return PlayTarget([url], timeshift: Duration(minutes: timeshiftMinutes));
    _throwFor(r);
  }

  /// 409 «busy» blir BusyException (noen har tatt over), annet en SourceException.
  static Never _throwFor(http.Response r) {
    final body = _json(r);
    if (r.statusCode == 409 && body is Map && body['code'] == 'busy') {
      final names = body['busy'];
      throw BusyException(_error(body, 409), [for (final n in names is List ? names : const []) '$n']);
    }
    throw SourceException(_error(body, r.statusCode));
  }

  /// adressene til serveren har ingen innlogging i seg
  @override
  String redact(String text) => text;

  @override
  Future<LiveWindow?> liveWindow(String url) async {
    final http.Response r;
    try {
      r = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    } on Exception {
      throw const SourceException('Får ikke kontakt med Fyrlys-serveren');
    }
    if (r.statusCode != 200) _throwFor(r);
    return parseLiveWindow(utf8.decode(r.bodyBytes, allowMalformed: true));
  }

  @override
  Future<void> stillWatching(PlayTarget target) async {
    final url = target.keepAlive;
    if (url == null) return;
    final http.Response r;
    try {
      r = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    } on Exception {
      return; // et nettverksblaff stopper ikke bildet; neste gang prøves det igjen
    }
    if (r.statusCode == 409) _throwFor(r);
  }

  @override
  Future<void> close(Channel channel) async {
    if (!ffmpeg && !direct) return;
    try {
      await _http.post(Uri.parse('$base/api/live/${channel.id}/stop?c=$clientId')).timeout(const Duration(seconds: 5));
    } on Exception {
      // serveren stopper kanalen selv etter 40 sekunder uten seere
    }
  }

  static Favorites? _favorites(Object? d) {
    if (d is! Map) return null;
    final favs = d['favs'];
    final cats = d['cats'];
    return Favorites(
      channels: [for (final f in favs is List ? favs : const []) if (f is Map) _channel(f)],
      categories: [for (final c in cats is List ? cats : const []) '$c'],
    );
  }

  @override
  Future<Favorites?> loadFavorites() async => _favorites(await _get('/api/streams/favs'));

  @override
  Future<Favorites?> changeFavorites(Map<String, Object?> change) async {
    final http.Response r;
    try {
      r = await _http
          .put(Uri.parse('$base/api/streams/favs'),
              headers: const {'Content-Type': 'application/json'}, body: jsonEncode(change))
          .timeout(const Duration(seconds: 15));
    } on Exception {
      throw const SourceException('Klarte ikke å lagre favorittene på serveren');
    }
    final body = _json(r);
    if (r.statusCode != 200) throw SourceException(_error(body, r.statusCode));
    return _favorites(body);
  }

  // ── filmer og serier (serveren filtrerer, sorterer og deler i sider) ──

  @override
  Future<VodCatalog> vodCatalog(VodKind kind, {bool force = false}) async {
    final cached = _catalogs[kind];
    if (!force && cached != null) return cached;
    final d = await _get('/api/xtream/categories?kind=${kind.api}', timeout: const Duration(minutes: 3));
    final cats = d is Map ? d['categories'] : null;
    final catalog = VodCatalog(
      categories: [
        for (final c in cats is List ? cats : const [])
          if (c is Map) VodCategory(id: '${c['id']}', name: _text(c['name']), count: _int(c['count'])),
      ],
      total: d is Map ? _int(d['total']) : 0,
    );
    _catalogs[kind] = catalog;
    return catalog;
  }

  static VodItem _vodItem(Map<Object?, Object?> it) => VodItem(
        id: '${it['id']}',
        name: _text(it['name']),
        categoryId: _text(it['cat']),
        icon: _url(it['icon']),
        ext: _text(it['ext']).isEmpty ? 'mp4' : _text(it['ext']),
        rating: _double(it['rating']),
        year: _text(it['year']).isEmpty ? null : _text(it['year']),
        plot: _text(it['plot']),
        added: _int(it['added']),
      );

  @override
  Future<VodPage> vodPage(VodKind kind,
      {String category = '', String query = '', VodSort sort = VodSort.provider, int start = 0}) async {
    final q = Uri(queryParameters: {
      'kind': kind.api,
      'cat': category,
      'q': query,
      'sort': sort.api,
      'start': '$start',
    }).query;
    final d = await _get('/api/xtream/streams?$q', timeout: const Duration(minutes: 3));
    if (d is! Map) throw const SourceException('Uventet svar fra Fyrlys-serveren');
    final items = d['items'];
    return VodPage(
      items: [for (final it in items is List ? items : const []) if (it is Map) _vodItem(it)],
      total: _int(d['total']),
    );
  }

  @override
  Future<MovieInfo> movieInfo(String id) async {
    final d = await _get('/api/xtream/vod?id=${Uri.encodeQueryComponent(id)}');
    final m = d is Map ? d : const <Object?, Object?>{};
    return MovieInfo(
      plot: _text(m['plot']),
      genre: _text(m['genre']),
      year: _text(m['year']),
      duration: _text(m['duration']),
      seconds: _intOrNull(m['seconds']) ?? 0,
      cast: _text(m['cast']),
      director: _text(m['director']),
      name: _text(m['name']),
      backdrop: _url(m['backdrop']),
      age: _text(m['age']),
      country: _text(m['country']),
      trailer: _text(m['trailer']),
      tech: MediaTech(
        height: _intOrNull(m['height']) ?? 0,
        videoCodec: _text(m['vcodec']),
        hdr: m['hdr'] == true,
        audioCodec: _text(m['acodec']),
        channels: _intOrNull(m['channels']) ?? 0,
      ),
    );
  }

  @override
  Future<SeriesInfo> seriesInfo(String id) async {
    final d = await _get('/api/xtream/series?id=${Uri.encodeQueryComponent(id)}');
    if (d is! Map) throw const SourceException('Fant ikke serien');
    final seasons = d['seasons'];
    return SeriesInfo(
      name: _text(d['name']),
      cover: _url(d['cover']),
      backdrop: _url(d['backdrop']),
      plot: _text(d['plot']),
      genre: _text(d['genre']),
      year: _text(d['year']),
      rating: _double(d['rating']),
      cast: _text(d['cast']),
      director: _text(d['director']),
      trailer: _text(d['trailer']),
      seasons: [
        for (final s in seasons is List ? seasons : const [])
          if (s is Map)
            Season(
              number: _text(s['season']),
              episodes: [
                for (final e in s['episodes'] is List ? s['episodes'] as List : const [])
                  if (e is Map)
                    Episode(
                      id: '${e['id']}',
                      title: _text(e['title']),
                      number: _intOrNull(e['ep']),
                      ext: _text(e['ext']).isEmpty ? 'mp4' : _text(e['ext']),
                      image: _url(e['img']),
                      plot: _text(e['plot']),
                      duration: _text(e['duration']),
                      seconds: _intOrNull(e['seconds']) ?? 0,
                    ),
              ],
            ),
      ],
    );
  }

  @override
  String movieUrl(VodItem movie) => '$base/api/xtream/file/vod/${movie.id}.${movie.ext}';

  @override
  String episodeUrl(Episode episode) => '$base/api/xtream/file/series/${episode.id}.${episode.ext}';

  @override
  Map<String, String> toPrefs() => {'kind': kind, 'base': base, 'client': clientId};

  @override
  void dispose() => _http.close();
}
