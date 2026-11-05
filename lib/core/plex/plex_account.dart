// Plex-kontoen i Fyrlys: innloggingen (kryptert, som IPTV-innloggingene), serveren som brukes, adressen den svarer
// på, og bibliotekene. Felles for alle IPTV-innloggingene.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/tr.dart';
import '../../platform.dart';
import '../play_info.dart';
import '../secrets.dart';
import 'plex_api.dart';
import 'plex_models.dart';

enum PlexStatus { off, connecting, ready, failed }

class PlexAccount extends ChangeNotifier {
  PlexAccount(this._prefs, this._secrets, {http.Client? client})
      : _http = client ?? http.Client(),
        _ownsClient = client == null {
    _read();
  }

  static const _idKey = 'plex_client_id';
  static const _protectedKey = 'plex_protected';
  static const _plainKey = 'plex_plain';
  static const _replaceKey = 'plex_replace_vod';
  static const _hiddenKey = 'plex_hidden_libraries';
  static const _orderKey = 'plex_library_order';
  static const _askKey = 'plex_ask_user';

  final SharedPreferences _prefs;
  final SecretCodec _secrets;
  final http.Client _http;
  final bool _ownsClient;

  /// hvem appen er overfor Plex (samme id hver gang, så den ikke blir en ny enhet i Plex-kontoen)
  late final PlexClientInfo info = PlexClientInfo(id: _clientId(), deviceName: _deviceName());
  late final PlexTv tv = PlexTv(info, _http);

  /// innloggingen til den som ser på (kontoen som koblet til, eller brukeren i Plex Home som er valgt)
  String? _token;

  /// innloggingen til kontoen som koblet Fyrlys til Plex, når en annen bruker i Plex Home er valgt (null: [_token]);
  /// med den hentes og byttes brukerne
  String? _homeToken;

  /// navnet på den som ser på (brukernavnet til kontoen, eller navnet på brukeren i Plex Home)
  String user = '';

  /// brukeren i Plex Home som er valgt (null: kontoen som koblet til)
  PlexHomeUser? homeUser;

  /// brukerne i Plex Home (tom før de er hentet, og når kontoen ikke har et Plex Home)
  List<PlexHomeUser> homeUsers = const [];
  bool _homeLoaded = false;
  Future<List<PlexHomeUser>>? _homeLoading;

  /// «Hvem ser på?» er vist siden appen startet
  bool askedThisRun = false;

  /// serveren som brukes
  PlexServer? server;

  /// serverne kontoen har (fra sist de ble hentet)
  List<PlexServer> servers = const [];

  /// adressen serveren svarte på sist (prøves først neste gang)
  String? _base;
  PlexStatus status = PlexStatus.off;

  /// feilen som vises (kan ha navnet på serveren); [_errorKind] er den samme uten navn, til loggen og feilrapporten
  String? error;
  String? _errorKind;

  /// bibliotekene med filmer og serier, i rekkefølgen du har valgt (ellers serverens)
  List<PlexLibrary> libraries = const [];
  PlexServerApi? _api;
  Future<PlexServerApi>? _connecting;

  /// økes når serveren byttes eller du logger ut, så en tilkobling som var på vei, ikke tas i bruk
  int _gen = 0;
  bool _disposed = false;

  /// logget inn med en server valgt
  bool get linked => _token != null && server != null;

  /// API-et på serveren (null til den har svart)
  PlexServerApi? get api => _api;

  /// til å spørre om HTTP-koden når noe ikke kan spilles
  http.Client get client => _http;

  /// Plex-fanen erstatter Filmer og Serier fra IPTV-leverandøren (på som standard)
  bool get replacesVod => _prefs.getBool(_replaceKey) ?? true;

  void setReplacesVod(bool value) {
    unawaited(_prefs.setBool(_replaceKey, value));
    _notify();
  }

