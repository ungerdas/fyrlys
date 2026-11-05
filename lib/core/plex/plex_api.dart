// Plex: innloggingen hos plex.tv (PIN), serverne kontoen har, og API-et på Plex-serveren.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, SocketException;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../../build_info.dart';
import '../../l10n/tr.dart';
import '../../platform.dart';
import 'plex_models.dart';

/// En feil fra Plex med en forklaring som kan vises. [network]: fikk ikke kontakt (ikke et svar fra Plex). [pin]:
/// brukeren i Plex Home trenger PIN-koden, eller den var feil.
class PlexException implements Exception {
  const PlexException(this.message, {this.status, this.network = false, this.pin = false});

  final String message;
  final int? status;
  final bool network;
  final bool pin;

  @override
  String toString() => message;
}

/// «Æsj Ø» → «Aesj O»: HTTP-hoder tåler bare vanlige tegn.
String plexAscii(String text) {
  const map = {'æ': 'ae', 'ø': 'o', 'å': 'a', 'Æ': 'AE', 'Ø': 'O', 'Å': 'A', 'ä': 'a', 'ö': 'o', 'ü': 'u', 'é': 'e'};
  final out = StringBuffer();
  for (final r in text.runes) {
    final c = String.fromCharCode(r);
    if (r >= 0x20 && r < 0x7f) {
      out.write(c);
    } else {
      out.write(map[c] ?? '');
    }
  }
  final s = out.toString().trim();
  return s.isEmpty ? 'Fyrlys' : s;
}

/// Hvem appen er overfor Plex. Sendes med i hver forespørsel (og vises under «Enheter» i Plex-kontoen og i
/// Plex-serverens oversikt over hva som spilles).
class PlexClientInfo {
  const PlexClientInfo({required this.id, this.deviceName = 'Fyrlys'});

  /// fast for denne installasjonen (X-Plex-Client-Identifier)
  final String id;
  final String deviceName;

  Map<String, String> headers([String? token]) => {
        'Accept': 'application/json',
        'X-Plex-Product': 'Fyrlys',
        'X-Plex-Version': appVersion.isEmpty ? '0' : appVersion,
        'X-Plex-Client-Identifier': id,
        'X-Plex-Platform': isAndroid ? 'Android' : 'Windows',
        'X-Plex-Device': isAndroid ? 'Android' : 'Windows',
        'X-Plex-Device-Name': plexAscii(deviceName),
        // overskriftene Plex lager selv («Nylig lagt til …»), på språket i appen
        'X-Plex-Language': appLanguage == 'en' ? 'en' : 'nb',
        if (token != null) 'X-Plex-Token': token,
      };
}

/// En PIN fra plex.tv: du logger inn hos Plex i nettleseren, og appen får innloggingen når du har sagt ja.
class PlexPin {
  const PlexPin({required this.id, required this.code, this.expires});

  final int id;
  final String code;
  final DateTime? expires;
}

bool _networkError(Object e) =>
    e is SocketException || e is TimeoutException || e is http.ClientException || e is HandshakeException;

Object? _json(http.Response res) {
  try {
    return jsonDecode(utf8.decode(res.bodyBytes));
  } on FormatException {
    return null;
  }
}

/// plex.tv: PIN-innloggingen, brukeren og serverne.
class PlexTv {
  PlexTv(this.info, this._http);

  final PlexClientInfo info;
  final http.Client _http;

  static const _api = 'https://plex.tv/api/v2';
  static const _clients = 'https://clients.plex.tv/api/v2';

  Future<http.Response> _send(Future<http.Response> Function() call) async {
    final http.Response res;
    try {
      res = await call().timeout(const Duration(seconds: 15));
    } on Object catch (e) {
      if (!_networkError(e)) rethrow;
      debugPrint('Plex: fikk ikke kontakt med plex.tv ($e)');
      throw PlexException(tr('Fikk ikke kontakt med plex.tv. Sjekk nettet og prøv igjen.'), network: true);
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw PlexException(tr('Plex godtok ikke innloggingen. Koble til Plex på nytt.'), status: res.statusCode);
    }
    return res;
  }

  /// En ny PIN (gjelder i en halvtime).
  Future<PlexPin> createPin() async {
    final res = await _send(() => _http.post(Uri.parse('$_api/pins?strong=true'), headers: info.headers()));
    final j = plexMap(_json(res));
    final id = plexInt(j['id']);
    final code = plexText(j['code']);
    if (res.statusCode >= 400 || id == null || code.isEmpty) {
      throw PlexException(tr('plex.tv svarte ikke som ventet (HTTP {code}).', {'code': res.statusCode}),
          status: res.statusCode);
    }
    return PlexPin(id: id, code: code, expires: DateTime.tryParse(plexText(j['expiresAt'])));
  }

