import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import 'failure.dart' show httpStatus;
import 'models.dart';
import 'source.dart';
import 'vod.dart';

/// Mange IPTV-leverandører avviser ukjente klienter, så appen presenterer seg som VLC.
const xtreamUserAgent = 'VLC/3.0.21 LibVLC/3.0.21';

class XtreamLogin {
  const XtreamLogin(this.server, this.user, this.password);

  final String server;
  final String? user;
  final String? password;
}

final _scheme = RegExp(r'^https?://', caseSensitive: false);

/// Godtar «host:port», «http://host:port» og hele M3U-lenker (get.php?username=…&password=…).
XtreamLogin cleanServer(String raw) {
  var text = raw.trim();
  if (text.isEmpty) throw const SourceException('Skriv inn serveradressen');
  if (!_scheme.hasMatch(text)) text = 'http://$text';
  final u = Uri.tryParse(text);
  if (u == null || u.host.isEmpty) throw const SourceException('Ugyldig serveradresse');
  var path = u.path;
  for (final tail in const ['get.php', 'player_api.php', 'xmltv.php']) {
    if (path.endsWith(tail)) path = path.substring(0, path.length - tail.length);
  }
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  final port = u.hasPort ? ':${u.port}' : '';
  return XtreamLogin('${u.scheme.toLowerCase()}://${hostOf(u)}$port$path', u.queryParameters['username'], u.queryParameters['password']);
}

/// Vertsnavnet slik det skrives i en adresse: IPv6 i klammer («[fe80::1]»).
String hostOf(Uri u) => u.host.contains(':') ? '[${u.host}]' : u.host;

/// Tekst i EPG-en er base64 hos de fleste leverandører; det som ikke er det, brukes som det er.
String decodeBase64Text(Object? value) {
  if (value == null) return '';
  final text = '$value'.trim();
  if (text.isEmpty) return '';
  try {
    return utf8.decode(base64.decode(text), allowMalformed: true).trim();
  } on FormatException {
    return text;
  }
}

double? _number(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

DateTime _time(double seconds) => DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round());

String _text(Object? v) => v == null ? '' : '$v'.trim();

String? _url(Object? v) => v is String && (v.startsWith('http://') || v.startsWith('https://')) ? v : null;

final _extRe = RegExp(r'^[a-z0-9]{2,5}$');

String _ext(Object? v) {
  final e = _text(v).toLowerCase();
  return _extRe.hasMatch(e) ? e : 'mp4';
}

/// Filmer og serier fra player_api.php.
List<VodItem> parseVodItems(VodKind kind, Object? raw) => [
      for (final s in raw is List ? raw : const [])
        if (s is Map && (kind == VodKind.series ? s['series_id'] : s['stream_id']) != null)
          kind == VodKind.series
              ? VodItem(
                  id: '${s['series_id']}',
                  name: _text(s['name']),
                  categoryId: _text(s['category_id']),
                  icon: _url(s['cover']),
                  rating: _number(s['rating']),
                  year: () {
                    final y = _text(s['releaseDate'] ?? s['release_date']);
                    return y.length >= 4 ? y.substring(0, 4) : null;
                  }(),
                  plot: _text(s['plot']),
                  added: _number(s['last_modified'])?.toInt() ?? 0,
                )
              : VodItem(
                  id: '${s['stream_id']}',
                  name: _text(s['name']),
                  categoryId: _text(s['category_id']),
                  icon: _url(s['stream_icon']),
                  ext: _ext(s['container_extension']),
                  rating: _number(s['rating']),
                  added: _number(s['added'])?.toInt() ?? 0,
                ),
    ];

/// Det første bakgrunnsbildet (backdrop_path er en liste hos de fleste, en tekst hos noen).
String? firstBackdrop(Map<Object?, Object?> info) {
  final b = info['backdrop_path'];
  if (b is List) {
    for (final u in b) {
      final url = _url(u);
      if (url != null) return url;
    }
    return null;
  }
  return _url(b);
}