  /// bibliotekene som er skjult i Plex-fanen («<server>/<bibliotek>»)
  Set<String> get _hidden => <String>{...?_prefs.getStringList(_hiddenKey)};

  String _libraryId(PlexLibrary l) => '${server?.id ?? ''}/${l.key}';

  /// [l] vises ikke i Plex-fanen (sidemenyen, Hjem og søket)
  bool isHidden(PlexLibrary l) => _hidden.contains(_libraryId(l));

  /// Bibliotekene som vises i Plex-fanen.
  List<PlexLibrary> get shownLibraries {
    final hidden = _hidden;
    return [
      for (final l in libraries)
        if (!hidden.contains(_libraryId(l))) l,
    ];
  }

  /// nøklene til bibliotekene som vises
  Set<String> get shownSections => {for (final l in shownLibraries) l.key};

  void setHidden(PlexLibrary l, bool hidden) {
    final set = _hidden;
    final id = _libraryId(l);
    if (!(hidden ? set.add(id) : set.remove(id))) return;
    unawaited(_prefs.setStringList(_hiddenKey, set.toList()..sort()));
    _notify();
  }

  // ── Plex Home ──

  /// flere enn én bruker i Plex Home: da kan du velge hvem som ser på
  bool get hasHome => homeUsers.length > 1;

  /// den i Plex Home som ser på nå (null før brukerne er hentet, med mindre en er valgt)
  PlexHomeUser? get currentHomeUser {
    final chosen = homeUser;
    if (chosen != null) {
      for (final u in homeUsers) {
        if (u.uuid == chosen.uuid) return u;
      }
      return chosen;
    }
    // kontoen som koblet til
    final name = user.toLowerCase();
    if (name.isNotEmpty) {
      for (final u in homeUsers) {
        if (u.username.toLowerCase() == name || u.title.toLowerCase() == name) return u;
      }
    }
    for (final u in homeUsers) {
      if (u.admin) return u;
    }
    return null;
  }

  /// spør «Hvem ser på?» første gang Plex-fanen åpnes etter at appen har startet
  bool get askUser => _prefs.getBool(_askKey) ?? false;

  void setAskUser(bool value) {
    unawaited(_prefs.setBool(_askKey, value));
    _notify();
  }

  /// Brukerne i Plex Home, hentet fra plex.tv (ett forsøk om gangen). Fikk ikke kontakt: det som var hentet før.
  Future<List<PlexHomeUser>> loadHomeUsers() => _homeLoading ??= _loadHome().whenComplete(() {
        _homeLoading = null;
      });

  /// brukerne i Plex Home, hentet én gang etter at appen startet
  Future<void> ensureHomeUsers() async {
    if (!_homeLoaded && linked) await loadHomeUsers();
  }

  Future<List<PlexHomeUser>> _loadHome() async {
    final token = _homeToken ?? _token;
    if (token == null) return homeUsers;
    try {
      final list = await tv.homeUsers(token);
      // logget ut eller inn imens
      if (token != (_homeToken ?? _token)) return homeUsers;
      homeUsers = list;
      _homeLoaded = true;
      debugPrint('Plex: ${list.length} ${list.length == 1 ? 'bruker' : 'brukere'} i Plex Home');
    } on PlexException catch (e) {
      debugPrint('Plex: fikk ikke hentet brukerne i Plex Home (${e.network ? 'ingen kontakt' : 'HTTP ${e.status}'})');
      if (!e.network && token == (_homeToken ?? _token)) {
        homeUsers = const [];
        _homeLoaded = true;
      }
    }
    _notify();
    return homeUsers;
  }