  /// Siden hos Plex der du logger inn og sier ja til Fyrlys.
  String authUrl(PlexPin pin) => 'https://app.plex.tv/auth#?${[
        'clientID=${Uri.encodeQueryComponent(info.id)}',
        'code=${Uri.encodeQueryComponent(pin.code)}',
        '${Uri.encodeQueryComponent('context[device][product]')}=Fyrlys',
      ].join('&')}';

  /// Innloggingen når du har sagt ja (null: ikke ennå). Kaster PlexException når PIN-en er gått ut.
  Future<String?> checkPin(PlexPin pin) async {
    final res = await _send(() => _http.get(Uri.parse('$_api/pins/${pin.id}'), headers: info.headers()));
    if (res.statusCode == 404 || res.statusCode == 410) {
      throw PlexException(tr('Koden gikk ut. Prøv igjen.'), status: res.statusCode);
    }
    if (res.statusCode >= 400) return null;
    final token = plexText(plexMap(_json(res))['authToken']);
    return token.isEmpty ? null : token;
  }

  /// Brukernavnet hos Plex (tomt når det ikke kan hentes).
  Future<String> userName(String token) async {
    try {
      final res = await _send(() => _http.get(Uri.parse('$_api/user'), headers: info.headers(token)));
      final j = plexMap(_json(res));
      final name = plexText(j['username']);
      return name.isNotEmpty ? name : plexText(j['title']);
    } on PlexException catch (e) {
      if (e.status == 401 || e.status == 403) rethrow;
      return '';
    }
  }

  /// Serverne kontoen har tilgang til, egne først.
  Future<List<PlexServer>> servers(String token) async {
    final res = await _send(() => _http.get(
          Uri.parse('$_clients/resources?includeHttps=1&includeRelay=1'),
          headers: info.headers(token),
        ));
    if (res.statusCode >= 400) {
      throw PlexException(tr('plex.tv svarte ikke som ventet (HTTP {code}).', {'code': res.statusCode}),
          status: res.statusCode);
    }
    final raw = _json(res);
    return sortServers([
      for (final j in plexList(raw is List ? raw : plexMap(raw)['MediaContainer']))
        if (PlexServer.fromJson(j) case final s?) s,
    ]);
  }

  /// Brukerne i Plex Home til kontoen med innloggingen [token] (bare den selv når kontoen ikke har et Plex Home).
  Future<List<PlexHomeUser>> homeUsers(String token) async {
    final res = await _send(() => _http.get(Uri.parse('$_clients/home/users'), headers: info.headers(token)));
    if (res.statusCode >= 400) {
      throw PlexException(tr('plex.tv svarte ikke som ventet (HTTP {code}).', {'code': res.statusCode}),
          status: res.statusCode);
    }
    return [
      for (final j in plexList(plexMap(_json(res))['users']))
        if (PlexHomeUser.fromJson(j) case final u?) u,
    ];
  }

  /// Innloggingen til Plex Home-brukeren [uuid], hentet med kontoens innlogging [token] ([pin] når brukeren har PIN).
  /// Feil eller manglende PIN gir en PlexException med [PlexException.pin].
  Future<String> switchUser(String token, String uuid, {String? pin}) async {
    final query = pin == null || pin.isEmpty ? '' : '?pin=${Uri.encodeQueryComponent(pin)}';
    final http.Response res;
    try {
      res = await _http
          .post(Uri.parse('$_clients/home/users/${Uri.encodeComponent(uuid)}/switch$query'), headers: info.headers(token))
          .timeout(const Duration(seconds: 15));
    } on Object catch (e) {
      if (!_networkError(e)) rethrow;
      debugPrint('Plex: fikk ikke kontakt med plex.tv ($e)');
      throw PlexException(tr('Fikk ikke kontakt med plex.tv. Sjekk nettet og prøv igjen.'), network: true);
    }
    final j = _json(res);
    // 1041: PIN-koden mangler eller er feil
    final codes = [for (final e in plexList(plexMap(j)['errors'])) plexInt(e['code'])];
    if (res.statusCode == 403 && (codes.isEmpty || codes.contains(1041))) {
      throw PlexException(tr('Feil PIN-kode. Prøv igjen.'), status: 403, pin: true);
    }
    if (res.statusCode == 401) {
      throw PlexException(tr('Plex godtok ikke innloggingen. Koble til Plex på nytt.'), status: 401);
    }
    final userToken = plexText(plexMap(j)['authToken']);
    if (res.statusCode >= 400 || userToken.isEmpty) {
      throw PlexException(tr('plex.tv svarte ikke som ventet (HTTP {code}).', {'code': res.statusCode}),
          status: res.statusCode);
    }
    return userToken;
  }
}