/// Kvaliteten leverandøren oppgir for en fil (video/audio i get_vod_info).
MediaTech mediaTech(Map<Object?, Object?> info) {
  final v = info['video'] is Map ? info['video'] as Map : const <Object?, Object?>{};
  final a = info['audio'] is Map ? info['audio'] as Map : const <Object?, Object?>{};
  final transfer = _text(v['color_transfer']).toLowerCase();
  return MediaTech(
    height: _number(v['height'])?.toInt() ?? 0,
    videoCodec: _text(v['codec_name']),
    hdr: transfer == 'smpte2084' || transfer == 'arib-std-b67',
    audioCodec: _text(a['codec_name']),
    channels: _number(a['channels'])?.toInt() ?? 0,
  );
}

/// get_series_info: sesongene kommer som et kart (sesong → episoder) eller, hos noen, som en liste av lister.
SeriesInfo parseSeriesInfo(Object? d) {
  if (d is! Map) throw const SourceException('Fant ikke serien');
  final info = d['info'] is Map ? d['info'] as Map : const <Object?, Object?>{};
  final rawEpisodes = d['episodes'];
  final Map<Object?, Object?> bySeason = rawEpisodes is List
      ? <Object?, Object?>{for (var i = 0; i < rawEpisodes.length; i++) '${i + 1}': rawEpisodes[i]}
      : rawEpisodes is Map
          ? rawEpisodes
          : const <Object?, Object?>{};
  final seasons = <Season>[];
  if (bySeason.isNotEmpty) {
    final keys = [...bySeason.keys]..sort((a, b) => (_number(a) ?? 0).compareTo(_number(b) ?? 0));
    for (final k in keys) {
      final eps = bySeason[k];
      seasons.add(Season(
        number: '$k',
        episodes: [
          for (final e in eps is List ? eps : const [])
            if (e is Map)
              Episode(
                id: '${e['id']}',
                title: _text(e['title']),
                number: _number(e['episode_num'])?.toInt(),
                ext: _ext(e['container_extension']),
                image: e['info'] is Map ? _url((e['info'] as Map)['movie_image']) : null,
                plot: e['info'] is Map ? _text((e['info'] as Map)['plot']) : '',
                duration: e['info'] is Map ? _text((e['info'] as Map)['duration']) : '',
                seconds: e['info'] is Map ? (_number((e['info'] as Map)['duration_secs'])?.toInt() ?? 0) : 0,
              ),
        ],
      ));
    }
  }
  final year = _text(info['releaseDate'] ?? info['release_date']);
  return SeriesInfo(
    name: _text(info['name']),
    cover: _url(info['cover']),
    backdrop: firstBackdrop(info),
    cast: _text(info['cast']),
    director: _text(info['director']),
    trailer: _text(info['youtube_trailer']),
    plot: _text(info['plot']),
    genre: _text(info['genre']),
    year: year.length >= 4 ? year.substring(0, 4) : year,
    rating: _number(info['rating']),
    seasons: seasons,
  );
}

// ── TV-arkivet ──

final _clockRe = RegExp(r'^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2}))?');

/// Hvor langt serverens klokke er foran UTC: time_now (serverens tid) mot timestamp_now i server_info, rundet til
/// nærmeste kvarter. null når serveren ikke sier det.
Duration? serverClockOffset(Object? serverInfo) {
  if (serverInfo is! Map) return null;
  final stamp = _number(serverInfo['timestamp_now']);
  final m = _clockRe.firstMatch(_text(serverInfo['time_now']));
  if (stamp == null || m == null) return null;
  int n(int i) => int.parse(m.group(i) ?? '0');
  final wall = DateTime.utc(n(1), n(2), n(3), n(4), n(5), n(6));
  final diff = wall.difference(DateTime.fromMillisecondsSinceEpoch((stamp * 1000).round(), isUtc: true));
  final quarters = (diff.inSeconds / 900).round();
  if (quarters.abs() > 14 * 4) return null;
  return Duration(minutes: quarters * 15);
}

