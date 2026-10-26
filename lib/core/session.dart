import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Tilstanden i appen: kilden du er logget inn på, kanallista, favoritter, «sist sett» og lys/mørk.
class Session extends ChangeNotifier {
  Session(this._prefs, {this.sourceFactory, this.listCache, SecretCodec? secrets})
      : _secrets = secrets ?? SecretCodec.platform(),
        themeMode = _themeFrom(_prefs.getString('theme'));

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

  // Innloggingen lagres kryptert i 'source_protected' (2.1.13); 'source' er klartekst (før 2.1.13, eller når
  // krypteringen ikke virker).
  static const _plainKey = 'source';
  static const _protectedKey = 'source_protected';

  /// Kobler til igjen med det som ble lagret sist.
  Future<void> restore() async {
    String? raw;
    final protected = _prefs.getString(_protectedKey);
    if (protected != null) raw = _secrets.unprotect(protected);
    final plain = raw == null ? _prefs.getString(_plainKey) : null;
    raw ??= plain;
    TvSource? src;
    if (raw != null) {
      try {
        final saved = (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
        final factory = sourceFactory;
        src = factory != null ? await factory(saved) : _fromPrefs(saved);
        // lagret i klartekst fra før: krypteres nå
        if (src != null && plain != null) await _saveSource(raw);
      } on Object {
        src = null;
      }
    }
    recent = _readChannels('recent');
    restoring = false;
    if (src != null) {
      _attach(src);
    } else {
      notifyListeners();
    }
  }

  /// Kryptert når det går (og bare når det kan leses igjen); ellers i klartekst som før.
  Future<void> _saveSource(String json) async {
    final protected = _secrets.protect(json);
    if (protected != null && _secrets.unprotect(protected) == json) {
      await _prefs.setString(_protectedKey, protected);
      await _prefs.remove(_plainKey);
    } else {
      await _prefs.setString(_plainKey, json);
      await _prefs.remove(_protectedKey);
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

  Future<void> _use(TvSource src) async {
    await _saveSource(jsonEncode(src.toPrefs()));
    _attach(src);
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
    favorites = _readChannels('favorites');
    favoriteCategories = _prefs.getStringList('favoriteCategories') ?? const [];
    notifyListeners();
    unawaited(_startLists(src));
  }

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

  static String _cacheKey(TvSource src) => '${src.kind}|${src.label}';

  Future<void> logout() async {
    source?.dispose();
    source = null;
    await _prefs.remove(_plainKey);
    await _prefs.remove(_protectedKey);
    categories = const [];
    channels = const [];
    categoryCounts = const {};
    favorites = const [];
    favoriteCategories = const [];
    _byId = const {};
    _filtered.clear();
    _epg.clear();
    error = null;
    notifyListeners();
  }

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
      if (source == src) error = e.message;
    } on Object {
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
    await _prefs.setString('favorites', jsonEncode([for (final c in favorites) c.toJson()]));
    await _prefs.setStringList('favoriteCategories', favoriteCategories);
  }

  void addRecent(Channel ch) {
    recent = [ch, for (final c in recent) if (c.id != ch.id) c].take(12).toList();
    unawaited(_prefs.setString('recent', jsonEncode([for (final c in recent) c.toJson()])));
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
  String? get guideCategory => _prefs.getString('guide_cat');

  void saveGuideCategory(String filter) => unawaited(_prefs.setString('guide_cat', filter));

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
      final raw = jsonDecode(_prefs.getString('resume') ?? '{}');
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
    unawaited(_prefs.setString('resume', jsonEncode(m)));
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
      final raw = jsonDecode(_prefs.getString('continue') ?? '[]');
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
    unawaited(_prefs.setString('continue', jsonEncode([for (final c in _continue ?? const <ContinueItem>[]) c.toJson()])));
  }

  // ── utseende ──

  void toggleTheme(Brightness current) {
    themeMode = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
    unawaited(_prefs.setString('theme', themeMode == ThemeMode.light ? 'light' : 'dark'));
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