/// Finner en adresse serveren svarer på: i hjemmenettet først (https, så http), så over nettet, og til sist via Plex
/// (relay). Alle prøves samtidig; null når ingen svarer.
Future<PlexConnection?> pickConnection(PlexServer server, http.Client client, PlexClientInfo info) async {
  final candidates = <PlexConnection>[];
  void add(PlexConnection c) {
    if (c.uri.isNotEmpty && !candidates.any((x) => x.uri == c.uri)) candidates.add(c);
  }

  for (final c in server.connections) {
    add(c);
  }
  for (final c in server.connections) {
    if (c.lanHttp case final h?) add(h);
  }
  if (candidates.isEmpty) return null;
  final probes = {
    for (final c in candidates) c: probeServer(c.uri, server, client, info, timeout: probeTimeout(c)),
  };
  for (final tier in const [0, 1, 2]) {
    final inTier = [for (final c in candidates) if (c.tier == tier) c];
    if (inTier.isEmpty) continue;
    final best = await _bestOf(inTier, probes);
    if (best != null) return best;
  }
  return null;
}

/// Hvor lenge en adresse får på seg: kort i hjemmenettet, lenger over nettet og via Plex.
Duration probeTimeout(PlexConnection c) => switch (c.tier) {
      0 => const Duration(seconds: 3),
      1 => const Duration(seconds: 6),
      _ => const Duration(seconds: 8),
    };

/// Den første som svarer, men https foran http: en http-adresse velges først når ingen https-adresse svarte.
Future<PlexConnection?> _bestOf(List<PlexConnection> list, Map<PlexConnection, Future<bool>> probes) {
  final done = Completer<PlexConnection?>();
  var pending = list.length;
  var securePending = list.where((c) => c.secure).length;
  PlexConnection? plain;
  for (final c in list) {
    unawaited(probes[c]!.then((ok) {
      pending--;
      if (c.secure) securePending--;
      if (done.isCompleted) return;
      if (ok && c.secure) {
        done.complete(c);
        return;
      }
      if (ok) plain ??= c;
      if ((plain != null && securePending == 0) || pending == 0) done.complete(plain);
    }));
  }
  return done.future;
}

/// Svarer serveren på [base]? /identity krever ikke innlogging, så nøkkelen sendes ikke (adressen kan være en helt
/// annen maskin, f.eks. i et annet nett med samme adresser), og det må være samme server.
Future<bool> probeServer(String base, PlexServer server, http.Client client, PlexClientInfo info,
    {Duration timeout = const Duration(seconds: 6)}) async {
  try {
    final res = await client.get(Uri.parse('$base/identity'), headers: info.headers()).timeout(timeout);
    if (res.statusCode != 200) return false;
    final id = plexText(plexMap(plexMap(_json(res))['MediaContainer'])['machineIdentifier']);
    return id == server.id;
  } on Object {
    return false;
  }
}

/// API-et på Plex-serveren, på adressen som virket.
class PlexServerApi {
  PlexServerApi({
    required this.base,
    required this.token,
    required this.info,
    required http.Client client,
    this.tier = 0,
  }) : _http = client;

  final String base;
  final String token;
  final PlexClientInfo info;
  final http.Client _http;

  /// 0: i hjemmenettet, 1: over nettet, 2: via Plex (relay)
  final int tier;

  /// sendes med til filene (avspilleren og Chromecasten), så innloggingen ikke står i adressen
  Map<String, String> get headers => info.headers(token);

  Uri _uri(String path, Map<String, String> query) {
    final uri = Uri.parse('$base$path');
    if (query.isEmpty) return uri;
    return uri.replace(queryParameters: {...uri.queryParameters, ...query});
  }

  /// MediaContainer fra [path] (kaster PlexException).
  Future<Map<String, Object?>> get(String path, [Map<String, String> query = const {}]) async {
    final res = await _request(path, query);
    final j = _json(res);
    if (j == null) throw PlexException(tr('Plex-serveren svarte ikke som ventet.'), status: res.statusCode);
    return plexMap(plexMap(j)['MediaContainer']);
  }