/// Serverens klokke da [t] var. Går den likt med PC-en nå (eller sier ikke serveren noe), brukes PC-ens tidssone
/// med sommertid og vintertid; ellers serverens forskjell slik den er nå.
Duration archiveOffset(DateTime t, Duration? server, {DateTime? now}) {
  final local = t.toLocal().timeZoneOffset;
  if (server == null || server == (now ?? DateTime.now()).timeZoneOffset) return local;
  return server;
}

/// «2026-10-26:20-00»: starten i arkivet slik Xtream vil ha den, i serverens tid.
String xtreamTime(DateTime t, Duration offset) {
  final s = t.toUtc().add(offset);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${s.year}-${two(s.month)}-${two(s.day)}:${two(s.hour)}-${two(s.minute)}';
}

/// Programmene i arkivet fra get_simple_data_table: det som har begynt de siste [days] dagene, eldst først.
/// has_archive: 0 betyr at leverandøren ikke har det; det som går nå, kan alltid ses fra start.
List<EpgEntry> parseArchive(Object? d, {required DateTime now, required int days}) {
  final listings = d is Map ? d['epg_listings'] : null;
  final from = now.subtract(Duration(days: days));
  final out = <EpgEntry>[];
  for (final e in listings is List ? listings : const []) {
    if (e is! Map) continue;
    final start = _number(e['start_timestamp']);
    final stop = _number(e['stop_timestamp']);
    if (start == null || stop == null) continue;
    final a = _time(start);
    final b = _time(stop);
    if (!b.isAfter(a) || a.isAfter(now) || a.isBefore(from)) continue;
    final flag = e['has_archive'];
    final saved = flag == null || flag == true || '$flag' == '1';
    out.add(EpgEntry(
      title: decodeBase64Text(e['title']),
      description: decodeBase64Text(e['description']),
      start: a,
      stop: b,
      inArchive: saved || b.isAfter(now),
    ));
  }
  out.sort((a, b) => a.start.compareTo(b.start));
  return out;
}

/// IPTV-leverandøren direkte (Xtream Codes).
class XtreamSource implements TvSource {
  XtreamSource({required this.server, required this.user, required this.password, http.Client? client})
      : _http = client ?? http.Client();

  final String server;
  final String user;
  final String password;
  final http.Client _http;
  Map<Object?, Object?>? _info;

  /// serverens klokke mot UTC (for TV-arkivet), og om den er spurt
  Duration? _clock;
  bool _clockAsked = false;
  List<Channel>? _channels;
  DateTime? _channelsAt;
  List<Category>? _categories;
  final Map<VodKind, ({DateTime at, List<VodCategory> categories, List<VodItem> items})> _vod = {};
  final Map<VodKind, Future<({List<VodCategory> categories, List<VodItem> items})>> _vodLoading = {};

  /// store lister (alle kanaler, filmer eller serier) kan være mange megabyte på en treg linje
  static const _bigList = Duration(minutes: 3);

  /// Sjekker innloggingen hos leverandøren før den lagres.
  static Future<XtreamSource> login(String serverInput, String user, String password, {http.Client? client}) async {
    final l = cleanServer(serverInput);
    final u = user.trim().isNotEmpty ? user.trim() : (l.user ?? '').trim();
    final p = password.trim().isNotEmpty ? password.trim() : (l.password ?? '').trim();
    if (u.isEmpty || p.isEmpty) throw const SourceException('Skriv inn brukernavn og passord');
    final src = XtreamSource(server: l.server, user: u, password: p, client: client);
    try {
      final info = await src._userInfo();
      if (info == null || '${info['auth']}' != '1') throw const SourceException('Feil brukernavn eller passord');
      src._info = info;
      return src;
    } on SourceException {
      src.dispose();
      rethrow;
    }
  }

