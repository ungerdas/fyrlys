import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:screen_retriever/screen_retriever.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'window_effects.dart';

/// Vinduet åpner der det var sist: samme størrelse og plassering, og maksimert hvis det var det. Fullskjerm huskes
/// ikke (det er noe du velger i spilleren), og et vindu som ville havnet utenfor skjermene, får standardplassen.
class WindowMemory with WindowListener {
  WindowMemory._(this._prefs);

  static const key = 'window';

  final SharedPreferences _prefs;
  Timer? _timer;

  /// Før første bilde, så vinduet ikke hopper: stiller det tilbake og følger med på endringene etterpå.
  static Future<WindowMemory> restore(SharedPreferences prefs) async {
    final memory = WindowMemory._(prefs);
    final saved = read(prefs.getString(key));
    try {
      final bounds = saved.bounds;
      if (bounds != null && await _onScreen(bounds)) await windowManager.setBounds(bounds);
      if (saved.maximized) await windowManager.maximize();
    } on Object {
      // standardplassen
    }
    windowManager.addListener(memory);
    return memory;
  }

  /// Det som er lagret: den vanlige størrelsen og plasseringen (null: ingen, ødelagt eller for lite) og om
  /// vinduet var maksimert.
  static ({Rect? bounds, bool maximized}) read(String? json) {
    const none = (bounds: null, maximized: false);
    if (json == null) return none;
    try {
      final j = jsonDecode(json);
      if (j is! Map) return none;
      double n(Object? v) => v is num ? v.toDouble() : double.nan;
      final r = Rect.fromLTWH(n(j['x']), n(j['y']), n(j['w']), n(j['h']));
      final ok = r.isFinite && r.width >= 480 && r.height >= 320;
      return (bounds: ok ? r : null, maximized: j['max'] == true);
    } on FormatException {
      return none;
    }
  }

  /// Minst en god bit av tittellinja må ligge på en av skjermene, så vinduet kan flyttes.
  static Future<bool> _onScreen(Rect r) async {
    final displays = await screenRetriever.getAllDisplays();
    final titleBar = Rect.fromLTWH(r.left, r.top, r.width, 40);
    for (final d in displays) {
      final pos = d.visiblePosition ?? Offset.zero;
      final size = d.visibleSize ?? d.size;
      final visible = (pos & size).intersect(titleBar);
      if (visible.width >= 120 && visible.height >= 20) return true;
    }
    return false;
  }

  void _later() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 600), () => unawaited(_store()));
  }

  Future<void> _store() async {
    try {
      // i fullskjerm, minimert og som minispiller er ikke størrelsen den vanlige
      if (MiniWindow.instance.active) return;
      if (await windowManager.isFullScreen() || await windowManager.isMinimized()) return;
      final maximized = await windowManager.isMaximized();
      // maksimert: behold den vanlige størrelsen fra før, så vinduet blir riktig når det gjøres vanlig igjen
      final bounds = maximized ? read(_prefs.getString(key)).bounds : await windowManager.getBounds();
      if (bounds == null) {
        await _prefs.setString(key, jsonEncode({'max': maximized}));
        return;
      }
      await _prefs.setString(
        key,
        jsonEncode({'x': bounds.left, 'y': bounds.top, 'w': bounds.width, 'h': bounds.height, 'max': maximized}),
      );
    } on Object {
      // ikke viktig nok til å stoppe noe
    }
  }

  @override
  void onWindowResize() => _later();

  @override
  void onWindowMove() => _later();

  @override
  void onWindowMaximize() => _later();

  @override
  void onWindowUnmaximize() => _later();
}