  Future<http.Response> _request(String path, Map<String, String> query, {Duration? timeout}) async {
    final http.Response res;
    try {
      res = await _http.get(_uri(path, query), headers: headers).timeout(timeout ?? const Duration(seconds: 20));
    } on Object catch (e) {
      if (!_networkError(e)) rethrow;
      throw PlexException(tr('Fikk ikke kontakt med Plex-serveren.'), network: true);
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw PlexException(tr('Plex-serveren godtar ikke innloggingen (HTTP {code}). Koble til Plex på nytt i '
          'innstillingene.', {'code': res.statusCode}), status: res.statusCode);
    }
    if (res.statusCode == 404) {
      throw PlexException(tr('Finnes ikke på Plex-serveren lenger (HTTP 404).'), status: 404);
    }
    if (res.statusCode >= 400) {
      throw PlexException(tr('Plex-serveren svarte med en feil (HTTP {code}).', {'code': res.statusCode}),
          status: res.statusCode);
    }
    return res;
  }

  List<PlexItem> _items(Map<String, Object?> container) =>
      [for (final j in plexList(container['Metadata'])) PlexItem.fromJson(j)];

  /// Bibliotekene med filmer og serier.
  Future<List<PlexLibrary>> libraries() async {
    final c = await get('/library/sections');
    return [
      for (final j in plexList(c['Directory']))
        if (j['type'] == 'movie' || j['type'] == 'show') PlexLibrary.fromJson(j),
    ];
  }

  /// En side fra biblioteket, sortert og eventuelt filtrert på sjanger.
  Future<PlexPage> items(PlexLibrary library,
      {PlexSort sort = PlexSort.added, String genre = '', int start = 0, int size = 100}) async {
    final c = await get('/library/sections/${library.key}/all', {
      'type': '${library.apiType}',
      'sort': sort.api(shows: library.shows),
      if (genre.isNotEmpty) 'genre': genre,
      'includeCollections': '0',
      'X-Plex-Container-Start': '$start',
      'X-Plex-Container-Size': '$size',
    });
    final items = _items(c);
    return PlexPage(items: items, total: plexInt(c['totalSize']) ?? (start + items.length));
  }

  /// Sjangrene i et bibliotek.
  Future<List<PlexTag>> genres(PlexLibrary library) async {
    final c = await get('/library/sections/${library.key}/genre');
    return [
      for (final j in plexList(c['Directory']))
        if (plexText(j['key']).isNotEmpty) PlexTag(key: plexText(j['key']), title: plexText(j['title'])),
    ];
  }

  /// «Fortsett å se»: filmer du er midt i og neste episode i seriene du ser på (som på Plex sin egen startside).
  Future<List<PlexItem>> continueWatching() async {
    try {
      return _items(await get('/hubs/continueWatching/items', {'X-Plex-Container-Size': '30'}));
    } on PlexException catch (e) {
      // eldre servere
      if (e.status != 404 && e.status != 400) rethrow;
      return _items(await get('/library/onDeck', {'X-Plex-Container-Size': '30'}));
    }
  }

  /// Det som sist kom i biblioteket (serier: der det sist kom en episode).
  Future<List<PlexItem>> recentlyAdded(PlexLibrary library, {int size = 24}) async =>
      (await items(library, sort: PlexSort.added, size: size)).items;

  /// Radene på Hjem i Plex for [libraries], de samme som på Plex sin egen startside («Nytt fra …», samlinger lagt på
  /// Hjem, «Nylig lagt til …»), uten «Fortsett å se». Tom når serveren ikke har noen der.
  Future<List<PlexHub>> homeHubs(List<PlexLibrary> libraries, {int count = 20}) async {
    if (libraries.isEmpty) return const [];
    final ids = [for (final l in libraries) l.key].join(',');
    final c = await get('/hubs/promoted', {
      'contentDirectoryID': ids,
      'pinnedContentDirectoryID': ids,
      'count': '$count',
      'excludeContinueWatching': '1',
    });
    return parseHubs(c, sections: {for (final l in libraries) l.key});
  }