  @override
  String get kind => 'xtream';

  @override
  String get label => '$user på ${Uri.tryParse(server)?.host ?? server}';

  @override
  Map<String, String> get httpHeaders => const {'User-Agent': xtreamUserAgent};

  @override
  bool get hasVod => true;

  Future<Object?> _api(String? action, [Map<String, String> params = const {}, Duration timeout = const Duration(seconds: 60)]) async {
    final uri = Uri.parse('$server/player_api.php').replace(queryParameters: {
      'username': user,
      'password': password,
      if (action != null) 'action': action,
      ...params,
    });
    final http.Response r;
    try {
      r = await _http.get(uri, headers: httpHeaders).timeout(timeout);
    } on Exception {
      throw const SourceException('Får ikke kontakt med IPTV-serveren');
    }
    if (r.statusCode == 401 || r.statusCode == 403) throw const SourceException('Serveren avviste innloggingen');
    if (r.statusCode >= 400) throw SourceException('IPTV-serveren svarte HTTP ${r.statusCode}');
    final text = utf8.decode(r.bodyBytes, allowMalformed: true);
    try {
      // kanallista kan være mange megabyte: tolkes i bakgrunnen, så bildet ikke henger imens
      return text.length > 200000 ? await Isolate.run(() => jsonDecode(text)) : jsonDecode(text);
    } on Object {
      throw const SourceException('Serveren svarte ikke som en Xtream-server');
    }
  }

  Future<Map<Object?, Object?>?> _userInfo() async {
    final info = await _api(null);
    if (info is Map) {
      _clock = serverClockOffset(info['server_info']);
      _clockAsked = true;
    }
    final ui = info is Map ? info['user_info'] : null;
    return ui is Map ? ui : null;
  }

  @override
  Future<Account> account({bool fresh = false}) async {
    if (fresh || _info == null) _info = await _userInfo() ?? _info;
    final u = _info ?? const <Object?, Object?>{};
    final exp = _number(u['exp_date']);
    return Account(
      user: user,
      host: Uri.tryParse(server)?.authority ?? server,
      status: '${u['status'] ?? ''}',
      expires: exp != null && exp > 0 ? _time(exp) : null,
      maxConnections: _number(u['max_connections'])?.toInt() ?? 0,
      activeConnections: _number(u['active_cons'])?.toInt() ?? 0,
    );
  }

  @override
  Future<List<Category>> categories({bool force = false}) async {
    final cached = _categories;
    if (!force && cached != null) return cached;
    final raw = await _api('get_live_categories');
    final list = <Category>[];
    if (raw is List) {
      for (final c in raw) {
        if (c is Map) list.add(Category(id: '${c['category_id']}', name: '${c['category_name'] ?? ''}'));
      }
    }
    _categories = list;
    return list;
  }

  @override
  Future<List<Channel>> channels({bool force = false}) async {
    final at = _channelsAt;
    final cached = _channels;
    if (!force && cached != null && at != null && DateTime.now().difference(at) < const Duration(minutes: 30)) {
      return cached;
    }
    final raw = await _api('get_live_streams', const {}, _bigList);
    final list = <Channel>[];
    if (raw is List) {
      for (final s in raw) {
        if (s is! Map || s['stream_id'] == null) continue;
        final icon = s['stream_icon'];
        final epgId = s['epg_channel_id'];
        // TV-arkivet: tv_archive 1 og hvor mange dager (noen oppgir ikke dagene: minst én)
        final archive = '${s['tv_archive'] ?? ''}' == '1' || s['tv_archive'] == true;
        list.add(Channel(
          id: '${s['stream_id']}',
          name: '${s['name'] ?? ''}'.trim(),
          categoryId: '${s['category_id']}',
          icon: icon is String && (icon.startsWith('http://') || icon.startsWith('https://')) ? icon : null,
          number: s['num']?.toString(),
          hasEpg: epgId != null && '$epgId'.isNotEmpty,
          archiveDays: archive ? math.max(1, _number(s['tv_archive_duration'])?.toInt() ?? 1) : 0,
        ));
      }
    }
    _channels = list;
    _channelsAt = DateTime.now();
    return list;
  }

