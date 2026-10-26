import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/tr.dart';
import 'cache.dart';
import 'languages.dart';
import 'm3u_source.dart';
import 'models.dart';
import 'names.dart';
import 'picture.dart';
import 'secrets.dart';
import 'source.dart';
import 'vod.dart';
import 'xtream_source.dart';

typedef SourceFactory = Future<TvSource?> Function(Map<String, String> saved);

/// En lagret innlogging: navnet du ser og hva slags den er. Det som trengs for å logge inn (med passordet), ligger
/// kryptert for seg.
class SavedLogin {
  const SavedLogin({required this.id, required this.name, required this.kind});

  factory SavedLogin.fromJson(Map<Object?, Object?> j) =>
      SavedLogin(id: '${j['id']}', name: '${j['name'] ?? ''}', kind: '${j['kind'] ?? ''}');

  final String id;
  final String name;

  /// 'xtream' eller 'm3u'
  final String kind;

  String get kindName => switch (kind) {
        'xtream' => 'Xtream Codes',
        'm3u' => 'M3U-liste',
        _ => kind,
      };

  SavedLogin named(String name) => SavedLogin(id: id, name: name, kind: kind);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'kind': kind};
}

/// Tilstanden i appen: kilden du er logget inn på, kanallista, favoritter, «sist sett» og lys/mørk.
class Session extends ChangeNotifier {
  Session(this._prefs, {this.sourceFactory, this.listCache, SecretCodec? secrets, this.systemLanguage = 'no'})
      : _secrets = secrets ?? SecretCodec.platform(),
        themeMode = _themeFrom(_prefs.getString('theme')) {
    appLanguage = _effectiveLanguage(language);
  }

  /// språket Windows bruker ('no' eller 'en'); norsk i testene
  final String systemLanguage;

  /// Språket i appen: 'auto' (som Windows), 'no' eller 'en'.
  String get language {
    final v = _prefs.getString('language');
    return v == 'no' || v == 'en' ? v! : 'auto';
  }

  String _effectiveLanguage(String value) => value == 'auto' ? systemLanguage : value;

  void setLanguage(String value) {
    unawaited(_prefs.setString('language', value));
    appLanguage = _effectiveLanguage(value);
    notifyListeners();
  }

  final SharedPreferences _prefs;

  /// tester lager kilden selv i stedet for å koble til noe
  final SourceFactory? sourceFactory;

  /// kanallista fra sist (null: hentes hver gang, som i testene)
  final ListCache? listCache;

  /// krypterer innloggingen (DPAPI på Windows)
  final SecretCodec _secrets;

  TvSource? source;
  bool restoring = true;
  ThemeMode themeMode;

  /// innloggingene du har lagret, og den som er i bruk (id i lista)
  List<SavedLogin> logins = const [];
  String? activeLogin;

  List<Category> categories = const [];
  List<Channel> channels = const [];
  Map<String, int> categoryCounts = const {};
  bool loading = false;
  String? error;

  List<Channel> favorites = const [];
  List<String> favoriteCategories = const [];
  List<Channel> recent = const [];

  Map<String, Channel> _byId = const {};
  final Map<String, List<Channel>> _filtered = {};
  final Map<String, _EpgHit> _epg = {};
  int _epgBusy = 0;
  final Queue<Completer<void>> _epgWaiting = Queue();