  /// Bytter til [u] i Plex Home ([pin] når brukeren har PIN-kode): serverne hentes med den brukerens innlogging, og
  /// samme server brukes når brukeren har tilgang til den. Kaster PlexException ([PlexException.pin]: PIN-koden
  /// mangler eller er feil).
  Future<void> switchUser(PlexHomeUser u, {String? pin}) async {
    final home = _homeToken ?? _token;
    if (home == null) throw PlexException(tr('Fyrlys er ikke koblet til Plex.'));
    final token = await tv.switchUser(home, u.uuid, pin: pin);
    final list = await tv.servers(token);
    if (list.isEmpty) {
      throw PlexException(tr('{name} har ikke tilgang til noen Plex-server.', {'name': u.title}));
    }
    // logget ut eller inn imens
    if (home != (_homeToken ?? _token)) throw PlexException(tr('Plex-serveren ble byttet.'));
    final before = server?.id;
    _gen++;
    _homeToken = home;
    _token = token;
    user = u.title;
    homeUser = u;
    servers = list;
    server = list.firstWhere((s) => s.id == before, orElse: () => list.first);
    _reset();
    await _save();
    debugPrint('Plex: byttet bruker i Plex Home${u.restricted ? ' (administrert)' : ''}');
    _notify();
  }

  // ── rekkefølgen på bibliotekene ──

  /// rekkefølgen du har valgt («<server>/<bibliotek>», for alle serverne)
  List<String> get _order => _prefs.getStringList(_orderKey) ?? const [];

  /// [libs] i rekkefølgen du har valgt; de som ikke står der (nye biblioteker), kommer sist, i serverens rekkefølge
  List<PlexLibrary> _inOrder(List<PlexLibrary> libs) {
    final order = _order;
    if (order.isEmpty) return libs;
    final place = <String, int>{};
    for (var i = 0; i < order.length; i++) {
      place.putIfAbsent(order[i], () => i);
    }
    final ranked = [
      for (var i = 0; i < libs.length; i++) (lib: libs[i], rank: place[_libraryId(libs[i])] ?? order.length + i),
    ]..sort((a, b) => a.rank.compareTo(b.rank));
    return [for (final r in ranked) r.lib];
  }

  /// Flytter [l] ett steg opp ([step] < 0) eller ned ([step] > 0) blant alle bibliotekene (også de skjulte, som i
  /// valget av biblioteker). Huskes per server.
  void moveLibrary(PlexLibrary l, int step) {
    final list = [...libraries];
    final i = list.indexWhere((x) => x.key == l.key);
    final j = i + (step < 0 ? -1 : 1);
    if (i < 0 || step == 0 || j < 0 || j >= list.length) return;
    list.insert(j, list.removeAt(i));
    libraries = list;
    // hele rekkefølgen for serveren, så et bibliotek som kommer til senere, havner sist
    final prefix = '${server?.id ?? ''}/';
    unawaited(_prefs.setStringList(_orderKey, [
      for (final id in _order)
        if (!id.startsWith(prefix)) id,
      for (final x in list) _libraryId(x),
    ]));
    _notify();
  }