  @override
  Future<List<EpgEntry>> epg(String channelId, {int limit = 6}) async {
    final d = await _api('get_short_epg', {'stream_id': channelId, 'limit': '${limit < 8 ? 8 : limit}'});
    final listings = d is Map ? d['epg_listings'] : null;
    final now = DateTime.now();
    final out = <EpgEntry>[];
    if (listings is List) {
      for (final e in listings) {
        if (e is! Map) continue;
        final start = _number(e['start_timestamp']);
        final stop = _number(e['stop_timestamp']);
        if (start == null || stop == null || !_time(stop).isAfter(now)) continue;
        out.add(EpgEntry(
          title: decodeBase64Text(e['title']),
          description: decodeBase64Text(e['description']),
          start: _time(start),
          stop: _time(stop),
        ));
      }
    }
    out.sort((a, b) => a.start.compareTo(b.start));
    return out;
  }

  @override
  String? logoUrl(String? icon) => icon;

  @override
  Future<PlayTarget> open(Channel channel) async {
    // HLS fra leverandøren starter ved direktepunktet; MPEG-TS er reserven
    final base = '$server/live/$_creds/${channel.id}';
    // rett fra leverandøren: avspilleren tar vare på det siste selv, så det går an å pause og spole tilbake
    return PlayTarget(['$base.m3u8', '$base.ts'], localShift: true);
  }

  // ── TV-arkivet ──

  @override
  Future<List<EpgEntry>> archive(Channel channel) async {
    if (!channel.hasArchive) return const [];
    final d = await _api('get_simple_data_table', {'stream_id': channel.id});
    return parseArchive(d, now: DateTime.now(), days: channel.archiveDays);
  }

  /// Serverens klokke (spurt én gang; null når den ikke sier det, og da brukes PC-ens).
  Future<Duration?> _serverClock() async {
    if (!_clockAsked) {
      try {
        _info = await _userInfo() ?? _info;
      } on SourceException {
        // PC-ens klokke
      }
      _clockAsked = true;
    }
    return _clock;
  }

  @override
  Future<ArchiveClip> archiveClip(Channel channel, EpgEntry program) async {
    if (!channel.hasArchive) throw const SourceException('Kanalen har ikke TV-arkiv');
    final clock = await _serverClock();
    return ArchiveClip(
      start: program.start,
      stop: program.stop,
      urlsAt: (from) {
        // på minuttet (arkivet ligger i biter på ett minutt hos leverandøren), og ut programmet
        final ms = program.start.add(from < Duration.zero ? Duration.zero : from).millisecondsSinceEpoch;
        final at = DateTime.fromMillisecondsSinceEpoch(ms - ms % 60000);
        final minutes = math.max(1, (program.stop.difference(at).inSeconds / 60).ceil());
        final base = '$server/timeshift/$_creds/$minutes/${xtreamTime(at, archiveOffset(at, clock))}/${channel.id}';
        return (urls: ['$base.m3u8', '$base.ts'], from: at.difference(program.start));
      },
    );
  }

  // ── filmer og serier: hele lista hentes (mellomlagret 30 min), og appen filtrerer og deler i sider ──

  /// Kategoriene og hele lista for filmer eller serier. Spør to deler av appen samtidig (kategoriene og første
  /// side), lastes lista bare ned én gang.
  Future<({List<VodCategory> categories, List<VodItem> items})> _vodLists(VodKind kind, {bool force = false}) {
    final running = _vodLoading[kind];
    if (running != null) return running;
    final f = _loadVodLists(kind, force: force);
    _vodLoading[kind] = f;
    return f.whenComplete(() => _vodLoading.remove(kind));
  }