  static ThemeMode _themeFrom(String? s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  // ── innlogging ──

  // Innloggingene (2.1.14): lista i 'logins' (navn og slag), den som er i bruk i 'login', og det som trengs for å logge
  // inn i 'login_protected:<id>' (kryptert) eller 'login_source:<id>' (klartekst, når krypteringen ikke virker).
  // Fram til 2.1.13 var det én innlogging, i 'source_protected' eller 'source'; den flyttes over første gang.
  static const _legacyProtected = 'source_protected';
  static const _legacyPlain = 'source';
  static const _listKey = 'logins';
  static const _activeKey = 'login';
  static String _protectedKey(String id) => 'login_protected:$id';
  static String _plainKey(String id) => 'login_source:$id';

  /// Det hver innlogging har for seg (kanalene og filmene har ulike id-er hos ulike leverandører). Lyd, språk, bilde
  /// og lys/mørk gjelder alle.
  static const _perLogin = ['favorites', 'favoriteCategories', 'recent', 'resume', 'continue', 'guide_cat'];

  /// nøkkelen for [name] i innloggingen som er i bruk
  String _k(String name) => '$name@${activeLogin ?? ''}';

  /// Samme konto får samme id, så favorittene er der igjen hvis du logger ut og inn: leverandøren og brukeren, ikke
  /// passordet.
  static String loginId(Map<String, String> prefs) {
    final kind = prefs['kind'] ?? '';
    final who = switch (kind) {
      'xtream' => '${prefs['server']}|${prefs['user']}',
      'm3u' => _withoutPassword(prefs['url'] ?? ''),
      _ => jsonEncode(prefs),
    };
    return stableHash('$kind|$who');
  }

  static String _withoutPassword(String url) {
    final u = Uri.tryParse(url);
    if (u == null || !u.hasQuery) return url;
    const secret = {'password', 'pass', 'pwd'};
    return u.replace(queryParameters: {
      for (final e in u.queryParameters.entries)
        if (!secret.contains(e.key.toLowerCase())) e.key: e.value,
    }).toString();
  }

  /// innloggingen som er i bruk
  SavedLogin? get currentLogin {
    for (final l in logins) {
      if (l.id == activeLogin) return l;
    }
    return null;
  }

  /// Kobler til igjen med innloggingen du brukte sist (eller den neste som lar seg åpne).
  Future<void> restore() async {
    final moved = await _migrate();
    logins = _readLogins();
    TvSource? src = moved?.source;
    String? id = moved?.id;
    if (src == null) {
      final wanted = _prefs.getString(_activeKey);
      for (final l in [...logins.where((l) => l.id == wanted), ...logins.where((l) => l.id != wanted)]) {
        src = await _openLogin(l.id);
        if (src != null) {
          id = l.id;
          break;
        }
      }
    }
    restoring = false;
    if (src != null && id != null) {
      await _activate(id, src);
    } else {
      notifyListeners();
    }
  }

  /// Fra før 2.1.14: én innlogging, og favorittene og resten uten id. Flyttes til lista én gang.
  Future<({String id, TvSource source})?> _migrate() async {
    if (_prefs.containsKey(_listKey)) return null;
    String? raw;
    final protected = _prefs.getString(_legacyProtected);
    if (protected != null) raw = _secrets.unprotect(protected);
    raw ??= _prefs.getString(_legacyPlain);
    final saved = raw == null ? null : _decode(raw);
    final src = saved == null ? null : await _build(saved);
    // kan den ikke åpnes (eller var du logget ut), blir favorittene og resten liggende til du logger inn (_use)
    if (src == null) return null;
    final prefs = src.toPrefs();
    final id = loginId(prefs);
    await _saveSecret(id, jsonEncode(prefs));
    await _moveLegacy(id);
    await _prefs.setString(_listKey, jsonEncode([SavedLogin(id: id, name: src.label, kind: src.kind).toJson()]));
    return (id: id, source: src);
  }

  /// Favorittene og resten fra før 2.1.14 (uten id) går til innloggingen [id], og den gamle innloggingen slettes.
  Future<void> _moveLegacy(String id) async {
    for (final name in _perLogin) {
      final value = _prefs.get(name);
      if (value is String) {
        await _prefs.setString('$name@$id', value);
      } else if (value is List) {
        await _prefs.setStringList('$name@$id', [for (final v in value) '$v']);
      }
      await _prefs.remove(name);
    }
    await _prefs.remove(_legacyProtected);
    await _prefs.remove(_legacyPlain);
  }

  List<SavedLogin> _readLogins() {
    try {
      final raw = jsonDecode(_prefs.getString(_listKey) ?? '[]');
      return [
        for (final j in raw is List ? raw : const [])
          if (j is Map && j['id'] is String) SavedLogin.fromJson(j),
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> _saveLogins() => _prefs.setString(_listKey, jsonEncode([for (final l in logins) l.toJson()]));

  static Map<String, String>? _decode(String raw) {
    try {
      final j = jsonDecode(raw);
      return j is Map ? j.map((k, v) => MapEntry('$k', '$v')) : null;
    } on FormatException {
      return null;
    }
  }

  Future<TvSource?> _build(Map<String, String> saved) async {
    try {
      final factory = sourceFactory;
      return factory != null ? await factory(saved) : _fromPrefs(saved);
    } on Object {
      return null;
    }
  }

  /// En lagret innlogging, klar til bruk (null: finnes ikke, eller kan ikke leses her, f.eks. en annen Windows-bruker).
  Future<TvSource?> _openLogin(String id) async {
    String? raw;
    final protected = _prefs.getString(_protectedKey(id));
    if (protected != null) raw = _secrets.unprotect(protected);
    final plain = raw == null ? _prefs.getString(_plainKey(id)) : null;
    raw ??= plain;
    final saved = raw == null ? null : _decode(raw);
    final src = saved == null ? null : await _build(saved);
    // lagret i klartekst fra før: krypteres nå, når det går
    if (src != null && plain != null && _secrets.protect(plain) != null) await _saveSecret(id, plain);
    return src;
  }

  /// Kryptert når det går (og bare når det kan leses igjen); ellers i klartekst som før.
  Future<void> _saveSecret(String id, String json) async {
    final protected = _secrets.protect(json);
    if (protected != null && _secrets.unprotect(protected) == json) {
      await _prefs.setString(_protectedKey(id), protected);
      await _prefs.remove(_plainKey(id));
    } else {
      await _prefs.setString(_plainKey(id), json);
      await _prefs.remove(_protectedKey(id));
    }
  }

  TvSource? _fromPrefs(Map<String, String> s) {
    switch (s['kind']) {
      case 'm3u':
        final url = s['url'];
        return url == null ? null : M3uSource(url: url, epgUrl: s['epg'] ?? '');
      case 'xtream':
        final server = s['server'];
        final user = s['user'];
        final password = s['password'];
        if (server == null || user == null || password == null) return null;
        return XtreamSource(server: server, user: user, password: password);
    }
    return null;
  }

  /// En M3U-lenke. Er det en Xtream-lenke (get.php med brukernavn og passord), logges du inn med Xtream Codes, som
  /// også har TV-guide, filmer og serier; ellers leses lista (med TV-guide fra [epg] eller lenken i lista).
  Future<void> loginM3u(String link, {String epg = ''}) async {
    final address = M3uSource.normalize(link);
    final login = cleanServer(address);
    final path = Uri.parse(address).path;
    if (login.user != null && login.password != null && (path.endsWith('get.php') || path.endsWith('player_api.php'))) {
      try {
        await _use(await XtreamSource.login(address, '', ''));
        return;
      } on SourceException {
        // ikke en Xtream-server likevel: lista leses som den er
      }
    }
    await _use(await M3uSource.connect(address, epgUrl: epg));
  }

  Future<void> loginXtream(String server, String user, String password) async =>
      _use(await XtreamSource.login(server, user, password));

  /// Lagrer innloggingen (en du har fra før, oppdateres og beholder navnet) og bytter til den.
  Future<void> _use(TvSource src) async {
    final prefs = src.toPrefs();
    final id = loginId(prefs);
    await _saveSecret(id, jsonEncode(prefs));
    // den første innloggingen når ingen kunne flyttes (du var logget ut da du oppdaterte): den får favorittene fra før
    if (logins.isEmpty) await _moveLegacy(id);
    if (!logins.any((l) => l.id == id)) {
      logins = [...logins, SavedLogin(id: id, name: src.label, kind: src.kind)];
      await _saveLogins();
    }
    await _activate(id, src);
  }

  /// for testene: logger inn med en kilde de har laget selv
  @visibleForTesting
  Future<void> useSource(TvSource src) => _use(src);

  Future<void> _activate(String id, TvSource src) async {
    activeLogin = id;
    await _prefs.setString(_activeKey, id);
    _attach(src);
  }

  /// Bytter til en annen lagret innlogging (kaster SourceException når den ikke kan åpnes her).
  Future<void> switchLogin(String id) async {
    if (id == activeLogin && source != null) return;
    if (!logins.any((l) => l.id == id)) return;
    final src = await _openLogin(id);
    if (src == null) throw const SourceException('Fikk ikke åpnet innloggingen. Fjern den og logg inn på nytt.');
    await _activate(id, src);
  }

  Future<void> renameLogin(String id, String name) async {
    final text = name.trim();
    if (text.isEmpty) return;
    logins = [for (final l in logins) l.id == id ? l.named(text) : l];
    await _saveLogins();
    notifyListeners();
  }

  /// Logger ut av en innlogging: den slettes fra lista (favorittene blir liggende og er der igjen hvis du logger inn
  /// på nytt). Var det den du brukte, byttes det til den neste som kan åpnes; ellers vises innloggingen.
  Future<void> removeLogin(String id) async {
    await _prefs.remove(_protectedKey(id));
    await _prefs.remove(_plainKey(id));
    logins = [for (final l in logins) if (l.id != id) l];
    await _saveLogins();
    if (id != activeLogin) {
      notifyListeners();
      return;
    }
    _detach();
    await _prefs.remove(_activeKey);
    for (final l in logins) {
      final src = await _openLogin(l.id);
      if (src != null) {
        await _activate(l.id, src);
        return;
      }
    }
    notifyListeners();
  }

  /// Logger ut av den du bruker.
  Future<void> logout() async {
    final id = activeLogin;
    if (id != null) {
      await removeLogin(id);
    } else {
      _detach();
      notifyListeners();
    }
  }

  void _attach(TvSource src) {
    source?.dispose();
    source = src;
    categories = const [];
    channels = const [];
    categoryCounts = const {};
    _byId = const {};
    _filtered.clear();
    _epg.clear();
    error = null;
    loading = false;
    favorites = _readChannels(_k('favorites'));
    favoriteCategories = _prefs.getStringList(_k('favoriteCategories')) ?? const [];
    recent = _readChannels(_k('recent'));
    _resume = null;
    _continue = null;
    _connections = null;
    notifyListeners();
    unawaited(_startLists(src));
    unawaited(_loadConnections(src));
  }

  void _detach() {
    source?.dispose();
    source = null;
    activeLogin = null;
    _connections = null;
    categories = const [];
    channels = const [];
    categoryCounts = const {};
    favorites = const [];
    favoriteCategories = const [];
    recent = const [];
    _resume = null;
    _continue = null;
    _byId = const {};
    _filtered.clear();
    _epg.clear();
    error = null;
    loading = false;
  }

  // ── flere bilder samtidig (multiview) ──

  /// hvor mange tilkoblinger abonnementet i bruk har (null: vet ikke ennå)
  int? _connections;

  Future<void> _loadConnections(TvSource src) async {
    try {
      final a = await src.account();
      if (source != src) return;
      _connections = a.maxConnections;
      if (a.maxConnections >= 2) notifyListeners();
    } on Object {
      // vet ikke: én
    }
  }

  /// Flere bilder samtidig går når du har flere abonnementer, eller ett med flere tilkoblinger.
  bool get canMultiview => logins.length >= 2 || (_connections ?? 0) >= 2;

  /// Kilden for en lagret innlogging: den i bruk, eller en ny for de andre (den som spør, lukker den med dispose).
  Future<TvSource?> sourceFor(String id) async =>
      id == activeLogin && source != null ? source : await _openLogin(id);

  /// favorittkanalene til en innlogging (også en som ikke er i bruk)
  List<Channel> favoritesOf(String id) => id == activeLogin ? favorites : _readChannels('favorites@$id');

  /// Lista fra sist vises med en gang, og den nye hentes i bakgrunnen.
  Future<void> _startLists(TvSource src) async {
    final cache = listCache;
    if (cache != null) {
      final saved = await cache.read(_cacheKey(src));
      // ikke hvis kilden er byttet imens, eller den nye lista alt er kommet
      if (saved != null && source == src && channels.isEmpty && saved.channels.isNotEmpty) {
        _applyLists(saved.categories, saved.channels);
        notifyListeners();
        _prefetchEpg();
      }
    }
    if (source == src) await load();
  }

  /// samme som innloggingen (to lister fra samme vert har samme navn, men er ikke samme liste)
  static String _cacheKey(TvSource src) => loginId(src.toPrefs());

  // ── lister ──

  Future<void> load({bool force = false}) async {
    final src = source;
    if (src == null) return;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final cats = await src.categories(force: force);
      final chans = await src.channels(force: force);
      if (source != src) return;
      final first = channels.isEmpty;
      _applyLists(cats, chans);
      unawaited(listCache?.write(_cacheKey(src), categories, channels));
      if (first) _prefetchEpg();
    } on SourceException catch (e) {
      debugPrint('Listene: ${src.redact(e.message)}');
      if (source == src) error = e.message;
    } on Object catch (e) {
      debugPrint('Listene: ${src.redact('$e')}');
      // uventet svar (ikke en Xtream-server eller M3U-liste): vis en feil i stedet for en tom liste
      if (source == src) error = 'Uventet svar fra serveren da lista ble hentet';
    } finally {
      if (source == src) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void _applyLists(List<Category> cats, List<Channel> chans) {
    final counts = <String, int>{};
    for (final c in chans) {
      counts[c.categoryId] = (counts[c.categoryId] ?? 0) + 1;
    }
    final seen = <String>{};
    categories = [for (final c in cats) if ((counts[c.id] ?? 0) > 0 && seen.add(c.id)) c];
    channels = chans;
    categoryCounts = counts;
    _byId = {for (final c in chans) c.id: c};
    _filtered.clear();
    favorites = [for (final f in favorites) _byId[f.id] ?? f];
    recent = [for (final r in recent) _byId[r.id] ?? r];
  }

  /// Programinfo for favorittene og det du har sett sist hentes med en gang, så startsiden er fylt ut når den
  /// vises (det som faktisk vises, går likevel først i køen).
  void _prefetchEpg() {
    final ids = <String>{
      for (final c in [...favorites.take(12), ...recent.take(8)])
        if (c.hasEpg && nameParts(c.name).sub.isEmpty) c.id,
    };
    for (final id in ids) {
      unawaited(epg(id));
    }
  }

  /// Kanalene i et utvalg: 'all', 'fav', 'recent' eller en kategori-id.
  List<Channel> channelsIn(String filter) => switch (filter) {
        'all' => channels,
        'fav' => favorites,
        'recent' => recent,
        _ => _filtered.putIfAbsent(filter, () => [for (final c in channels) if (c.categoryId == filter) c]),
      };

  String categoryName(String id) {
    for (final c in categories) {
      if (c.id == id) return c.name;
    }
    return 'Kanaler';
  }

  // ── programinfo ──

  /// Programmene for en kanal. Mellomlagres i fem minutter, og høyst fire forespørsler går om gangen.
  /// En lengre liste (TV-guiden) brukes også av kortene, men ikke omvendt.
  Future<List<EpgEntry>> epg(String channelId, {int limit = 6}) {
    final hit = _freshEpg(channelId, limit);
    if (hit != null) return hit.list;
    final src = source;
    if (src == null) return Future.value(const <EpgEntry>[]);
    // doble og overlappende programmer ryddes her, så det gjelder begge kildene
    late final _EpgHit entry;
    final future = _limited(() => src.epg(channelId, limit: limit)).then(cleanEpg).catchError((Object _) {
      // en feil skal ikke huskes i fem minutter: neste gang kanalen vises, prøves det igjen
      if (identical(_epg[channelId], entry)) _epg.remove(channelId);
      return const <EpgEntry>[];
    });
    entry = _EpgHit(limit, future);
    unawaited(future.then((list) => entry.value = list));
    _epg.remove(channelId);
    _epg[channelId] = entry;
    if (_epg.length > 600) _epg.remove(_epg.keys.first);
    return future;
  }

  /// Det som alt er hentet (og er ferskt), uten å vente, så rader som rulles inn igjen ikke blinker.
  List<EpgEntry>? epgCached(String channelId, {int limit = 6}) => _freshEpg(channelId, limit)?.value;

  _EpgHit? _freshEpg(String channelId, int limit) {
    final hit = _epg[channelId];
    if (hit == null || hit.limit < limit || DateTime.now().difference(hit.at) >= const Duration(minutes: 5)) return null;
    return hit;
  }

  Future<T> _limited<T>(Future<T> Function() task) async {
    while (_epgBusy >= 4) {
      final waiter = Completer<void>();
      _epgWaiting.add(waiter);
      await waiter.future;
    }
    _epgBusy++;
    try {
      return await task();
    } finally {
      _epgBusy--;
      // nyeste først: det som vises nå (etter at du har rullet), før det du rullet forbi
      if (_epgWaiting.isNotEmpty) _epgWaiting.removeLast().complete();
    }
  }

  // ── TV-arkivet ──

  /// Programmene i arkivet for en kanal (de siste dagene, og det som går nå), eldst først.
  Future<List<EpgEntry>> archive(Channel channel) async {
    final src = source;
    if (src == null || !channel.hasArchive) return const [];
    return cleanEpg(await src.archive(channel));
  }

  /// Strømmen for et program i arkivet (kaster SourceException når det ikke går).
  Future<ArchiveClip> archiveClip(Channel channel, EpgEntry program) async {
    final src = source;
    if (src == null) throw const SourceException('Ikke logget inn');
    return src.archiveClip(channel, program);
  }

  // ── favoritter og «sist sett» ──

  bool isFavorite(String id) => favorites.any((c) => c.id == id);

  bool isFavoriteCategory(String id) => favoriteCategories.contains(id);

  Future<bool> toggleFavorite(Channel ch) async {
    final on = !isFavorite(ch.id);
    favorites = on ? [...favorites, ch] : [for (final c in favorites) if (c.id != ch.id) c];
    notifyListeners();
    await _saveFavorites();
    return on;
  }

  Future<bool> toggleFavoriteCategory(String id) async {
    final on = !isFavoriteCategory(id);
    favoriteCategories = on ? [...favoriteCategories, id] : [for (final c in favoriteCategories) if (c != id) c];
    notifyListeners();
    await _saveFavorites();
    return on;
  }

  Future<void> moveFavoriteCategory(String id, int step) async {
    final list = [...favoriteCategories];
    final i = list.indexOf(id);
    final j = i + step;
    if (i < 0 || j < 0 || j >= list.length) return;
    final moved = list[i];
    list[i] = list[j];
    list[j] = moved;
    favoriteCategories = list;
    notifyListeners();
    await _saveFavorites();
  }

  Future<void> _saveFavorites() async {
    await _prefs.setString(_k('favorites'), jsonEncode([for (final c in favorites) c.toJson()]));
    await _prefs.setStringList(_k('favoriteCategories'), favoriteCategories);
  }

  void addRecent(Channel ch) {
    recent = [ch, for (final c in recent) if (c.id != ch.id) c].take(12).toList();
    unawaited(_prefs.setString(_k('recent'), jsonEncode([for (final c in recent) c.toJson()])));
    notifyListeners();
  }

  List<Channel> _readChannels(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      return [
        for (final j in list is List ? list : const [])
          if (j is Map) Channel.fromJson(j.map((k, v) => MapEntry('$k', v))),
      ];
    } on FormatException {
      return const [];
    }
  }

  /// kanalene TV-guiden viste sist: 'fav', 'all' eller en kategori-id (null: aldri valgt)
  String? get guideCategory => _prefs.getString(_k('guide_cat'));

  void saveGuideCategory(String filter) => unawaited(_prefs.setString(_k('guide_cat'), filter));

  // ── lyd og språk ──

  /// Språkene du foretrekker for lydspor og undertekster (gjelder alle spillerne).
  LanguagePrefs get languages => LanguagePrefs(
        audio: _prefs.getStringList('lang_audio') ?? const [],
        subtitles: _prefs.getStringList('lang_subs') ?? const [],
      );

  void saveLanguages(LanguagePrefs prefs) {
    unawaited(_prefs.setStringList('lang_audio', prefs.audio));
    unawaited(_prefs.setStringList('lang_subs', prefs.subtitles));
    notifyListeners();
  }

  /// Bildet i spillerne: deinterlacing (på) og jevn bevegelse (av til den er prøvd).
  PicturePrefs get picture => PicturePrefs(
        deinterlace: _prefs.getBool('deinterlace') ?? true,
        smooth: _prefs.getBool('smooth_motion') ?? false,
      );

  void savePicture(PicturePrefs prefs) {
    unawaited(_prefs.setBool('deinterlace', prefs.deinterlace));
    unawaited(_prefs.setBool('smooth_motion', prefs.smooth));
    notifyListeners();
  }

  /// Bildeformatet og lydforsinkelsen for en kanal (huskes per innlogging, for de 300 siste kanalene).
  ChannelView channelView(String channelId) => ChannelView.fromJson(_channelViews()[channelId]);

  void saveChannelView(String channelId, ChannelView view) {
    final m = _channelViews()..remove(channelId);
    if (!view.isDefault) m[channelId] = view.toJson();
    while (m.length > 300) {
      m.remove(m.keys.first);
    }
    unawaited(_prefs.setString(_k('channel_view'), jsonEncode(m)));
  }

  Map<String, Object?> _channelViews() {
    try {
      final raw = jsonDecode(_prefs.getString(_k('channel_view')) ?? '{}');
      if (raw is Map) return Map<String, Object?>.from(raw);
    } on FormatException {
      // begynner på nytt
    }
    return {};
  }

  /// Volumet i spilleren (0–100), som sist.
  double get volume => (_prefs.getDouble('volume') ?? 100).clamp(0, 100).toDouble();

  bool get muted => _prefs.getBool('muted') ?? false;

  /// Lagres uten å si fra til resten av appen (det skjer mens glidebryteren dras).
  void saveVolume(double volume, bool muted) {
    unawaited(_prefs.setDouble('volume', volume));
    unawaited(_prefs.setBool('muted', muted));
  }

  // ── fortsett der du slapp (filmer og episoder) ──

  Map<String, List<int>>? _resume;

  /// nøkkel («film:123», «episode:456») → [sekunder, lengde i sekunder, når]
  Map<String, List<int>> _resumeMap() {
    final cached = _resume;
    if (cached != null) return cached;
    final out = <String, List<int>>{};
    try {
      final raw = jsonDecode(_prefs.getString(_k('resume')) ?? '{}');
      if (raw is Map) {
        for (final e in raw.entries) {
          final v = e.value;
          if (v is List && v.length == 3 && v.every((x) => x is int)) out['${e.key}'] = [for (final x in v) x as int];
        }
      }
    } on FormatException {
      // begynner på nytt
    }
    return _resume = out;
  }

  /// Hvor du slapp, når det er verdt å fortsette: mer enn et halvt minutt inn og ikke nesten ferdig.
  Duration? resumeAt(String key) {
    final v = _resumeMap()[key];
    if (v == null) return null;
    final position = v[0];
    final length = v[1];
    if (position < 30 || (length > 0 && position > length * 0.95)) return null;
    return Duration(seconds: position);
  }

  /// Hvor mye du har sett, fra 0 til 1 (streken under episodene).
  double watched(String key) {
    final v = _resumeMap()[key];
    if (v == null || v[1] <= 0) return 0;
    return (v[0] / v[1]).clamp(0.0, 1.0).toDouble();
  }

  void saveResume(String key, Duration position, Duration length) {
    final m = _resumeMap();
    m.remove(key);
    m[key] = [position.inSeconds, length.inSeconds, DateTime.now().millisecondsSinceEpoch ~/ 1000];
    while (m.length > 300) {
      m.remove(m.keys.first);
    }
    unawaited(_prefs.setString(_k('resume'), jsonEncode(m)));
  }

  /// Hvor du slapp og hvor lang den er, når det er verdt å fortsette (som [resumeAt]).
  ({Duration position, Duration length})? resumeState(String key) {
    final at = resumeAt(key);
    final v = _resumeMap()[key];
    if (at == null || v == null) return null;
    return (position: at, length: Duration(seconds: v[1]));
  }

  // ── fortsett å se (filmer og serier) ──

  List<ContinueItem>? _continue;

  /// sist sett først
  List<ContinueItem> get continueItems {
    final cached = _continue;
    if (cached != null) return cached;
    final out = <ContinueItem>[];
    try {
      final raw = jsonDecode(_prefs.getString(_k('continue')) ?? '[]');
      if (raw is List) {
        for (final j in raw) {
          if (j is Map && j['key'] is String) out.add(ContinueItem.fromJson(j));
        }
      }
    } on FormatException {
      // begynner på nytt
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return _continue = out;
  }

  /// Du ser på dette nå: øverst i «Fortsett å se».
  void touchContinue(ContinueItem item) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _continue = [item.seenNow(now), for (final c in continueItems) if (c.key != item.key) c].take(50).toList();
    _saveContinue();
  }

  void removeContinue(String key) {
    if (!continueItems.any((c) => c.key == key)) return;
    _continue = [for (final c in continueItems) if (c.key != key) c];
    _saveContinue();
  }

  /// Uten notifyListeners: dette lagres mens filmen spiller (og når spilleren lukkes), og sidene som viser lista,
  /// tegnes på nytt når du kommer tilbake til dem.
  void _saveContinue() {
    unawaited(_prefs.setString(_k('continue'), jsonEncode([for (final c in _continue ?? const <ContinueItem>[]) c.toJson()])));
  }

  // ── utseende ──

  void toggleTheme(Brightness current) => setThemeMode(current == Brightness.dark ? ThemeMode.light : ThemeMode.dark);

  /// Lyst, mørkt, eller som Windows (system).
  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    unawaited(_prefs.setString('theme', switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    }));
    notifyListeners();
  }

  @override
  void dispose() {
    source?.dispose();
    super.dispose();
  }
}

/// Programmene for én kanal i mellomlageret: når de ble hentet, hvor mange som ble bedt om, og svaret når det er kommet.
class _EpgHit {
  _EpgHit(this.limit, this.list);

  final DateTime at = DateTime.now();
  final int limit;
  final Future<List<EpgEntry>> list;
  List<EpgEntry>? value;
}
