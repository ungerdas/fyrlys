import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/cast/caster.dart';
import '../core/failure.dart';
import '../core/names.dart';
import '../core/picture.dart';
import '../core/session.dart';
import '../core/source.dart';
import '../core/vod.dart';
import '../l10n/tr.dart';
import '../theme.dart';
import 'cast_ui.dart';
import 'language_dialog.dart';
import 'mini_player.dart';
import 'picture_dialogs.dart';
import 'playback.dart';
import 'window_effects.dart';

export '../core/names.dart' show formatDuration;

/// Spilleren er alltid mørk.
final ThemeData _playerTheme = fyrlysTheme(Brightness.dark);

/// Noe å spille: en film, en episode eller et program i TV-arkivet.
class VodPlayItem {
  const VodPlayItem({
    required this.key,
    required this.title,
    this.url = '',
    this.subtitle = '',
    this.continueAs,
    this.archive,
  });

  /// for «fortsett der du slapp», f.eks. «film:123», «episode:456» eller «arkiv:101:1793041200»
  final String key;
  final String title;
  final String subtitle;
  final String url;

  /// slik den står i «Fortsett å se» mens du ser den
  final ContinueItem? continueAs;

  /// et program i TV-arkivet: adressen lages fra der i programmet du er (i stedet for [url])
  final ArchiveClip? archive;
}

/// Spilleren for filmer, episoder og TV-arkivet: tidslinje med spoling, ±10 sekunder, neste og forrige episode (eller
/// program), lydspor og undertekster, volum og fullskjerm. Husker hvor du slapp, og går videre til den neste når en er
/// ferdig.
class VodPlayerPage extends StatelessWidget {
  const VodPlayerPage({
    super.key,
    required this.session,
    required this.items,
    this.index = 0,
    this.resume = true,
    this.startFull = false,
    this.playback,
  });

  final Session session;

  /// filmen, eller episodene i sesongen (så den kan gå videre til neste)
  final List<VodPlayItem> items;
  final int index;

  /// fortsett der du slapp (false: fra begynnelsen)
  final bool resume;

  /// vinduet er alt i fullskjerm (åpnet fra TV-spilleren i fullskjerm)
  final bool startFull;

  /// testene bruker en falsk avspiller
  final Playback Function()? playback;

  @override
  Widget build(BuildContext context) => Theme(data: _playerTheme, child: _VodPlayer(page: this));
}

class _VodPlayer extends StatefulWidget {
  const _VodPlayer({required this.page});

  final VodPlayerPage page;

  @override
  State<_VodPlayer> createState() => _VodPlayerState();
}

class _VodPlayerState extends State<_VodPlayer> {
  late final Playback _pb = (widget.page.playback ?? playbackFactory)();
  final FocusNode _focus = FocusNode(debugLabel: 'filmspiller');
  final List<StreamSubscription<Object?>> _subs = [];

  late int _index = widget.page.index;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _started = false;
  bool _ending = false;
  String? _status;
  bool _controls = true;
  late bool _full = widget.page.startFull;
  double? _seekValue;
  bool _dragging = false;
  late double _volume = _session.volume;
  late bool _muted = _session.muted;
  PointerDeviceKind _pointer = PointerDeviceKind.mouse;
  String? _flash;
  Timer? _flashTimer;
  Timer? _hideTimer;
  Timer? _saveTimer;
  Timer? _nextTimer;

  // ── TV-arkivet: strømmen begynner på et helt minutt, og åpnes på nytt når du spoler utenfor det som er hentet ──

  /// hvor i programmet strømmen begynner
  Duration _base = Duration.zero;

  /// adressene for der den ble åpnet sist, og hvilken som prøves
  List<String> _urls = const [];
  int _urlIndex = 0;

  /// den som virket sist (HLS eller MPEG-TS): prøves først neste gang
  int _variant = 0;

  /// lengden strømmen selv oppgir (et HLS-arkiv kjenner den, og da spoler avspilleren selv)
  Duration _streamLength = Duration.zero;

  /// hoppet fram fra minuttet til der du skulle, når avspilleren har hentet så langt
  Duration? _skip;
  Timer? _skipTimer;

  /// ←/→ samles litt før det spoles
  Duration? _seekTarget;
  Timer? _seekTimer;

  /// nye åpninger når strømmen slutter før programmet (det som går nå, vokser mens du ser)
  final List<DateTime> _reopens = [];

  /// nye forsøk før feilen vises (rett etter TV-spilleren kan leverandøren ennå telle den tilkoblingen)
  int _openTries = 0;

  // ── Chromecast: det spilles på TV-en, og spilleren her viser det i stedet for bildet ──

  bool _wasCasting = appCaster.active;
  CastState? _castState;

  /// arkivet på TV-en: strømmen begynner så langt inn i programmet
  Duration _castBase = Duration.zero;

