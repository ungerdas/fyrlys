import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fyrlys_source.dart';
import 'models.dart';
import 'source.dart';
import 'xtream_source.dart';

typedef SourceFactory = Future<TvSource?> Function(Map<String, String> saved);

/// Tilstanden i appen: kilden du er logget inn på, kanallista, favoritter, «sist sett» og lys/mørk.
class Session extends ChangeNotifier {
  Session(this._prefs, {this.sourceFactory}) : themeMode = _themeFrom(_prefs.getString('theme'));

  final SharedPreferences _prefs;

  /// tester lager kilden selv i stedet for å koble til noe
  final SourceFactory? sourceFactory;

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

  final _messages = StreamController<String>.broadcast();

  /// korte beskjeder til brukeren, vises nederst på skjermen
  Stream<String> get messages => _messages.stream;

  Map<String, Channel> _byId = const {};
  final Map<String, List<Channel>> _filtered = {};
  final Map<String, ({DateTime at, Future<List<EpgEntry>> list})> _epg = {};
  int _epgBusy = 0;
  final Queue<Completer<void>> _epgWaiting = Queue();
  Future<void> _favQueue = Future.value();
  int _favPending = 0;

  static ThemeMode _themeFrom(String? s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  // ── innlogging ──

  /// Kobler til igjen med det som ble lagret sist.
  Future<void> restore() async {
    final raw = _prefs.getString('source');
    TvSource? src;
    if (raw != null) {
      try {
        final saved = (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
        final factory = sourceFactory;
        src = factory != null ? await factory(saved) : _fromPrefs(saved);
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

  TvSource? _fromPrefs(Map<String, String> s) {
    switch (s['kind']) {
      case 'fyrlys':
        final base = s['base'];
        return base == null ? null : FyrlysSource(base: base, clientId: s['client']);
      case 'xtream':
        final server = s['server'];
        final user = s['user'];
        final password = s['password'];
        if (server == null || user == null || password == null) return null;
        return XtreamSource(server: server, user: user, password: password);
    }
    return null;
  }

  Future<void> loginFyrlys(String address) async => _use(await FyrlysSource.connect(address));

  Future<void> loginXtream(String server, String user, String password) async =>
      _use(await XtreamSource.login(server, user, password));

  Future<void> _use(TvSource src) async {
    await _prefs.setString('source', jsonEncode(src.toPrefs()));
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
    if (src.sharedFavorites) {
      favorites = const [];
      favoriteCategories = const [];
    } else {
      favorites = _readChannels('favorites');
      favoriteCategories = _prefs.getStringList('favoriteCategories') ?? const [];
    }
    notifyListeners();
    unawaited(load());
    unawaited(refreshFavorites());
  }

  Future<void> logout() async {
    source?.dispose();
    source = null;
    await _prefs.remove('source');
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
      await src.prepare();
      final cats = await src.categories(force: force);
      final chans = await src.channels(force: force);
      if (source != src) return;
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
    } on SourceException catch (e) {
      if (source == src) error = e.message;
    } finally {
      if (source == src) {
        loading = false;
        notifyListeners();
      }
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
  Future<List<EpgEntry>> epg(String channelId) {
    final hit = _epg[channelId];
    if (hit != null && DateTime.now().difference(hit.at) < const Duration(minutes: 5)) return hit.list;
    final src = source;
    if (src == null) return Future.value(const <EpgEntry>[]);
    final future = _limited(() => src.epg(channelId)).catchError((Object _) => const <EpgEntry>[]);
    _epg.remove(channelId);
    _epg[channelId] = (at: DateTime.now(), list: future);
    if (_epg.length > 600) _epg.remove(_epg.keys.first);
    return future;
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
      if (_epgWaiting.isNotEmpty) _epgWaiting.removeFirst().complete();
    }
  }

  // ── favoritter og «sist sett» ──

  bool isFavorite(String id) => favorites.any((c) => c.id == id);

  bool isFavoriteCategory(String id) => favoriteCategories.contains(id);

  Future<bool> toggleFavorite(Channel ch) async {
    final on = !isFavorite(ch.id);
    favorites = on ? [...favorites, ch] : [for (final c in favorites) if (c.id != ch.id) c];
    notifyListeners();
    final src = source;
    if (src != null && src.sharedFavorites) {
      await _change(
        src,
        on
            ? {
                'op': 'add',
                'fav': {'id': ch.id, 'name': ch.name, 'icon': ch.icon, 'num': int.tryParse(ch.number ?? '') ?? ch.number},
              }
            : {'op': 'remove', 'id': ch.id},
      );
    } else {
      await _saveLocal();
    }
    return on;
  }

  Future<bool> toggleFavoriteCategory(String id) async {
    final on = !isFavoriteCategory(id);
    favoriteCategories = on ? [...favoriteCategories, id] : [for (final c in favoriteCategories) if (c != id) c];
    notifyListeners();
    final src = source;
    if (src != null && src.sharedFavorites) {
      await _change(src, {'op': on ? 'cat_add' : 'cat_remove', 'cat': id});
    } else {
      await _saveLocal();
    }
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
    final src = source;
    if (src != null && src.sharedFavorites) {
      await _change(src, {'op': 'cat_move', 'cat': id, 'step': step});
    } else {
      await _saveLocal();
    }
  }

  Future<void> _saveLocal() async {
    await _prefs.setString('favorites', jsonEncode([for (final c in favorites) c.toJson()]));
    await _prefs.setStringList('favoriteCategories', favoriteCategories);
  }

  /// Endringene sendes én om gangen. Svaret er lista slik serveren har den, også med det andre enheter har
  /// endret, og tas i bruk når køen er tom.
  Future<void> _change(TvSource src, Map<String, Object?> change) {
    _favPending++;
    final run = _favQueue.then((_) async {
      try {
        final f = await src.changeFavorites(change);
        if (_favPending == 1 && f != null && source == src) _adopt(f);
      } on SourceException catch (e) {
        _messages.add(e.message);
      } on Object {
        _messages.add('Klarte ikke å lagre favorittene');
      } finally {
        _favPending--;
      }
    });
    _favQueue = run;
    return run;
  }

  /// Henter favorittene på nytt (når appen kommer fram igjen): de kan være endret på en annen enhet.
  Future<void> refreshFavorites() async {
    final src = source;
    if (src == null || !src.sharedFavorites || _favPending > 0) return;
    try {
      final f = await src.loadFavorites();
      if (f != null && source == src && _favPending == 0) _adopt(f);
    } on SourceException {
      // beholder det vi har
    }
  }

  void _adopt(Favorites f) {
    favorites = [for (final c in f.channels) _byId[c.id] ?? c];
    favoriteCategories = f.categories;
    notifyListeners();
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

  // ── lyd ──

  /// Volumet i spilleren (0–100), som sist.
  double get volume => (_prefs.getDouble('volume') ?? 100).clamp(0, 100).toDouble();

  bool get muted => _prefs.getBool('muted') ?? false;

  /// Lagres uten å si fra til resten av appen (det skjer mens glidebryteren dras).
  void saveVolume(double volume, bool muted) {
    unawaited(_prefs.setDouble('volume', volume));
    unawaited(_prefs.setBool('muted', muted));
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
    unawaited(_messages.close());
    super.dispose();
  }
}