  String _clientId() {
    final saved = _prefs.getString(_idKey);
    if (saved != null && saved.isNotEmpty) return saved;
    final r = Random.secure();
    final id = [for (var i = 0; i < 16; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
    unawaited(_prefs.setString(_idKey, id));
    return id;
  }

  static String _deviceName() {
    if (isAndroid) return 'Android';
    try {
      final host = Platform.localHostname.trim();
      return host.isEmpty ? 'Windows' : host;
    } on Object {
      return 'Windows';
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ── lagret innlogging ──

  void _read() {
    String? raw;
    final protected = _prefs.getString(_protectedKey);
    if (protected != null) raw = _secrets.unprotect(protected);
    raw ??= _prefs.getString(_plainKey);
    if (raw == null) return;
    try {
      final j = plexMap(jsonDecode(raw));
      final token = plexText(j['token']);
      final s = PlexServer.fromSaved(j['server']);
      if (token.isEmpty || s == null) return;
      _token = token;
      user = plexText(j['user']);
      server = s;
      _base = plexPath(j['base']);
      _homeToken = plexPath(j['home']);
      homeUser = PlexHomeUser.fromJson(j['homeUser']);
    } on FormatException {
      // kobles til på nytt
    }
  }

  /// Kryptert når det går (og bare når det kan leses igjen); ellers i klartekst, som IPTV-innloggingene.
  Future<void> _save() async {
    final s = server;
    final token = _token;
    if (s == null || token == null) {
      await _prefs.remove(_protectedKey);
      await _prefs.remove(_plainKey);
      return;
    }
    final home = _homeToken;
    final json = jsonEncode({
      'token': token,
      'user': user,
      'server': s.toJson(),
      if (_base != null) 'base': _base,
      if (home != null && home != token) 'home': home,
      if (homeUser case final u?) 'homeUser': u.toJson(),
    });
    final protected = _secrets.protect(json);
    if (protected != null && _secrets.unprotect(protected) == json) {
      await _prefs.setString(_protectedKey, protected);
      await _prefs.remove(_plainKey);
    } else {
      await _prefs.setString(_plainKey, json);
      await _prefs.remove(_protectedKey);
    }
  }

  // ── innlogging ──

  /// En ny PIN; du sier ja hos Plex på [authUrl], og [finishLogin] gir svaret.
  Future<PlexPin> startLogin() => tv.createPin();

  String authUrl(PlexPin pin) => tv.authUrl(pin);

  /// true når du har sagt ja hos Plex: da er kontoen og serveren lagret. Kaster PlexException når koden gikk ut.
  Future<bool> finishLogin(PlexPin pin) async {
    final token = await tv.checkPin(pin);
    if (token == null) return false;
    await signIn(token);
    return true;
  }

  /// Logger inn med [token]: henter serverne og velger den første (din egen, ellers den som sist var på nett).
  Future<void> signIn(String token) async {
    final list = await tv.servers(token);
    if (list.isEmpty) {
      throw PlexException(tr('Fant ingen Plex-server på kontoen. Har du en server, eller har noen delt sin med deg?'));
    }
    final name = await tv.userName(token);
    _gen++;
    _token = token;
    user = name;
    servers = list;
    server = list.first;
    _resetHome();
    _reset();
    await _save();
    debugPrint('Plex: logget inn (${list.length} ${list.length == 1 ? 'server' : 'servere'})');
    _notify();
    // brukerne i Plex Home, så du kan velge hvem som ser på
    unawaited(loadHomeUsers());
  }

  void _resetHome() {
    _homeToken = null;
    homeUser = null;
    homeUsers = const [];
    _homeLoaded = false;
  }

  void _reset() {
    _base = null;
    _api = null;
    _connecting = null;
    libraries = const [];
    status = PlexStatus.off;
    error = null;
    _errorKind = null;
  }

  /// Serverne på kontoen, hentet på nytt.
  Future<List<PlexServer>> loadServers() async {
    final token = _token;
    if (token == null) return const [];
    servers = await tv.servers(token);
    _notify();
    return servers;
  }

  /// Bytter til en annen server.
  Future<void> useServer(PlexServer s) async {
    _gen++;
    server = s;
    _reset();
    await _save();
    _notify();
  }

  /// Kobler Fyrlys fra Plex (innloggingen slettes her; Fyrlys står fortsatt under «Enheter» hos Plex til du fjerner
  /// den der).
  Future<void> logout() async {
    _gen++;
    _token = null;
    user = '';
    server = null;
    servers = const [];
    _resetHome();
    _reset();
    await _save();
    debugPrint('Plex: koblet fra');
    _notify();
  }

  // ── tilkobling ──

  /// API-et på serveren: finner adressen den svarer på (hjemmenettet først) og henter bibliotekene. Samme forsøk
  /// deles av alle som spør samtidig.
  Future<PlexServerApi> connect({bool force = false}) {
    final api = _api;
    if (api != null && !force) return Future.value(api);
    final pending = _connecting;
    if (pending != null) return pending;
    late final Future<PlexServerApi> f;
    f = _connect(_gen).whenComplete(() {
      if (identical(_connecting, f)) _connecting = null;
    });
    _connecting = f;
    return f;
  }

  Future<PlexServerApi> _connect(int gen) async {
    final s = server;
    final token = _token;
    if (s == null || token == null) throw PlexException(tr('Fyrlys er ikke koblet til Plex.'));
    status = PlexStatus.connecting;
    error = null;
    _notify();
    try {
      var current = s;
      PlexConnection? conn;
      // adressen fra sist, når den var i hjemmenettet (den over nettet eller via Plex svarer overalt, også hjemme,
      // så da prøves alle: hjemmenettet går foran)
      final saved = _base;
      final known = saved == null ? null : _known(s, saved);
      if (known != null &&
          known.tier == 0 &&
          await probeServer(known.uri, s, _http, info, timeout: const Duration(seconds: 3))) {
        conn = known;
      }
      conn ??= await pickConnection(s, _http, info);
      if (conn == null) {
        // adressene kan ha endret seg (ny IP, fjerntilgang slått av eller på): spør plex.tv på nytt
        final fresh = await _freshServer(token, s.id);
        if (fresh != null) {
          current = fresh;
          conn = await pickConnection(fresh, _http, info);
        }
      }
      if (conn == null) {
        throw PlexException(
          tr('Fikk ikke kontakt med Plex-serveren {name}. Er den på, og er du i samme nett som den (eller har den '
              'fjerntilgang)?', {'name': current.name}),
          network: true,
        );
      }
      final api = PlexServerApi(base: conn.uri, token: current.token, info: info, client: _http, tier: conn.tier);
      final libs = await api.libraries();
      if (gen != _gen) throw PlexException(tr('Plex-serveren ble byttet.'));
      server = current;
      _base = conn.uri;
      _api = api;
      libraries = _inOrder(libs);
      status = PlexStatus.ready;
      error = null;
      _errorKind = null;
      debugPrint('Plex: koblet til ${tierName(conn.tier)} (${conn.secure ? 'https' : 'http'}), '
          '${libs.length} ${libs.length == 1 ? 'bibliotek' : 'biblioteker'}');
      await _save();
      _notify();
      return api;
    } on Object catch (e) {
      final ex = e is PlexException ? e : PlexException(tr('Fikk ikke kontakt med Plex: {error}', {'error': '$e'}));
      if (gen == _gen) {
        _api = null;
        status = PlexStatus.failed;
        error = ex.message;
        _errorKind = ex.network ? 'ingen kontakt' : (ex.status != null ? 'HTTP ${ex.status}' : 'annen feil');
        debugPrint('Plex: fikk ikke koblet til ($_errorKind)');
        _notify();
      }
      throw ex;
    }
  }

  /// adressen fra sist, med hva slags den er (hjemmenettet, nettet eller via Plex)
  static PlexConnection _known(PlexServer s, String uri) {
    for (final c in s.connections) {
      if (c.uri == uri) return c;
      if (c.lanHttp?.uri == uri) return c.lanHttp!;
    }
    return PlexConnection(uri: uri, protocol: uri.startsWith('http://') ? 'http' : 'https');
  }

  Future<PlexServer?> _freshServer(String token, String id) async {
    try {
      final list = await tv.servers(token);
      servers = list;
      for (final s in list) {
        if (s.id == id) return s;
      }
    } on PlexException {
      // plex.tv svarer ikke: blir med adressene vi har
    }
    return null;
  }

  /// Kjører [call] mot serveren. Brøt forbindelsen (byttet nett, eller serveren fikk ny adresse), finnes adressen
  /// på nytt og det prøves én gang til.
  Future<T> run<T>(Future<T> Function(PlexServerApi api) call) async {
    final api = await connect();
    try {
      return await call(api);
    } on PlexException catch (e) {
      if (e.status == 401 || e.status == 403) {
        status = PlexStatus.failed;
        error = e.message;
        _errorKind = 'HTTP ${e.status}';
        _notify();
        rethrow;
      }
      if (!e.network) rethrow;
      // Alle som feilet samtidig, venter på samme nye forsøk. Sidene står som før imens (det gamle API-et byttes
      // først når det nye svarer).
      final current = _api;
      if (current != null && !identical(current, api)) return call(current);
      debugPrint('Plex: mistet kontakten, prøver adressene på nytt');
      return call(await connect(force: true));
    }
  }

  /// et bilde i passe størrelse (null før serveren har svart)
  String? image(String? path, {required int width, required int height}) =>
      _api?.image(path, width: width, height: height);

  /// «i hjemmenettet», «over nettet» eller «via Plex (relay)»
  static String tierName(int tier) => switch (tier) {
        0 => tr('i hjemmenettet'),
        1 => tr('over nettet'),
        _ => tr('via Plex (relay)'),
      };

  /// til feilrapporten (uten navn og adresser)
  String get reportLine {
    if (!linked) return tr('ikke koblet til');
    final api = _api;
    return [
      switch (status) {
        PlexStatus.ready => tr('koblet til'),
        PlexStatus.connecting => tr('kobler til'),
        PlexStatus.failed => tr('feil: {error}', {'error': _errorKind ?? ''}),
        PlexStatus.off => tr('ikke tilkoblet ennå'),
      },
      if (api != null) '${tierName(api.tier)} (${api.base.startsWith('https') ? 'https' : 'http'})',
      if (api != null) tr('{n} biblioteker', {'n': libraries.length}),
      if (server case final s?) s.owned ? tr('egen server') : tr('delt server'),
      if (hasHome) tr('Plex Home: {n} brukere', {'n': homeUsers.length}),
      if (server?.version case final v? when v.isNotEmpty) 'Plex Media Server $v',
    ].join(' · ');
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsClient) _http.close();
    super.dispose();
  }
}

/// Sier fra til Plex om hvor du er i det som spilles: Plex husker det («Fortsett å se» også i andre Plex-apper), viser
/// det i oversikten sin, og merker det som sett når du er forbi 90 %.
class PlexReporter implements PlayReport {
  PlexReporter(this._plex, this.ratingKey);

  final PlexAccount _plex;
  final String ratingKey;

  /// Plex merker det som sett selv når den ser at du går forbi grensen (90 %)
  static const threshold = 0.9;

  /// serveren har fått en posisjon mellom 0 og grensen (da merker den det selv når du går forbi)
  bool _below = false;
  bool _marked = false;
  String? _lastState;
  Duration? _lastTime;

  @override
  void progress(Duration position, Duration duration, {required bool playing}) =>
      unawaited(_send(playing ? 'playing' : 'paused', position, duration));

  @override
  void stopped(Duration position, Duration duration) => unawaited(_send('stopped', position, duration));

  @override
  void finished(Duration duration) => unawaited(_send('stopped', duration, duration));

  Future<void> _send(String state, Duration position, Duration duration) async {
    final api = _plex.api;
    if (api == null || duration <= Duration.zero) return;
    final at = position < Duration.zero ? Duration.zero : (position > duration ? duration : position);
    // samme beskjed to ganger (spilleren lukkes rett etter at den er sagt fra om)
    if (state == 'stopped' && _lastState == 'stopped' && _lastTime == at) return;
    _lastState = state;
    _lastTime = at;
    final part = at.inMilliseconds / duration.inMilliseconds;
    try {
      await api.timeline(ratingKey: ratingKey, state: state, time: at, duration: duration);
      if (at > Duration.zero && part < threshold) _below = true;
      if (part >= threshold && !_marked) {
        _marked = true;
        // Plex merker den selv når den har sett deg gå forbi grensen; ellers (du begynte nesten ved slutten) her
        if (!_below) await api.setWatched(ratingKey, true);
      }
    } on Object catch (e) {
      debugPrint('Plex: fikk ikke sagt fra om hvor du er ($state): $e');
    }
  }
}