  /// hvor langt TV-en har kommet, hvert sekund (for «fortsett der du slapp»)
  Timer? _castTimer;

  /// kobler til en Chromecast (går det ikke, sier _startCast fra og spiller videre her)
  bool _connecting = false;

  bool get _casting => appCaster.active;

  Session get _session => widget.page.session;
  List<VodPlayItem> get _items => widget.page.items;
  VodPlayItem get _item => _items[_index];
  bool get _hasNext => _index + 1 < _items.length;
  bool get _hasPrev => _index > 0;
  ArchiveClip? get _clip => _item.archive;

  @override
  void initState() {
    super.initState();
    _subs
      ..add(_pb.playingStream.listen((v) => _set(() => _playing = v)))
      ..add(_pb.bufferingStream.listen((v) => _set(() => _buffering = v)))
      ..add(_pb.durationStream.listen((d) {
        // arkivet: lengden er programmets; strømmens egen brukes bare til å spole i HLS
        if (_clip != null) {
          _streamLength = d;
        } else {
          _set(() => _duration = d);
        }
      }))
      ..add(_pb.positionStream.listen(_onPosition))
      ..add(_pb.errorStream.listen(_onError))
      ..add(_pb.completedStream.listen((done) {
        if (!done || !_started) return;
        if (_clip != null) {
          _onArchiveEnd();
        } else {
          _onEnd();
        }
      }));
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _save());
    appCaster.addListener(_onCast);
    if (_casting) _startCastTimer();
    unawaited(_start());
    _wake();
  }

  @override
  void dispose() {
    _save();
    appCaster.removeListener(_onCast);
    _castTimer?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _flashTimer?.cancel();
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _nextTimer?.cancel();
    _skipTimer?.cancel();
    _seekTimer?.cancel();
    unawaited(_pb.dispose());
    _focus.dispose();
    // åpnet fra TV-spilleren i fullskjerm: den fortsetter i fullskjerm, så vinduet blir der
    if (_full && !widget.page.startFull) unawaited(WindowFullscreen.instance.set(false));
    if (_mini) unawaited(MiniWindow.instance.set(false));
    super.dispose();
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  // ── avspilling ──

  Future<void> _start() async {
    // arkivet: avspilleren tar vare på det den har hentet, så det går an å spole i det uten å åpne på nytt
    await _pb.setup(live: _items.any((i) => i.archive != null));
    await _pb.setLanguages(_session.languages);
    await _pb.setPicture(_session.picture);
    await _pb.setVolume(_muted ? 0 : _volume);
    await _open(resume: widget.page.resume);
  }

  Future<void> _open({bool resume = true}) async {
    final item = _item;
    debugPrint('Spiller ${item.key}');
    final start = resume ? _session.resumeAt(item.key) : null;
    if (_casting) {
      if (start != null) _showFlash(tr('Fortsetter fra {time}', {'time': formatDuration(start)}));
      await _castOpen(start ?? Duration.zero);
      return;
    }
    if (item.archive != null) {
      if (start != null) _showFlash(tr('Fortsetter fra {time}', {'time': formatDuration(start)}));
      await _openArchive(start ?? Duration.zero);
      return;
    }
    _set(() {
      _status = null;
      _started = false;
      _ending = false;
      _buffering = true;
      _position = start ?? Duration.zero;
      _duration = Duration.zero;
    });
    if (start != null) _showFlash(tr('Fortsetter fra {time}', {'time': formatDuration(start)}));
    try {
      await _pb.open(item.url, _session.source?.httpHeaders ?? const {}, start: start);
    } on Object catch (e) {
      _set(() {
        _status = tr('Kunne ikke spille av ({message}).', {'message': _session.source?.redact('$e') ?? e});
        _buffering = false;
      });
    }
  }

  void _onPosition(Duration raw) {
    // arkivet: strømmen begynner [_base] inn i programmet
    final p = _clip != null ? _base + raw : raw;
    if (!_started && raw > Duration.zero) {
      _openTries = 0;
      _variant = _urlIndex;
      _set(() => _started = true);
      if (_skip != null) _waitForSkip();
    }
    // spolt tilbake etter slutten: ikke ferdig likevel (og ikke videre til neste episode)
    if (_ending && _duration > Duration.zero && p < _duration - const Duration(seconds: 10)) _ending = false;
    // mens ←/→ samles, står tidslinja der du skal
    if (_seekTarget != null) return;
    // tegnes på nytt én gang i sekundet, ikke for hver melding fra avspilleren
    if (p.inSeconds != _position.inSeconds) {
      _set(() => _position = p);
    } else {
      _position = p;
    }
  }

  void _onError(String raw) {
    // mpv sier «Failed to open <hele adressen>»: rett mot leverandøren står brukernavn og passord i den
    final message = _session.source?.redact(raw) ?? raw;
    debugPrint('mpv: $message');
    if (!mounted || _started) return;
    // arkivet: HLS først, så MPEG-TS
    if (_clip != null && _urlIndex + 1 < _urls.length) {
      _urlIndex++;
      unawaited(_pb.open(_urls[_urlIndex], _session.source?.httpHeaders ?? const {}));
      return;
    }
    if (_openTries < 2) {
      _openTries++;
      final index = _index;
      Timer(const Duration(seconds: 3), () {
        if (!mounted || index != _index || _started || _status != null) return;
        unawaited(_clip != null ? _openArchive(_position) : _open());
      });
      return;
    }
    final at = _index;
    final url = _clip != null && _urls.isNotEmpty ? _urls[_urlIndex] : _item.url;
    final fallback = tr('Kunne ikke spille av ({message}).', {'message': plainMessage(message)});
    _set(() {
      _status = fallback;
      _buffering = false;
    });
    // en bedre forklaring: alle tilkoblingene i bruk, eller leverandøren avviser den (med HTTP-koden)
    final src = _session.source;
    if (src == null) return;
    unawaited(() async {
      await _pb.stop();
      final text = await explainFailure(src, url, fallback: fallback, channel: false);
      if (mounted && at == _index && !_started && _status == fallback) _set(() => _status = text);
    }());
  }

  /// Ferdig: husk at den er sett, og gå videre til neste episode.
  void _onEnd() {
    if (_ending) return;
    _ending = true;
    final d = _duration > Duration.zero ? _duration : _position;
    _session.saveResume(_item.key, d, d);
    // «Fortsett å se»: neste episode, eller borte når filmen (eller sesongen) er sett
    final next = _hasNext ? _items[_index + 1].continueAs : null;
    final current = _item.continueAs;
    if (next != null) {
      _session.touchContinue(next);
    } else if (current != null) {
      _session.removeContinue(current.key);
    }
    if (_hasNext) {
      final next = _items[_index + 1];
      _showFlash(tr('Neste: {title}', {'title': next.archive != null ? next.title : next.subtitle}));
      _nextTimer?.cancel();
      _nextTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted && _ending) _go(_index + 1);
      });
    } else {
      _wake(stay: true);
    }
  }

  /// Hvor du er, lagres hvert tiende sekund og når du går ut.
  void _save() {
    // ferdig: _onEnd har alt lagret den som sett
    if (_ending || !_started || _duration <= Duration.zero || _position <= Duration.zero) return;
    _session.saveResume(_item.key, _position, _duration);
    final c = _item.continueAs;
    if (c != null) _session.touchContinue(c);
  }

  void _go(int index) {
    if (index < 0 || index >= _items.length) return;
    _save();
    _reopens.clear();
    _openTries = 0;
    _seekTimer?.cancel();
    _seekTarget = null;
    setState(() => _index = index);
    unawaited(_open());
    _wake();
  }

  void _togglePlay() {
    if (_casting) {
      unawaited(castIsPlaying(appCaster) ? appCaster.pause() : appCaster.play());
      return;
    }
    unawaited(_pb.playOrPause());
    _wake();
  }

  /// «Prøv igjen»: arkivet der du var, ellers som da den ble åpnet
  void _retry() {
    _reopens.clear();
    _openTries = 0;
    if (_casting) {
      unawaited(_castOpen(_position));
    } else if (_clip != null) {
      unawaited(_openArchive(_position));
    } else {
      unawaited(_open());
    }
  }

  // ── Chromecast ──

  /// Spiller det som er valgt, på TV-en fra [at] (arkivet: fra minuttet før, som her).
  Future<void> _castOpen(Duration at) async {
    final item = _item;
    final clip = item.archive;
    final src = _session.source;
    var target = at < Duration.zero ? Duration.zero : at;
    final List<String> urls;
    final Duration start;
    if (clip != null) {
      if (clip.length > const Duration(seconds: 1) && target > clip.length - const Duration(seconds: 1)) {
        target = clip.length - const Duration(seconds: 1);
      }
      final u = clip.urlsAt(target);
      if (u.urls.isEmpty) return;
      urls = u.urls;
      _castBase = u.from;
      start = target - u.from;
    } else {
      urls = [item.url];
      _castBase = Duration.zero;
      start = target;
    }
    _set(() {
      _status = null;
      _started = false;
      _ending = false;
      _buffering = false;
      _position = target;
      if (clip != null) _duration = clip.length;
    });
    try {
      await appCaster.load(CastItem(
        urls: urls,
        title: item.title,
        subtitle: item.subtitle,
        headers: src?.httpHeaders ?? const {},
        start: start,
      ));
    } on Object catch (e) {
      debugPrint('Chromecast: $e');
    }
  }

  /// Spoler på TV-en (arkivet åpnes på nytt fra minuttet, som her).
  Future<void> _castSeek(Duration to) async {
    _position = to;
    if (_clip != null) {
      await _castOpen(to);
    } else {
      await appCaster.seek(to);
    }
  }

  /// Velg en Chromecast og spill videre der, fra der du er.
  Future<void> _startCast() async {
    final device = await pickCastDevice(context);
    if (device == null || !mounted) return;
    if (_mini) await _setMini(false);
    if (!mounted) return;
    if (_full) _toggleFull();
    final at = _position;
    _save();
    _seekTimer?.cancel();
    _seekTarget = null;
    _skipTimer?.cancel();
    _skip = null;
    // abonnementet har kanskje bare én tilkobling: TV-en får den
    await _pb.stop();
    _connecting = true;
    try {
      await appCaster.connect(device);
    } on Object {
      // fikk ikke kontakt: videre her, med hvorfor
      _connecting = false;
      if (!mounted) return;
      _snack(appCaster.error ?? tr('Fikk ikke kontakt med {name}. Er den på og på samme nettverk som PC-en?', {'name': device.name}));
      _openTries = 0;
      unawaited(_open());
      return;
    }
    _connecting = false;
    if (!mounted) return;
    await _castOpen(at);
  }

  void _startCastTimer() {
    _castTimer?.cancel();
    _castTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_casting) return;
      if (_seekTarget == null) _position = _castBase + appCaster.position;
      final d = appCaster.duration;
      if (_clip == null && d != null && d > Duration.zero) _duration = d;
      if (!_started && appCaster.state == CastState.playing) _started = true;
    });
  }

  /// Chromecasten har endret seg: castingen stoppet (da spilles det videre her, fra der TV-en var), filmen er
  /// ferdig (neste episode), eller det feilet.
  void _onCast() {
    if (!mounted) return;
    if (!appCaster.active) {
      if (_wasCasting) {
        _wasCasting = false;
        _castState = null;
        _castTimer?.cancel();
        final error = appCaster.error;
        if (error != null && !_connecting) _snack(error);
        if (!_connecting) {
          _save();
          _openTries = 0;
          unawaited(_open());
        }
      }
      _set(() {});
      return;
    }
    if (!_wasCasting) {
      _wasCasting = true;
      _startCastTimer();
    }
    final state = appCaster.state;
    final before = _castState;
    _castState = state;
    if (state != before && before != null && _status == null) {
      if (state == CastState.ended) {
        _onEnd();
      } else if (state == CastState.failed) {
        _status = appCaster.error ?? tr('Chromecasten kunne ikke spille dette.');
      }
    }
    _set(() {});
  }

  void _snack(String text) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 5)));
  }

  // ── TV-arkivet ──

  /// Åpner arkivet [at] inn i programmet: strømmen begynner på minuttet før, og resten hoppes over når avspilleren
  /// har hentet så langt.
  Future<void> _openArchive(Duration at) async {
    final clip = _clip;
    if (clip == null) return;
    final length = clip.length;
    var target = at < Duration.zero ? Duration.zero : at;
    if (length > const Duration(seconds: 1) && target > length - const Duration(seconds: 1)) {
      target = length - const Duration(seconds: 1);
    }
    final u = clip.urlsAt(target);
    if (u.urls.isEmpty) return;
    _skipTimer?.cancel();
    _base = u.from;
    _urls = u.urls;
    _urlIndex = math.min(_variant, u.urls.length - 1);
    _streamLength = Duration.zero;
    final skip = target - u.from;
    _skip = skip > const Duration(seconds: 2) ? skip : null;
    _set(() {
      _status = null;
      _started = false;
      _ending = false;
      _buffering = true;
      _position = target;
      _duration = length;
    });
    try {
      await _pb.open(_urls[_urlIndex], _session.source?.httpHeaders ?? const {});
    } on Object catch (e) {
      _set(() {
        _status = tr('Kunne ikke spille av ({message}).', {'message': _session.source?.redact('$e') ?? e});
        _buffering = false;
      });
    }
  }

  bool get _isHls => _urls.isNotEmpty && _urls[math.min(_urlIndex, _urls.length - 1)].contains('.m3u8');

  /// Når avspilleren har hentet langt nok, hoppes det fram til der du skulle (strømmen begynte på minuttet før).
  void _waitForSkip() {
    _skipTimer?.cancel();
    final until = DateTime.now().add(const Duration(seconds: 20));
    Future<void> tick() async {
      final skip = _skip;
      if (!mounted || skip == null) return;
      if (DateTime.now().isAfter(until)) {
        // kom ikke så langt: blir der den er
        _skip = null;
        return;
      }
      if (_isHls && _streamLength > Duration.zero) {
        _skip = null;
        await _pb.seek(skip);
        return;
      }
      final delta = skip - _pb.position;
      final c = await _pb.liveCache();
      if (!mounted || _skip != skip) return;
      if (c != null && delta <= c.ahead) {
        _skip = null;
        if (delta > const Duration(milliseconds: 500)) await _pb.seekBy(delta);
        return;
      }
      _skipTimer = Timer(const Duration(milliseconds: 500), () => unawaited(tick()));
    }

    unawaited(tick());
  }

  /// Spoler til [target] i programmet: i det avspilleren har (eller i HLS-strømmen), ellers åpnes den på nytt der.
  Future<void> _seekArchive(Duration target) async {
    final clip = _clip;
    if (clip == null) return;
    final last = clip.length - const Duration(seconds: 1);
    final to = target < Duration.zero ? Duration.zero : (target > last ? last : target);
    _skip = null;
    if (_started) {
      if (_isHls && _streamLength > Duration.zero) {
        final rel = to - _base;
        if (rel >= Duration.zero && rel <= _streamLength) {
          await _pb.seek(rel);
          _set(() => _position = to);
          return;
        }
      }
      final delta = to - (_base + _pb.position);
      final c = await _pb.liveCache();
      if (c != null && delta >= -c.back && delta <= c.ahead) {
        await _pb.seekBy(delta);
        _set(() => _position = to);
        return;
      }
    }
    await _openArchive(to);
  }

  /// Strømmen sluttet. Ferdig når programmet er sett; ellers (det som går nå, er ikke ferdig lagret ennå) åpnes
  /// den igjen der du er, inntil tre ganger i minuttet.
  void _onArchiveEnd() {
    final clip = _clip;
    if (clip == null) return;
    if (_position >= clip.length - const Duration(minutes: 1)) {
      _onEnd();
      return;
    }
    final now = DateTime.now();
    _reopens.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (_reopens.length >= 3) {
      _set(() {
        _status = clip.stop.isAfter(now)
            ? tr('Du har tatt igjen sendingen. Prøv igjen om litt for å se resten.')
            : tr('Arkivet stoppet før programmet var slutt.');
        _buffering = false;
      });
      return;
    }
    _reopens.add(now);
    unawaited(_openArchive(_position));
  }

  void _seekBy(int seconds) {
    if (_casting) {
      final total = _clip?.length ?? appCaster.duration ?? Duration.zero;
      final from = _seekTarget ?? (_castBase + appCaster.position);
      var to = from + Duration(seconds: seconds);
      if (to < Duration.zero) to = Duration.zero;
      if (total > const Duration(seconds: 1) && to > total - const Duration(seconds: 1)) {
        to = total - const Duration(seconds: 1);
      }
      _seekTarget = to;
      _showFlash(seconds < 0 ? '−${-seconds} s' : '+$seconds s');
      _seekTimer?.cancel();
      _seekTimer = Timer(const Duration(milliseconds: 450), () {
        final t = _seekTarget;
        _seekTarget = null;
        if (mounted && t != null) unawaited(_castSeek(t));
      });
      return;
    }
    if (_clip != null) {
      // trykk som kommer tett, samles før det spoles
      final from = _seekTarget ?? _position;
      final last = _duration - const Duration(seconds: 1);
      var to = from + Duration(seconds: seconds);
      if (to < Duration.zero) to = Duration.zero;
      if (last > Duration.zero && to > last) to = last;
      _seekTarget = to;
      _set(() => _position = to);
      _showFlash(seconds < 0 ? '−${-seconds} s' : '+$seconds s');
      _seekTimer?.cancel();
      _seekTimer = Timer(const Duration(milliseconds: 450), () {
        final t = _seekTarget;
        _seekTarget = null;
        if (mounted && t != null) unawaited(_seekArchive(t));
      });
      _wake();
      return;
    }
    if (_duration <= Duration.zero) return;
    var to = _position + Duration(seconds: seconds);
    if (to < Duration.zero) to = Duration.zero;
    if (to > _duration) to = _duration;
    unawaited(_pb.seek(to));
    _set(() => _position = to);
    _showFlash(seconds < 0 ? '−${-seconds} s' : '+$seconds s');
    _wake();
  }

  // ── lyd ──

  void _applyVolume({bool save = true}) {
    unawaited(_pb.setVolume(_muted ? 0 : _volume));
    if (save) _session.saveVolume(_volume, _muted);
  }

  void _setVolume(double v, {bool save = true}) {
    final next = v.clamp(0.0, 100.0).toDouble();
    setState(() {
      _volume = next;
      _muted = next == 0;
    });
    _applyVolume(save: save);
  }

  void _toggleMute() {
    if (_casting) {
      unawaited(appCaster.setMuted(!appCaster.muted));
      return;
    }
    setState(() {
      _muted = !_muted;
      if (!_muted && _volume == 0) _volume = 50;
    });
    _applyVolume();
    _showFlash(_muted ? tr('Lyd av') : tr('Lyd {n} %', {'n': _volume.round()}));
  }

  void _nudgeVolume(double step) {
    if (_casting) {
      unawaited(appCaster.setVolume(appCaster.volume + step / 100));
      _showFlash(tr('Volum på TV-en {n} %', {'n': (appCaster.volume * 100).round()}));
      return;
    }
    _setVolume((_muted ? 0 : _volume) + step);
    _showFlash(_muted ? tr('Lyd av') : tr('Lyd {n} %', {'n': _volume.round()}));
  }

  void _onWheel(PointerSignalEvent event) {
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      if (e is PointerScrollEvent && e.scrollDelta.dy != 0) {
        _nudgeVolume(e.scrollDelta.dy < 0 ? 5 : -5);
        _wake();
      }
    });
  }

  // ── visning ──

  void _showFlash(String text) {
    _flashTimer?.cancel();
    _set(() => _flash = text);
    _flashTimer = Timer(const Duration(milliseconds: 1400), () => _set(() => _flash = null));
  }

  /// bildeformatet og lydforsinkelsen, så lenge spilleren er åpen
  PictureFormat _format = PictureFormat.original;
  Duration _audioDelay = Duration.zero;

  /// minispilleren: et lite vindu alltid øverst, med bare bildet
  bool _mini = false;

  /// Minispilleren (I). Fra fullskjerm går det rett dit.
  Future<void> _setMini(bool on) async {
    if (on == _mini || !mounted || (on && _casting)) return;
    setState(() {
      _mini = on;
      if (on) _full = false;
    });
    // MiniWindow tar vinduet ut av fullskjerm selv
    await MiniWindow.instance.set(on);
    if (!mounted) return;
    _focus.requestFocus();
    _wake();
  }

  void _setFormat(PictureFormat format) {
    _set(() => _format = format);
    _showFlash(tr('Bildeformat: {name}', {'name': formatName(format)}));
  }

  void _setAudioDelay(Duration delay) {
    _set(() => _audioDelay = delay);
    unawaited(_pb.setAudioDelay(delay));
  }

  void _wake({bool stay = false}) {
    _hideTimer?.cancel();
    if (!_controls) _set(() => _controls = true);
    if (stay) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (_playing && _status == null && !_dragging) _set(() => _controls = false);
    });
  }

  void _toggleFull() {
    // mens det castes, er det ikke noe bilde her å vise stort
    if (_casting && !_full && !_mini) return;
    // minispilleren: tilbake til det store vinduet
    if (_mini) {
      unawaited(_setMini(false));
      return;
    }
    setState(() => _full = !_full);
    unawaited(WindowFullscreen.instance.set(_full));
    _wake();
  }

  void _close() {
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  void _onTap() {
    if (_pointer == PointerDeviceKind.mouse) {
      if (_status == null) _togglePlay();
      return;
    }
    if (_controls) {
      _hideTimer?.cancel();
      setState(() => _controls = false);
    } else {
      _wake();
    }
  }

  static final _playKeys = {
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.keyK,
    LogicalKeyboardKey.mediaPlayPause,
    LogicalKeyboardKey.select,
    LogicalKeyboardKey.enter,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isMetaPressed || keyboard.isAltPressed) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final repeat = event is KeyRepeatEvent;
    _wake();
    if (_status != null && !repeat && _focus.hasPrimaryFocus && (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.select)) {
      // OK når «Prøv igjen» vises: knappen på kortet (den får ikke fokus selv)
      _retry();
    } else if (_playKeys.contains(key) && !repeat && _focus.hasPrimaryFocus) {
      _togglePlay();
    } else if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.keyJ || key == LogicalKeyboardKey.mediaRewind) {
      _seekBy(-10);
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.keyL ||
        key == LogicalKeyboardKey.mediaFastForward) {
      _seekBy(10);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _nudgeVolume(5);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _nudgeVolume(-5);
    } else if (repeat) {
      return KeyEventResult.ignored;
    } else if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (key == LogicalKeyboardKey.keyF) {
      _toggleFull();
    } else if (key == LogicalKeyboardKey.keyZ) {
      _setFormat(_format.next);
    } else if (key == LogicalKeyboardKey.keyN || key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.mediaTrackNext) {
      if (_hasNext) _go(_index + 1);
    } else if (key == LogicalKeyboardKey.keyP || key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.mediaTrackPrevious) {
      if (_hasPrev) _go(_index - 1);
    } else if (key == LogicalKeyboardKey.keyI) {
      unawaited(_setMini(!_mini));
    } else if (key == LogicalKeyboardKey.escape) {
      if (_mini) {
        unawaited(_setMini(false));
      } else if (_full) {
        _toggleFull();
      } else {
        _close();
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 680;
    final showBars = _controls || _status != null;
    final flash = _flash;
    final status = _status;
    return PopScope(
      canPop: !_full && !_mini,
      onPopInvokedWithResult: (didPop, _) {
        // lagres med en gang du går ut, så siden du kommer tilbake til («Fortsett fra …») er oppdatert, og strømmen
        // stopper med en gang (TV-spilleren under åpner kanalen igjen, og abonnementet har kanskje bare én tilkobling)
        if (didPop) {
          _save();
          unawaited(_pb.stop());
        }
        if (!didPop && (_full || _mini)) _toggleFull();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: _casting ? _castStage(compact: compact) : Listener(
            onPointerDown: (e) => _pointer = e.kind,
            onPointerSignal: _onWheel,
            child: MouseRegion(
              cursor: showBars ? MouseCursor.defer : SystemMouseCursors.none,
              onHover: (_) => _wake(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onTap,
                    onDoubleTap: _toggleFull,
                    // minispilleren har ingen tittellinje: bildet flytter vinduet
                    onPanStart: _mini ? (_) => dragWindow() : null,
                    child: _pb.view(format: _format),
                  ),
                  if (_buffering && status == null) const IgnorePointer(child: Center(child: CircularProgressIndicator())),
                  if (flash != null)
                    Positioned(
                      top: _mini ? 44 : 96,
                      right: 20,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(color: const Color(0xA6000000), borderRadius: BorderRadius.circular(12)),
                          child: Text(flash,
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ),
                  ExcludeFocus(
                    excluding: !showBars,
                    child: IgnorePointer(
                      ignoring: !showBars,
                      child: AnimatedOpacity(
                        opacity: showBars ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: _mini
                            ? MiniControls(
                                title: _item.title,
                                playing: _playing,
                                muted: _muted,
                                onPlayPause: _togglePlay,
                                onMute: _toggleMute,
                                onExpand: () => unawaited(_setMini(false)),
                                onClose: _close,
                              )
                            : Stack(
                                children: [
                                  Positioned(left: 0, right: 0, top: 0, child: _topBar()),
                                  Positioned(left: 0, right: 0, bottom: 0, child: _bottomBar(compact: compact)),
                                ],
                              ),
                      ),
                    ),
                  ),
                  if (status != null) _card(status),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Mens det castes: hva og hvor, tidslinja, og knapper for spoling, forrige/neste, pause, volumet på TV-en og
  /// «Stopp casting».
  Widget _castStage({required bool compact}) {
    final item = _item;
    final status = _status;
    final total = _clip?.length ?? appCaster.duration ?? Duration.zero;
    return Stack(
      fit: StackFit.expand,
      children: [
        CastPanel(
          caster: appCaster,
          title: item.title,
          subtitle: item.subtitle,
          compact: compact,
          progress: total > Duration.zero
              ? CastProgress(
                  position: () => _seekTarget ?? (_castBase + appCaster.position),
                  duration: total,
                  onSeek: (to) => unawaited(_castSeek(to)),
                )
              : null,
          leading: [
            if (_items.length > 1)
              _ctl(Icons.skip_previous, _clip != null ? tr('Forrige program (P)') : tr('Forrige episode (P)'),
                  _hasPrev ? () => _go(_index - 1) : null),
            _ctl(Icons.replay_10, tr('10 sekunder tilbake (←)'), () => _seekBy(-10)),
            _ctl(Icons.forward_10, tr('10 sekunder fram (→)'), () => _seekBy(10)),
            if (_items.length > 1)
              _ctl(Icons.skip_next, _clip != null ? tr('Neste program (N)') : tr('Neste episode (N)'),
                  _hasNext ? () => _go(_index + 1) : null),
          ],
          onStop: () => unawaited(appCaster.stop()),
        ),
        Positioned(
          left: 12,
          top: 12,
          child: SafeArea(
            right: false,
            bottom: false,
            child: Material(
              color: const Color(0x8C000000),
              shape: const CircleBorder(side: BorderSide(color: Color(0x2EFFFFFF))),
              child: IconButton(
                tooltip: tr('Lukk (Esc)'),
                icon: const Icon(Icons.close, size: 20),
                color: Colors.white,
                onPressed: _close,
              ),
            ),
          ),
        ),
        if (status != null) _card(status),
      ],
    );
  }

  Widget _topBar() {
    final item = _item;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xD1000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 16, 40),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Material(
                color: const Color(0x8C000000),
                shape: const CircleBorder(side: BorderSide(color: Color(0x2EFFFFFF))),
                child: IconButton(
                  tooltip: tr('Lukk (Esc)'),
                  icon: const Icon(Icons.close, size: 20),
                  color: Colors.white,
                  onPressed: _close,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700),
                    ),
                    if (item.subtitle.isNotEmpty)
                      Text(
                        item.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFDFE6EA), fontSize: 14),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar({required bool compact}) {
    final total = _duration.inMilliseconds / 1000;
    final at = _seekValue ?? (_position.inMilliseconds / 1000).clamp(0, total > 0 ? total : 0).toDouble();
    final volume = _muted ? 0.0 : _volume;
    final volumeIcon = volume == 0 ? Icons.volume_off : (volume < 50 ? Icons.volume_down : Icons.volume_up);
    final timeStyle = const TextStyle(color: Colors.white, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xDB000000), Color(0x00000000)],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(compact ? 6 : 16, 40, compact ? 6 : 16, compact ? 4 : 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(formatDuration(Duration(milliseconds: (at * 1000).round())), style: timeStyle),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        activeTrackColor: FyrlysColors.live,
                        inactiveTrackColor: Colors.white24,
                        thumbColor: Colors.white,
                        overlayColor: Colors.white24,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      ),
                      child: Slider(
                        value: total > 0 ? at.clamp(0, total).toDouble() : 0,
                        max: total > 0 ? total : 1,
                        semanticFormatterCallback: (v) => formatDuration(Duration(seconds: v.round())),
                        onChangeStart: total > 0
                            ? (v) {
                                _dragging = true;
                                setState(() => _seekValue = v);
                              }
                            : null,
                        onChanged: total > 0
                            ? (v) {
                                setState(() => _seekValue = v);
                                _wake();
                              }
                            : null,
                        onChangeEnd: total > 0
                            ? (v) {
                                _dragging = false;
                                final to = Duration(milliseconds: (v * 1000).round());
                                unawaited(_clip != null ? _seekArchive(to) : _pb.seek(to));
                                setState(() {
                                  _seekValue = null;
                                  _position = to;
                                });
                                _wake();
                              }
                            : null,
                      ),
                    ),
                  ),
                  Text(total > 0 ? formatDuration(_duration) : '–:––', style: timeStyle),
                ],
              ),
              Row(
                children: [
                  _ctl(_playing ? Icons.pause : Icons.play_arrow,
                      _playing ? tr('Pause (mellomrom)') : tr('Spill av (mellomrom)'), _togglePlay,
                      size: 30),
                  _ctl(Icons.replay_10, tr('10 sekunder tilbake (←)'), () => _seekBy(-10)),
                  _ctl(Icons.forward_10, tr('10 sekunder fram (→)'), () => _seekBy(10)),
                  if (_items.length > 1) ...[
                    _ctl(Icons.skip_previous, _clip != null ? tr('Forrige program (P)') : tr('Forrige episode (P)'),
                        _hasPrev ? () => _go(_index - 1) : null),
                    _ctl(Icons.skip_next, _clip != null ? tr('Neste program (N)') : tr('Neste episode (N)'),
                        _hasNext ? () => _go(_index + 1) : null),
                  ],
                  const Spacer(),
                  _ctl(volumeIcon, _muted ? tr('Lyd på (M)') : tr('Lyd av (M)'), _toggleMute),
                  if (!compact) _volumeSlider(volume),
                  _tracksButton(),
                  if (!compact) _ctl(Icons.cast, tr('Cast til TV (Chromecast)'), () => unawaited(_startCast())),
                  if (!compact)
                    _ctl(Icons.picture_in_picture_alt_outlined, tr('Minispiller (I)'), () => unawaited(_setMini(true))),
                  _ctl(_full ? Icons.fullscreen_exit : Icons.fullscreen,
                      _full ? tr('Avslutt fullskjerm (F)') : tr('Fullskjerm (F)'), _toggleFull),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ctl(IconData icon, String tooltip, VoidCallback? onPressed, {double size = 24}) {
    return IconButton(
      tooltip: tooltip,
      iconSize: size,
      color: Colors.white,
      disabledColor: Colors.white38,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }

  Widget _volumeSlider(double volume) {
    return SizedBox(
      width: 100,
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          activeTrackColor: Colors.white,
          inactiveTrackColor: Colors.white24,
          thumbColor: Colors.white,
          overlayColor: Colors.white24,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        ),
        child: Slider(
          value: volume,
          max: 100,
          semanticFormatterCallback: (v) => tr('Volum {n} %', {'n': v.round()}),
          onChangeStart: (_) => _dragging = true,
          onChanged: (v) {
            _setVolume(v, save: false);
            _wake();
          },
          onChangeEnd: (v) {
            _dragging = false;
            _setVolume(v);
          },
        ),
      ),
    );
  }

  Widget _tracksButton() => TracksButton(
        playback: _pb,
        session: _session,
        onOpen: () => _hideTimer?.cancel(),
        onClose: _wake,
        format: _format,
        onFormat: _setFormat,
        audioDelay: _audioDelay,
        onAudioDelay: _setAudioDelay,
      );

  Widget _card(String text) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xE60C1B29),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1D3449)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
              const SizedBox(height: 16),
              FilledButton(autofocus: true, onPressed: _retry, child: Text(tr('Prøv igjen'))),
            ],
          ),
        ),
      ),
    );
  }
}
