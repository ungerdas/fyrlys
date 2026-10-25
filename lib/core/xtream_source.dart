import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'source.dart';

/// Mange IPTV-leverandører avviser ukjente klienter, så appen presenterer seg som VLC, slik nettversjonen gjør.
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
  return XtreamLogin('${u.scheme.toLowerCase()}://${u.host}$port$path', u.queryParameters['username'], u.queryParameters['password']);
}

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

/// IPTV-leverandøren direkte (Xtream Codes), uten Fyrlys-serveren.
class XtreamSource implements TvSource {
  XtreamSource({required this.server, required this.user, required this.password, http.Client? client})
      : _http = client ?? http.Client();

  final String server;
  final String user;
  final String password;
  final http.Client _http;
  Map<Object?, Object?>? _info;
  List<Channel>? _channels;
  DateTime? _channelsAt;
  List<Category>? _categories;

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
  bool get sharedFavorites => false;

  Future<Object?> _api(String? action, [Map<String, String> params = const {}]) async {
    final uri = Uri.parse('$server/player_api.php').replace(queryParameters: {
      'username': user,
      'password': password,
      if (action != null) 'action': action,
      ...params,
    });
    final http.Response r;
    try {
      r = await _http.get(uri, headers: httpHeaders).timeout(const Duration(seconds: 60));
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
    final ui = info is Map ? info['user_info'] : null;
    return ui is Map ? ui : null;
  }

  @override
  Future<void> prepare() async {}

  @override
  Future<Account> account() async {
    _info ??= await _userInfo();
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
    final raw = await _api('get_live_streams');
    final list = <Channel>[];
    if (raw is List) {
      for (final s in raw) {
        if (s is! Map || s['stream_id'] == null) continue;
        final icon = s['stream_icon'];
        final epgId = s['epg_channel_id'];
        list.add(Channel(
          id: '${s['stream_id']}',
          name: '${s['name'] ?? ''}'.trim(),
          categoryId: '${s['category_id']}',
          icon: icon is String && (icon.startsWith('http://') || icon.startsWith('https://')) ? icon : null,
          number: s['num']?.toString(),
          hasEpg: epgId != null && '$epgId'.isNotEmpty,
        ));
      }
    }
    _channels = list;
    _channelsAt = DateTime.now();
    return list;
  }

  @override
  Future<List<EpgEntry>> epg(String channelId) async {
    final d = await _api('get_short_epg', {'stream_id': channelId, 'limit': '8'});
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
  Future<PlayTarget> open(Channel channel, {bool takeOver = false}) async {
    // HLS fra leverandøren starter ved direktepunktet; MPEG-TS er reserven
    final base = '$server/live/$user/$password/${channel.id}';
    return PlayTarget(['$base.m3u8', '$base.ts']);
  }

  @override
  Future<void> close(Channel channel) async {}

  @override
  Future<Favorites?> loadFavorites() async => null;

  @override
  Future<Favorites?> changeFavorites(Map<String, Object?> change) async => null;

  @override
  Map<String, String> toPrefs() => {'kind': kind, 'server': server, 'user': user, 'password': password};

  @override
  void dispose() => _http.close();
}