  /// En side av hele raden [key] («Vis alle»), bare fra bibliotekene i [sections].
  Future<PlexHubPage> hubItems(String key, {required Set<String> sections, int start = 0, int size = 100}) async {
    final c = await get(key, {'X-Plex-Container-Start': '$start', 'X-Plex-Container-Size': '$size'});
    var list = plexList(c['Metadata']);
    // noen rader svarer med raden rundt innholdet
    if (list.isEmpty) {
      for (final hub in plexList(c['Hub'])) {
        list = plexList(hub['Metadata']);
        if (list.isNotEmpty) break;
      }
    }
    return PlexHubPage(
      items: [
        for (final j in list)
          if (PlexItem.fromJson(j) case final item when plexShown(item, sections)) item,
      ],
      fetched: list.length,
      total: plexInt(c['totalSize']),
    );
  }

  /// En film, serie, sesong eller episode med alt om den. [onDeck]: serien får med episoden du skal se nå.
  /// [markers]: intro og rulletekst.
  Future<PlexItem> metadata(String ratingKey, {bool onDeck = false, bool markers = false}) async {
    final c = await get('/library/metadata/$ratingKey', {
      if (onDeck) 'includeOnDeck': '1',
      if (markers) 'includeMarkers': '1',
    });
    final items = _items(c);
    if (items.isEmpty) throw PlexException(tr('Finnes ikke på Plex-serveren lenger (HTTP 404).'), status: 404);
    return items.first;
  }

  /// Sesongene i en serie, eller episodene i en sesong.
  Future<List<PlexItem>> children(String ratingKey) async => _items(await get('/library/metadata/$ratingKey/children'));

  /// Mer som dette (Plex sitt eget forslag).
  Future<List<PlexItem>> related(String ratingKey) async {
    final c = await get('/hubs/metadata/$ratingKey/related', {'count': '24'});
    for (final hub in plexList(c['Hub'])) {
      final items = _items(hub);
      if (items.isNotEmpty) return items;
    }
    return const [];
  }

  /// Søk i filmer, serier og episoder ([section]: bare i det biblioteket).
  Future<List<PlexItem>> search(String query, {String? section}) async {
    final c = await get('/hubs/search', {
      'query': query,
      'limit': '30',
      if (section != null) 'sectionId': section,
    });
    final out = <PlexItem>[];
    final seen = <String>{};
    for (final hub in plexList(c['Hub'])) {
      for (final item in _items(hub)) {
        final ok = item.type == PlexType.movie || item.type == PlexType.show || item.type == PlexType.episode;
        if (ok && seen.add(item.ratingKey)) out.add(item);
      }
    }
    return out;
  }

  /// Sett eller ikke sett (en serie eller sesong: alle episodene).
  Future<void> setWatched(String ratingKey, bool watched) async {
    await _request(watched ? '/:/scrobble' : '/:/unscrobble',
        {'key': ratingKey, 'identifier': 'com.plexapp.plugins.library'});
  }

  /// Hvor du er (playing, paused eller stopped): Plex husker det, og viser det som spilles i oversikten sin.
  Future<void> timeline({
    required String ratingKey,
    required String state,
    required Duration time,
    required Duration duration,
  }) async {
    await _request('/:/timeline', {
      'ratingKey': ratingKey,
      'key': '/library/metadata/$ratingKey',
      'identifier': 'com.plexapp.plugins.library',
      'state': state,
      'time': '${time.inMilliseconds}',
      'duration': '${duration.inMilliseconds}',
    }, timeout: const Duration(seconds: 10));
  }

  /// Et bilde i passe størrelse (Plex skalerer det selv). Innloggingen står i adressen her: bildene hentes uten
  /// egne hoder (adressene vaskes i loggen).
  String? image(String? path, {required int width, required int height}) {
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('http')) return path;
    return _uri('/photo/:/transcode', {
      'width': '$width',
      'height': '$height',
      'minSize': '1',
      'upscale': '1',
      'url': path,
      'X-Plex-Token': token,
    }).toString();
  }

  /// Filen avspilleren henter (innloggingen sendes som hode, se [headers]).
  String file(PlexPart part) => '$base${part.key}';

  /// En undertekstfil, som UTF-8 (mange norske .srt er Latin-1) og med filtypen i adressen, så avspilleren kjenner
  /// den igjen. mpv henter den selv, uten hodene.
  String stream(String key, String codec) {
    final ext = switch (codec) {
      'subrip' || 'srt' => 'srt',
      'webvtt' || 'vtt' => 'vtt',
      'pgs' || 'hdmv_pgs_subtitle' => 'sup',
      '' => '',
      final other => other,
    };
    final path = ext.isEmpty || key.contains('.') ? key : '$key.$ext';
    return _uri(path, {'encoding': 'utf-8', 'X-Plex-Token': token}).toString();
  }
}