  Future<({List<VodCategory> categories, List<VodItem> items})> _loadVodLists(VodKind kind, {bool force = false}) async {
    final hit = _vod[kind];
    if (!force && hit != null && DateTime.now().difference(hit.at) < const Duration(minutes: 30)) {
      return (categories: hit.categories, items: hit.items);
    }
    final movies = kind == VodKind.movies;
    final rawCats = await _api(movies ? 'get_vod_categories' : 'get_series_categories');
    final rawItems = await _api(movies ? 'get_vod_streams' : 'get_series', const {}, _bigList);
    final categories = [
      for (final c in rawCats is List ? rawCats : const [])
        if (c is Map) VodCategory(id: '${c['category_id']}', name: _text(c['category_name'])),
    ];
    final items = parseVodItems(kind, rawItems);
    _vod[kind] = (at: DateTime.now(), categories: categories, items: items);
    return (categories: categories, items: items);
  }

  @override
  Future<VodCatalog> vodCatalog(VodKind kind, {bool force = false}) async {
    final l = await _vodLists(kind, force: force);
    return catalogOf(l.categories, l.items);
  }

  @override
  Future<VodPage> vodPage(VodKind kind,
      {String category = '', String query = '', VodSort sort = VodSort.provider, int start = 0}) async {
    final l = await _vodLists(kind);
    return pageOf(l.items, category: category, query: query, sort: sort, start: start);
  }

  @override
  Future<MovieInfo> movieInfo(String id) async {
    final d = await _api('get_vod_info', {'vod_id': id});
    final info = d is Map && d['info'] is Map ? d['info'] as Map : const <Object?, Object?>{};
    final year = _text(info['releasedate'] ?? info['release_date']);
    return MovieInfo(
      plot: _text(info['plot'] ?? info['description']),
      genre: _text(info['genre']),
      year: year.length >= 4 ? year.substring(0, 4) : year,
      duration: _text(info['duration']),
      seconds: _number(info['duration_secs'])?.toInt() ?? 0,
      cast: _text(info['cast'] ?? info['actors']),
      director: _text(info['director']),
      name: _text(info['name']),
      backdrop: firstBackdrop(info),
      age: _text(info['age'] ?? info['mpaa_rating']),
      country: _text(info['country']),
      trailer: _text(info['youtube_trailer']),
      tech: mediaTech(info),
    );
  }

  @override
  Future<SeriesInfo> seriesInfo(String id) async => parseSeriesInfo(await _api('get_series_info', {'series_id': id}));

  @override
  String movieUrl(VodItem movie) => '$server/movie/$_creds/${movie.id}.${movie.ext}';

  @override
  String episodeUrl(Episode episode) => '$server/series/$_creds/${episode.id}.${episode.ext}';

  /// brukernavn og passord i adressene til strømmene (kodet, så `#`, `/` og mellomrom virker)
  String get _creds => '${Uri.encodeComponent(user)}/${Uri.encodeComponent(password)}';

  @override
  Future<int?> streamStatus(String url) => httpStatus(_http, url, httpHeaders);

  @override
  String redact(String text) {
    var out = text;
    for (final secret in {password, Uri.encodeComponent(password), Uri.encodeQueryComponent(password)}) {
      if (secret.length >= 3) out = out.replaceAll(secret, '***');
    }
    for (final name in {user, Uri.encodeComponent(user)}) {
      if (name.length >= 3) out = out.replaceAll('/$name/', '/***/').replaceAll('username=$name', 'username=***');
    }
    return out;
  }

  @override
  Map<String, String> toPrefs() => {'kind': kind, 'server': server, 'user': user, 'password': password};

  @override
  void dispose() => _http.close();
}
