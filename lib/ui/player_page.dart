import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/names.dart';
import '../core/session.dart';
import '../core/source.dart';
import '../theme.dart';
import 'archive_page.dart';
import 'channel_card.dart';
import 'channel_number.dart';
import 'language_dialog.dart';
import 'motion.dart';
import 'multiview_page.dart';
import 'playback.dart';
import 'side_list.dart';
import 'vod_player_page.dart';
import 'window_effects.dart';

/// Spilleren er alltid mørk.
final ThemeData _playerTheme = fyrlysTheme(Brightness.dark);

const _ink2 = Color(0xFFB3C1CD);
const _dim = Color(0xFF9FB0BB);
const _sideBg = Color(0xF20B111A);

/// Spilleren: bildet med kontroller og programinfo under, og kanallista ved siden av
/// (under på smale skjermer). Fullskjerm viser bare bildet, og kanallista kan da legges over det (C).
/// mpv (via media_kit) spiller strømmen direkte. Brytes den, eller står bildet fast, prøver spilleren på nytt
/// inntil tre ganger i minuttet. Pause og tilbakespoling i direktesendinger går i avspillerens eget buffer.
class PlayerPage extends StatelessWidget {
  const PlayerPage({
    super.key,
    required this.session,
    required this.channels,
    required this.index,
    this.listTitle = 'Kanaler',
    this.fromFavorites = false,
    this.playback,
  });

  final Session session;

  /// lista du valgte fra; ▲▼ blar i den
  final List<Channel> channels;
  final int index;

  /// navnet på lista, vises på fanen i kanallista
  final String listTitle;

  /// valgt fra favorittene: kanallista viser dem, og den andre fanen blir alle kanaler
  final bool fromFavorites;

  /// testene bruker en falsk avspiller
  final Playback Function()? playback;

  @override
  Widget build(BuildContext context) => Theme(data: _playerTheme, child: _Player(page: this));
}

class _Player extends StatefulWidget {
  const _Player({required this.page});

  final PlayerPage page;

  @override
  State<_Player> createState() => _PlayerState();
}

class _PlayerState extends State<_Player> {
  late final Playback _pb = (widget.page.playback ?? playbackFactory)();
  final FocusNode _focus = FocusNode(debugLabel: 'spiller');
  final FocusNode _searchFocus = FocusNode(debugLabel: 'søk i kanallista');
  final FocusNode _sideFocus = FocusNode(debugLabel: 'kanallista', skipTraversal: true);
  final GlobalKey _stageKey = GlobalKey(debugLabel: 'bildet');
  final GlobalKey<ChannelSideListState> _sideKey = GlobalKey(debugLabel: 'kanallista');
  final List<StreamSubscription<Object?>> _subs = [];
  final List<DateTime> _retries = [];

  late List<Channel> _list = widget.page.channels;
  late int _index = widget.page.index;
  late SideTab _tab = widget.page.fromFavorites ? SideTab.fav : SideTab.list;

  /// kanalen du så før denne (⇄ / Backspace)
  ({List<Channel> list, int index})? _last;
  Channel? _opened;
  int _seq = 0;
  PlayTarget? _target;
  int _url = 0;

  /// nye forsøk på å åpne kanalen før feilen vises (leverandøren kan ennå telle en strøm som nettopp ble stoppet)
  int _openTries = 0;
  bool _started = false;
  bool _buffering = true;
  bool _playing = false;
  bool _userPaused = false;

  late double _volume = widget.page.session.volume;
  late bool _muted = widget.page.session.muted;
  bool _dragging = false;

  /// du har valgt fullskjerm (bare bildet)
  bool _full = false;

  /// fullskjerm nå (satt i build)
  bool _fullNow = false;

  /// det vinduet sist ble satt til
  bool? _shownFull;

  /// kanallista over bildet i fullskjerm
  bool _sideOpen = false;
  bool _controls = true;
  PointerDeviceKind _pointer = PointerDeviceKind.mouse;
  String? _status;
  List<EpgEntry> _epg = const [];
  int? _height;
  String _tech = '';
  String? _flash;
  Timer? _flashTimer;
  Timer? _hideTimer;
  Timer? _epgTimer;
  Timer? _probeTimer;
  Timer? _watchdog;
  Duration _lastPos = Duration.zero;
  DateTime _lastMove = DateTime.now();

  // ── pause og tilbakespoling i det avspilleren har tatt vare på ──

  /// hvor langt tilbake det går an å spole akkurat nå
  Duration _window = Duration.zero;

  /// der ←/→ og knappene skal, mens tastetrykkene samles (så tre trykk blir 30 sekunder)
  Duration? _shiftTarget;
  Timer? _shiftTimer;

  /// tidslinja mens den dras: sekunder bak direkte
  double? _shiftDrag;

  /// det avspilleren har tatt vare på rundt der du er, og når det sist ble spurt om
  LiveCache? _cache;
  DateTime _cacheAt = DateTime(2000);
  bool _cachePolling = false;

  /// hvor mye avspilleren har hentet foran når du ser direkte (strømmen kommer i biter, så det er aldri 0)
  Duration? _liveAhead;

  /// du ser direkte (ikke pauset eller spolt tilbake siden): da følges [_liveAhead] med
  bool _localLive = true;

  /// tall du taster for å gå til en kanal; samles til det har gått 1,4 sekunder uten nye
  String _digits = '';
  Timer? _digitTimer;

  /// kanalen ↑/↓ har bladd fram til (plassen i lista); den startes først når du slutter å bla
  int? _pendingZap;
  Timer? _zapTimer;

  /// programinfoen til kanalen du blar forbi
  Future<List<EpgEntry>>? _pendingEpg;

  /// kanalinfoen nederst i bildet: noen sekunder etter et kanalbytte, og til den nye kanalen har startet
  bool _bannerOn = false;
  bool _switching = false;
  Timer? _bannerTimer;

  Channel get _channel => _list[_index];
  Session get _session => widget.page.session;
  TvSource? get _source => _session.source;

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
    _subs
      ..add(_pb.playingStream.listen((v) => _set(() => _playing = v)))
      ..add(_pb.bufferingStream.listen((v) => _set(() => _buffering = v)))
      ..add(_pb.positionStream.listen((p) {
        if (!_started && p > Duration.zero) {
          _openTries = 0;
          _set(() {
            _started = true;
            _switching = false;
            _status = null;
          });
          _probe();
        }
      }))
      ..add(_pb.heightStream.listen((h) => _set(() => _height = h)))
      ..add(_pb.errorStream.listen(_onError))
      ..add(_pb.completedStream.listen((done) {
        if (done && _started) _ended('sendingen stoppet');
      }));
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    unawaited(_start());
    _wake();
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _flashTimer?.cancel();
    _hideTimer?.cancel();
    _epgTimer?.cancel();
    _probeTimer?.cancel();
    _watchdog?.cancel();
    _shiftTimer?.cancel();
    _digitTimer?.cancel();
    _zapTimer?.cancel();
    _bannerTimer?.cancel();
    unawaited(_pb.dispose());
    _focus.dispose();
    _searchFocus.dispose();
    _sideFocus.dispose();
    if (_shownFull == true) unawaited(_windowFull(false));
    super.dispose();
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  /// favoritter og «sist sett» er endret
  void _onSession() => _set(() {});

  // ── avspilling ──

  Future<void> _start() async {
    await _pb.setup(live: true);
    await _pb.setLanguages(_session.languages);
    await _pb.setPicture(_session.picture);
    await _pb.setVolume(_muted ? 0 : _volume);
    await _open();
  }

  Future<void> _open() async {
    final src = _source;
    if (src == null || !mounted) return;
    final my = ++_seq;
    final ch = _channel;
    _opened = ch;
    _session.addRecent(ch);
    _loadEpg(ch);
    _probeTimer?.cancel();
    _target = null;
    _set(() {
      _status = null;
      _started = false;
      _buffering = true;
      _userPaused = false;
      _tech = '';
    });
    _lastPos = Duration.zero;
    _lastMove = DateTime.now();
    _resetShift();
    try {
      final t = await src.open(ch);
      if (my != _seq || !mounted) return;
      _target = t;
      _url = 0;
      await _pb.open(t.urls.first, src.httpHeaders);
    } on SourceException catch (e) {
      if (my != _seq || !mounted) return;
      await _pb.stop();
      // byttet kanal mens avspilleren stoppet: ikke vis den gamle kanalens beskjed på den nye
      if (my != _seq || !mounted) return;
      _set(() {
        _status = e.message;
        _buffering = false;
      });
    }
  }

  /// Neste adresse (HLS → MPEG-TS) før bildet har startet.
  bool _nextUrl() {
    final t = _target;
    if (t == null || _url + 1 >= t.urls.length) return false;
    _url++;
    _lastMove = DateTime.now();
    unawaited(_pb.open(t.urls[_url], _source?.httpHeaders ?? const {}));
    return true;
  }

  void _onError(String raw) {
    // mpv sier «Failed to open <hele adressen>»: rett mot leverandøren står brukernavn og passord i den
    final message = _source?.redact(raw) ?? raw;
    debugPrint('mpv: $message');
    if (!mounted || _started || _status != null || _target == null) return;
    if (_nextUrl()) return;
    final my = _seq;
    // Siste adresse. Rett etter en annen strøm (arkivet, multiview, en annen enhet) kan leverandøren ennå telle den
    // gamle tilkoblingen: prøv kanalen igjen to ganger før feilen vises.
    if (_openTries < 2) {
      _openTries++;
      Timer(const Duration(seconds: 3), () {
        if (mounted && my == _seq && !_started && _status == null) unawaited(_open());
      });
      return;
    }
    Timer(const Duration(seconds: 4), () async {
      if (!mounted || my != _seq || _started || _status != null) return;
      unawaited(_pb.stop());
      final busy = await _busy();
      if (!mounted || my != _seq || _started || _status != null) return;
      _set(() {
        _status = busy ?? 'Kanalen kunne ikke spilles ($message).';
        _buffering = false;
      });
    });
  }

  /// En forklaring når leverandøren sier at alle tilkoblingene er i bruk (ellers null).
  Future<String?> _busy() async {
    final src = _source;
    if (src == null) return null;
    try {
      return busyText(await src.account(fresh: true).timeout(const Duration(seconds: 8)));
    } on Object {
      return null;
    }
  }

  /// Strømmen stoppet etter at den hadde startet. Åpne kanalen på nytt via kilden (så «alle tilkoblinger
  /// i bruk» vises om noen har tatt over), inntil tre ganger i minuttet.
  void _ended(String why) {
    final now = DateTime.now();
    _retries.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (_retries.length >= 3) {
      unawaited(_pb.stop());
      _set(() {
        _status = 'Kanalen stoppet ($why).';
        _buffering = false;
      });
      return;
    }
    _retries.add(now);
    final my = _seq;
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted && my == _seq) unawaited(_open());
    });
  }

  /// Vakt: står bildet fast uten at mpv sier fra, prøves det på nytt. Spør også avspilleren hva den har tatt vare
  /// på (pause og tilbakespoling).
  void _check() {
    final t = _target;
    if (!mounted || _status != null || t == null) return;
    if (t.localShift && (_started || _userPaused)) unawaited(_pollCache());
    final now = DateTime.now();
    final pos = _pb.position;
    if (pos != _lastPos || _userPaused) {
      _lastPos = pos;
      _lastMove = now;
      return;
    }
    final still = now.difference(_lastMove);
    if (_started && still > const Duration(seconds: 20)) {
      _lastMove = now;
      _ended('bildet sto fast');
    } else if (!_started && still > const Duration(seconds: 30)) {
      _lastMove = now;
      if (!_nextUrl()) {
        unawaited(_pb.stop());
        _set(() {
          _status = 'Fikk ikke bilde fra kanalen.';
          _buffering = false;
        });
      }
    }
  }

  /// Kodek og dekoding vises i infoen når bildet har kommet i gang, og oppdateres hvert 5. s (bitrate og tapte
  /// bilder endrer seg mens du ser).
  void _probe() {
    _probeTimer?.cancel();
    final my = _seq;
    Future<void> update() async {
      final text = await _pb.describe();
      if (mounted && my == _seq && text != _tech) setState(() => _tech = text);
    }

    late final Timer first;
    first = Timer(const Duration(milliseconds: 1500), () async {
      await update();
      if (mounted && my == _seq && identical(_probeTimer, first)) {
        _probeTimer = Timer.periodic(const Duration(seconds: 5), (_) => unawaited(update()));
      }
    });
    _probeTimer = first;
  }

  void _loadEpg(Channel ch) {
    _epgTimer?.cancel();
    _set(() => _epg = const []);
    Future<void> load() async {
      final list = await _session.epg(ch.id);
      if (mounted && _opened?.id == ch.id) setState(() => _epg = list);
    }

    unawaited(load());
    _epgTimer = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(load()));
  }

  // ── kontroller ──

  void _wake() {
    _hideTimer?.cancel();
    if (!_controls) _set(() => _controls = true);
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (_playing && _status == null && !_sideOpen && !_dragging) _set(() => _controls = false);
    });
  }

  void _togglePlay() {
    if (_playing) {
      _userPaused = true;
      _localLive = false;
    } else {
      _userPaused = false;
    }
    unawaited(_pb.playOrPause());
    _wake();
  }

  // ── pause og tilbakespoling ──

  /// En direktesending der avspilleren har sagt hva den har tatt vare på: da går det an å spole i det.
  bool get _canShift {
    final t = _target;
    return t != null && t.localShift && _cache != null && _liveAhead != null && _status == null;
  }

  /// Hvor langt bak direkte du er: hvor mye mer avspilleren har hentet foran enn når du ser direkte (og på pause
  /// vokser det til den spør igjen).
  Duration get _behind {
    if (!_canShift) return Duration.zero;
    var b = _cache!.ahead - _liveAhead!;
    if (_userPaused) b += clock.now().difference(_cacheAt);
    return b < Duration.zero ? Duration.zero : b;
  }

  /// Direkte: litt bak og ikke pauset (strømmen kommer i biter på opptil ti sekunder).
  bool get _atLive => !_canShift || (_behind < const Duration(seconds: 15) && !_userPaused);

  void _resetShift() {
    _window = Duration.zero;
    _shiftTarget = null;
    _shiftTimer?.cancel();
    _shiftDrag = null;
    // tidslinja kan ha forsvunnet midt i et drag (da kommer aldri onChangeEnd)
    _dragging = false;
    _cache = null;
    _cacheAt = DateTime(2000);
    _liveAhead = null;
    _localLive = true;
  }

  /// Spør avspilleren hva den har tatt vare på. Mens du ser direkte, følges det den har foran med (det minste).
  Future<void> _pollCache() async {
    if (_cachePolling) return;
    _cachePolling = true;
    final my = _seq;
    try {
      final c = await _pb.liveCache();
      if (!mounted || my != _seq || c == null) return;
      final base = _liveAhead;
      if (_localLive && !_userPaused && (base == null || c.ahead < base)) _liveAhead = c.ahead;
      final live = _liveAhead ?? c.ahead;
      final behind = c.ahead > live ? c.ahead - live : Duration.zero;
      _set(() {
        _cache = c;
        _cacheAt = clock.now();
        _window = c.back + behind;
      });
    } finally {
      _cachePolling = false;
    }
  }

  /// Hopper i det avspilleren har tatt vare på, [back] bak direkte (0 = direkte), uten å åpne strømmen på nytt.
  Future<void> _shiftTo(Duration back) async {
    if (!_canShift) return;
    final c = _cache;
    final live = _liveAhead;
    if (c == null || live == null) return;
    final now = _behind;
    var target = back < Duration.zero ? Duration.zero : back;
    if (target > c.back + now) target = c.back + now;
    final delta = now - target;
    _shiftTarget = null;
    _localLive = target < const Duration(seconds: 3);
    if (delta.abs() >= const Duration(milliseconds: 500)) await _pb.seekBy(delta);
    if (!mounted) return;
    // det avspilleren har bak og foran, flytter seg like mye (og spørres på nytt om litt)
    final backNow = c.back + delta;
    _set(() {
      _cache = (back: backNow < Duration.zero ? Duration.zero : backNow, ahead: live + target);
      _cacheAt = clock.now();
    });
    _lastMove = DateTime.now();
  }

  /// ←/→ og knappene: flytt [seconds] (negativt er tilbake). Trykk som kommer tett, samles før det hoppes.
  void _nudgeShift(int seconds) {
    if (!_canShift) return;
    if (seconds > 0 && _shiftTarget == null && _atLive) {
      // allerede direkte: ingenting å spole fram til (og ikke last strømmen på nytt)
      _showFlash('Direkte');
      _wake();
      return;
    }
    var to = (_shiftTarget ?? _behind) - Duration(seconds: seconds);
    if (to < Duration.zero) to = Duration.zero;
    if (to > _window) to = _window;
    _shiftTarget = to;
    _showFlash(to < const Duration(seconds: 3) ? 'Direkte' : '−${formatDuration(to)}');
    _shiftTimer?.cancel();
    _shiftTimer = Timer(const Duration(milliseconds: 450), () {
      final target = _shiftTarget;
      if (mounted && target != null) unawaited(_shiftTo(target));
    });
    _wake();
  }

  void _goLive() {
    if (!_canShift) return;
    if (_atLive && _playing) {
      _showFlash('Direkte');
      return;
    }
    _shiftTimer?.cancel();
    unawaited(_shiftTo(Duration.zero));
    _wake();
  }

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
    setState(() {
      _muted = !_muted;
      if (!_muted && _volume == 0) _volume = 50;
    });
    _applyVolume();
    _showFlash(_muted ? 'Lyd av' : 'Lyd ${_volume.round()} %');
  }

  void _nudgeVolume(double step) {
    _setVolume((_muted ? 0 : _volume) + step);
    _showFlash(_muted ? 'Lyd av' : 'Lyd ${_volume.round()} %');
  }

  /// musehjulet over bildet styrer lyden (PC)
  void _onWheel(PointerSignalEvent event) {
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      if (e is PointerScrollEvent && e.scrollDelta.dy != 0) {
        _nudgeVolume(e.scrollDelta.dy < 0 ? 5 : -5);
        _wake();
      }
    });
  }

  void _showFlash(String text) {
    _flashTimer?.cancel();
    setState(() => _flash = text);
    _flashTimer = Timer(const Duration(milliseconds: 1200), () => _set(() => _flash = null));
  }

  void _toggleFull() {
    setState(() {
      _full = !_full;
      if (!_full) _sideOpen = false;
    });
    _focus.requestFocus();
    _wake();
  }

  /// Vinduet følger fullskjermen.
  void _syncFull(bool full) {
    if (_shownFull == full) return;
    final first = _shownFull == null;
    _shownFull = full;
    if (!first || full) unawaited(_windowFull(full));
  }

  Future<void> _windowFull(bool on) => WindowFullscreen.instance.set(on);

  /// Kanallista: over bildet i fullskjerm, ellers flyttes fokus dit (den står alltid ved siden av).
  void _toggleSide() {
    if (!_fullNow) {
      _sideKey.currentState?.focusCurrent();
      return;
    }
    setState(() => _sideOpen = !_sideOpen);
    if (_sideOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sideKey.currentState?.focusCurrent();
      });
    } else {
      _focus.requestFocus();
    }
    _wake();
  }

  /// Bytter til en kanal i en liste (▲▼ blar videre i den lista).
  void _switchTo(List<Channel> list, int index) {
    if (index < 0 || index >= list.length) return;
    _zapTimer?.cancel();
    _pendingZap = null;
    if (list[index].id == _channel.id) {
      setState(() {
        _list = list;
        _index = index;
      });
      // samme kanal: prøv igjen hvis den hadde stoppet
      if (_status != null) _retry();
      return;
    }
    _last = (list: _list, index: _index);
    _retries.clear();
    _openTries = 0;
    setState(() {
      _list = list;
      _index = index;
      _switching = true;
    });
    _showBanner();
    unawaited(_open());
    _wake();
  }

  /// ↑/↓: kanalinfoen blar gjennom lista med en gang, og kanalen du stopper på, startes etter et øyeblikk (eller
  /// straks med OK). Kanalene du blar forbi, startes ikke (med én tilkobling ville hver av dem tatt den).
  void _zap(int step) {
    final n = _list.length;
    if (n < 2) return;
    final to = ((_pendingZap ?? _index) + step) % n;
    _zapTimer?.cancel();
    setState(() {
      _pendingZap = to;
      _pendingEpg = _wantsEpg(_list[to]) ? _session.epg(_list[to].id) : null;
    });
    _zapTimer = Timer(const Duration(milliseconds: 650), _commitZap);
  }

  void _commitZap() {
    _zapTimer?.cancel();
    final to = _pendingZap;
    if (!mounted || to == null) return;
    if (to == _index) {
      setState(() => _pendingZap = null);
      return;
    }
    _switchTo(_list, to);
  }

  /// Bla tilbake til kanalen som spilles (Esc mens du blar).
  void _cancelZap() {
    _zapTimer?.cancel();
    setState(() => _pendingZap = null);
  }

  static bool _wantsEpg(Channel ch) => ch.hasEpg && nameParts(ch.name).sub.isEmpty;

  void _showBanner() {
    _bannerTimer?.cancel();
    _bannerOn = true;
    _bannerTimer = Timer(const Duration(seconds: 4), () => _set(() => _bannerOn = false));
  }

  bool get _bannerVisible =>
      _status == null && (_pendingZap != null || _bannerOn || (_switching && !_started));

  void _lastChannel() {
    final last = _last;
    if (last != null) _switchTo(last.list, last.index);
  }

  /// Et tall fra tastaturet eller fjernkontrollen: «1» og «2» rett etter hverandre er kanal 12.
  void _typeDigit(String digit) {
    _digitTimer?.cancel();
    final next = _digits + digit;
    setState(() => _digits = next.length > 4 ? next.substring(next.length - 4) : next);
    _digitTimer = Timer(const Duration(milliseconds: 1400), _goToNumber);
  }

  /// Kanalen med nummeret: i lista du ser fra først, ellers blant alle kanalene.
  void _goToNumber() {
    _digitTimer?.cancel();
    final digits = _digits;
    _set(() => _digits = '');
    if (digits.isEmpty || !mounted) return;
    final i = channelByNumber(_list, digits);
    if (i >= 0) {
      _switchTo(_list, i);
      return;
    }
    final all = _session.channels;
    final j = channelByNumber(all, digits);
    if (j >= 0) {
      _switchTo(all, j);
    } else {
      _showFlash('Fant ikke kanal ${int.parse(digits)}');
    }
  }

  void _retry() {
    _retries.clear();
    _openTries = 0;
    unawaited(_open());
  }

  // ── TV-arkivet ──

  bool get _hasArchive => _channel.hasArchive;

  /// Programmet som går nå, når det har gått mer enn et minutt (da er det noe å se fra start).
  EpgEntry? get _startable {
    if (!_hasArchive) return null;
    final now = DateTime.now();
    final cur = nowAndNext(_epg, now).now;
    if (cur == null || now.difference(cur.start) < const Duration(minutes: 1)) return null;
    return cur;
  }

  /// Direktesendingen stopper mens du er i arkivet (abonnementet har kanskje bare én tilkobling), og starter igjen
  /// når du kommer tilbake.
  Future<void> _away(Future<void> Function() visit) async {
    _seq++;
    _zapTimer?.cancel();
    _pendingZap = null;
    // et kanalnummer du holdt på å taste, skal ikke starte en kanal mens arkivet spiller
    _digitTimer?.cancel();
    _digits = '';
    _probeTimer?.cancel();
    _target = null;
    _resetShift();
    await _pb.stop();
    _set(() {
      _started = false;
      _buffering = false;
      _status = null;
    });
    await visit();
    if (!mounted) return;
    _retries.clear();
    _openTries = 0;
    unawaited(_open());
  }

  /// Programmet som går nå, fra start (i spilleren for arkivet, i fullskjerm om du er der).
  Future<void> _startOver() async {
    final cur = _startable;
    if (cur == null) return;
    final ch = _channel;
    final ArchiveClip clip;
    try {
      clip = await _session.archiveClip(ch, cur);
    } on SourceException catch (e) {
      if (mounted) _showFlash(e.message);
      return;
    }
    if (!mounted) return;
    final nav = Navigator.of(context);
    final full = _full;
    await _away(() async {
      await nav.push(fadeRoute<void>((_) => VodPlayerPage(
            session: _session,
            items: [archivePlayItem(ch, cur, clip)],
            resume: false,
            startFull: full,
          )));
      // spilleren for arkivet kan ha tatt vinduet ut av fullskjerm; her settes det slik denne spilleren er
      _shownFull = null;
    });
  }

  /// Flere kanaler samtidig, med denne i det første bildet (i fullskjerm om du er der).
  Future<void> _openMultiview() async {
    if (!_session.canMultiview) return;
    final ch = _channel;
    final nav = Navigator.of(context);
    final full = _full;
    await _away(() async {
      await nav.push(fadeRoute<void>((_) => MultiviewPage(session: _session, first: ch, startFull: full)));
      _shownFull = null;
    });
  }

  /// TV-arkivet for kanalen.
  Future<void> _openArchive() async {
    if (!_hasArchive) return;
    final ch = _channel;
    final nav = Navigator.of(context);
    // arkivet er en vanlig side: ut av fullskjerm først
    if (_full) {
      setState(() {
        _full = false;
        _sideOpen = false;
      });
    }
    await _away(() => nav.push(fadeRoute<void>((_) => ArchivePage(session: _session, channel: ch))));
  }

  void _close() {
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  void _toggleFav(Channel ch, {bool named = false}) {
    final on = !_session.isFavorite(ch.id);
    unawaited(_session.toggleFavorite(ch));
    final name = nameParts(ch.name).main;
    final text = named
        ? (on ? '$name er lagt til i favoritter' : '$name er fjernet fra favoritter')
        : (on ? 'Lagt til i favoritter' : 'Fjernet fra favoritter');
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 2)));
  }

  void _onStageTap() {
    if (_pointer == PointerDeviceKind.mouse) {
      // med mus: pause
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

  // ── tastatur og fjernkontroll ──

  static final _upKeys = {LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.pageUp, LogicalKeyboardKey.channelUp};
  static final _downKeys = {LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.pageDown, LogicalKeyboardKey.channelDown};
  static final _playKeys = {LogicalKeyboardKey.space, LogicalKeyboardKey.keyK, LogicalKeyboardKey.mediaPlayPause};
  static final _okKeys = {LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter, LogicalKeyboardKey.select};

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    // du skriver i søkefeltet: bare Esc er vår
    if (_searchFocus.hasFocus) {
      if (key != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
      _focus.requestFocus();
      if (_sideOpen) _toggleSide();
      return KeyEventResult.handled;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isMetaPressed || keyboard.isAltPressed) return KeyEventResult.ignored;
    _wake();
    // tall går til kanalen med det nummeret, også fra kanallista; OK går dit med en gang
    final digit = digitOf(key);
    if (digit != null) {
      _typeDigit(digit);
      return KeyEventResult.handled;
    }
    if (_digits.isNotEmpty && _okKeys.contains(key)) {
      _goToNumber();
      return KeyEventResult.handled;
    }
    // mens du blar: OK starter kanalen med en gang, Esc blir på den du ser
    if (_pendingZap != null && _okKeys.contains(key)) {
      _commitZap();
      return KeyEventResult.handled;
    }
    if (_pendingZap != null && key == LogicalKeyboardKey.escape) {
      _cancelZap();
      return KeyEventResult.handled;
    }
    // i kanallista flytter piltastene mellom kanalene; ← og Esc går tilbake til bildet
    if (_sideFocus.hasFocus) {
      if (key != LogicalKeyboardKey.escape && key != LogicalKeyboardKey.arrowLeft) return KeyEventResult.ignored;
      if (_sideOpen) {
        _toggleSide();
      } else {
        _focus.requestFocus();
      }
      return KeyEventResult.handled;
    }
    if (_upKeys.contains(key)) {
      _zap(-1);
    } else if (_downKeys.contains(key)) {
      _zap(1);
    } else if (_playKeys.contains(key)) {
      _togglePlay();
    } else if (_canShift && (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.mediaRewind)) {
      _nudgeShift(-10);
    } else if (_canShift &&
        (key == LogicalKeyboardKey.mediaFastForward ||
            (key == LogicalKeyboardKey.arrowRight && _focus.hasPrimaryFocus))) {
      // → spoler fram
      _nudgeShift(10);
    } else if (_canShift && (key == LogicalKeyboardKey.keyL || key == LogicalKeyboardKey.end)) {
      _goLive();
    } else if (key == LogicalKeyboardKey.mediaPlay) {
      if (!_playing) _togglePlay();
    } else if (key == LogicalKeyboardKey.mediaPause) {
      if (_playing) _togglePlay();
    } else if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (key == LogicalKeyboardKey.keyF) {
      _toggleFull();
    } else if (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.contextMenu) {
      _toggleSide();
    } else if (key == LogicalKeyboardKey.keyA && _hasArchive) {
      unawaited(_openArchive());
    } else if (key == LogicalKeyboardKey.keyV && _session.canMultiview) {
      unawaited(_openMultiview());
    } else if (key == LogicalKeyboardKey.backspace) {
      _lastChannel();
    } else if (key == LogicalKeyboardKey.escape) {
      if (_sideOpen) {
        _toggleSide();
      } else if (_full) {
        _toggleFull();
      } else {
        _close();
      }
    } else if (_okKeys.contains(key) && _focus.hasPrimaryFocus && _status != null) {
      // OK/Enter når kortet med «Prøv igjen» vises: knappen på kortet (den får ikke fokus selv)
      _retry();
    } else if (_okKeys.contains(key) && _focus.hasPrimaryFocus) {
      // OK/Enter: fullskjerm, og i fullskjerm kanallista
      if (_fullNow) {
        _toggleSide();
      } else {
        _toggleFull();
      }
    } else if (key == LogicalKeyboardKey.arrowRight && _focus.hasPrimaryFocus && !_fullNow) {
      _sideKey.currentState?.focusCurrent();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // ── visning ──

  /// «1080p · H.264 · maskinvaredekoding (d3d11va) · AAC stereo · HLS rett fra leverandøren»
  String _meta() => [
        if ((_height ?? 0) > 0) '${_height}p',
        if (_tech.isNotEmpty) _tech,
        _route(),
      ].where((s) => s.isNotEmpty).join(' · ');

  String _route() {
    final t = _target;
    if (t == null) return '';
    final url = t.urls[math.min(_url, t.urls.length - 1)];
    final kind = url.contains('.m3u8') ? 'HLS ' : (url.contains('.ts') ? 'MPEG-TS ' : '');
    return '${kind}rett fra leverandøren';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final full = _full;
    _fullNow = full;
    // ute av fullskjerm: kanallista over bildet finnes ikke lenger
    if (!full) _sideOpen = false;
    if (_shownFull != full) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncFull(full);
      });
    }
    final wide = size.width >= 860;
    final stageWidth = full ? size.width : (wide ? size.width - 404 - pad.horizontal : size.width - pad.horizontal);
    final stage = KeyedSubtree(
      key: _stageKey,
      child: _stage(full: full, compact: stageWidth < 680),
    );
    final scheme = Theme.of(context).colorScheme;
    final Widget body;
    if (full) {
      body = Stack(
        fit: StackFit.expand,
        children: [
          stage,
          if (_sideOpen)
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: math.min(380.0, size.width),
              child: Material(color: _sideBg, child: SafeArea(left: false, child: _side(overlay: true))),
            ),
        ],
      );
    } else if (wide) {
      final h = math.max(180.0, math.min((stageWidth) * 9 / 16, size.height - pad.vertical - 190));
      body = SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: h, child: ClipRRect(borderRadius: BorderRadius.circular(12), child: stage)),
                    _info(wide: true),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 360,
              child: Material(
                color: _sideBg,
                shape: Border(left: BorderSide(color: scheme.outline)),
                child: _side(),
              ),
            ),
          ],
        ),
      );
    } else {
      body = SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: math.min(stageWidth * 9 / 16, size.height * 0.45), child: stage),
            _info(wide: false),
            Expanded(
              child: Material(
                color: _sideBg,
                shape: Border(top: BorderSide(color: scheme.outline)),
                child: _side(),
              ),
            ),
          ],
        ),
      );
    }
    return PopScope(
      canPop: !_full && !_sideOpen,
      onPopInvokedWithResult: (didPop, _) {
        // ut av spilleren: strømmen stopper med en gang (ikke først når siden er borte), så tilkoblingen er ledig
        if (didPop) {
          unawaited(_pb.stop());
          return;
        }
        if (_sideOpen) {
          _toggleSide();
        } else if (_full) {
          _toggleFull();
        }
      },
      child: Scaffold(
        backgroundColor: full ? Colors.black : scheme.surfaceContainerLowest,
        body: Focus(focusNode: _focus, autofocus: true, onKeyEvent: _onKey, child: body),
      ),
    );
  }

  /// Bildet med det som ligger over: kontroller, venting, beskjeder. Samme widget i alle oppsett (GlobalKey),
  /// så avspillingen ikke forstyrres når du går inn og ut av fullskjerm.
  Widget _stage({required bool full, required bool compact}) {
    final status = _status;
    final flash = _flash;
    final showBars = _controls || status != null;
    return Listener(
      onPointerDown: (e) {
        _pointer = e.kind;
        if (!_focus.hasPrimaryFocus) _focus.requestFocus();
      },
      onPointerSignal: _onWheel,
      child: MouseRegion(
        cursor: showBars ? MouseCursor.defer : SystemMouseCursors.none,
        onHover: (_) => _wake(),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // trykk og dobbeltklikk bare på selve bildet, så knappene svarer med en gang
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onStageTap,
              onDoubleTap: _toggleFull,
              child: _pb.view(),
            ),
            if (_buffering && status == null)
              const IgnorePointer(child: Center(child: CircularProgressIndicator())),
            if (flash != null && _digits.isEmpty)
              Positioned(top: full ? 96 : 16, right: 20, child: IgnorePointer(child: _flashBadge(flash))),
            if (_digits.isNotEmpty)
              Positioned(top: full ? 96 : 16, right: 20, child: IgnorePointer(child: NumberBadge(digits: _digits))),
            // kanalinfoen ved bytte, over kontrollene når de vises
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              left: compact ? 10 : 20,
              right: compact ? 10 : null,
              bottom: showBars ? (compact ? 62 : (_canShift && _window >= const Duration(seconds: 20) ? 112 : 86)) : 20,
              child: IgnorePointer(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOut,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(animation),
                      child: child,
                    ),
                  ),
                  child: _bannerVisible
                      ? KeyedSubtree(
                          key: ValueKey('banner:${(_pendingZap != null ? _list[_pendingZap!] : _channel).id}'),
                          child: _banner(compact: compact),
                        )
                      : const SizedBox.shrink(key: ValueKey('banner:none')),
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
                  child: _overlay(full: full, compact: compact),
                ),
              ),
            ),
            if (status != null) _card(text: status, action: 'Prøv igjen', onPressed: _retry),
          ],
        ),
      ),
    );
  }

  Widget _overlay({required bool full, required bool compact}) {
    return Stack(
      children: [
        // kanalinfoen nederst viser det samme mens den er framme
        if (full && !_bannerVisible) Positioned(left: 0, right: 0, top: 0, child: _topBar()),
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
                tooltip: 'Lukk (Esc)',
                icon: const Icon(Icons.close, size: 20),
                color: Colors.white,
                onPressed: _close,
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _bottomBar(full: full, compact: compact),
        ),
      ],
    );
  }

  /// I fullskjerm: kanal og program øverst på bildet.
  Widget _topBar() {
    final ch = _channel;
    final parts = nameParts(ch.name);
    final nn = nowAndNext(_epg, DateTime.now());
    final cur = nn.now;
    final next = nn.next;
    final meta = _meta();
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
          padding: const EdgeInsets.fromLTRB(68, 14, 12, 40),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _title(ch, parts, size: 19, color: Colors.white, numberColor: _dim),
                    if (cur != null)
                      _nowLine(cur, color: const Color(0xFFDFE6EA), bar: 90, fontSize: 14)
                    else if (parts.sub.isNotEmpty)
                      Text(parts.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _dim)),
                    if (next != null)
                      Text(
                        'Deretter ${hhmm(next.start)}: ${next.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _dim, fontSize: 13),
                      ),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF8696A2), fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
              _star(ch, idle: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bottomBar({required bool full, required bool compact}) {
    final volume = _muted ? 0.0 : _volume;
    final volumeIcon = volume == 0 ? Icons.volume_off : (volume < 50 ? Icons.volume_down : Icons.volume_up);
    final shift = _canShift;
    final timeline = shift && _window >= const Duration(seconds: 20);
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
          padding: EdgeInsets.fromLTRB(compact ? 4 : 12, timeline ? 30 : 44, compact ? 4 : 12, compact ? 4 : 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (timeline) _timeline(),
              Row(
                children: [
                  _ctl(_playing ? Icons.pause : Icons.play_arrow,
                      _playing ? 'Pause (mellomrom)' : 'Spill av (mellomrom)', _togglePlay,
                      size: 30),
                  if (shift && !compact) ...[
                    _ctl(Icons.replay_10, '10 sekunder tilbake (←)', () => _nudgeShift(-10)),
                    _ctl(Icons.forward_10, '10 sekunder fram (→)', _atLive ? null : () => _nudgeShift(10)),
                  ],
                  _liveBadge(compact: compact),
                  const Spacer(),
                  // smal skjerm med tidslinje: kanallista under bildet bytter kanal, så pilene får vike
                  if (!compact || !shift) ...[
                    _ctl(Icons.keyboard_arrow_up, 'Forrige kanal (↑)', () => _zap(-1)),
                    _ctl(Icons.keyboard_arrow_down, 'Neste kanal (↓)', () => _zap(1)),
                  ],
                  if (!compact)
                    _ctl(Icons.swap_horiz, 'Kanalen du så sist (Backspace)', _last == null ? null : _lastChannel),
                  // smalt vindu: knappene står under bildet
                  if (_hasArchive && (!compact || full)) ...[
                    _ctl(Icons.restart_alt, 'Se fra start', _startable == null ? null : () => unawaited(_startOver())),
                    _ctl(Icons.history, 'TV-arkiv (A)', () => unawaited(_openArchive())),
                  ],
                  if (_session.canMultiview && (!compact || full))
                    _ctl(Icons.grid_view_outlined, 'Multiview (V)', () => unawaited(_openMultiview())),
                  _ctl(volumeIcon, _muted ? 'Lyd på (M)' : 'Lyd av (M)', _toggleMute),
                  if (!compact) _volumeSlider(volume),
                  if (full) _ctl(Icons.list, 'Kanaler (C)', _toggleSide, on: _sideOpen),
                  _tracksButton(),
                  _ctl(full ? Icons.fullscreen_exit : Icons.fullscreen, full ? 'Avslutt fullskjerm (F)' : 'Fullskjerm (F)',
                      _toggleFull),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Tidslinja for direktesendingen: fra så langt tilbake serveren har, til direkte helt til høyre.
  Widget _timeline() {
    final window = _window.inMilliseconds / 1000;
    final behindSec = _shiftDrag ?? math.min(_behind.inMilliseconds / 1000, window);
    final label = _shiftDrag != null
        ? (behindSec < 3 ? 'Direkte' : '−${formatDuration(Duration(milliseconds: (behindSec * 1000).round()))}')
        : '−${formatDuration(_window)}';
    const timeStyle = TextStyle(color: Colors.white, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]);
    return Row(
      children: [
        const SizedBox(width: 8),
        Text(label, style: timeStyle),
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
              key: const ValueKey('live-timeline'),
              value: (window - behindSec).clamp(0.0, window).toDouble(),
              max: window,
              semanticFormatterCallback: (v) {
                final back = window - v;
                return back < 3 ? 'Direkte' : '${formatDuration(Duration(seconds: back.round()))} bak direkte';
              },
              onChangeStart: (v) {
                _dragging = true;
                setState(() => _shiftDrag = window - v);
              },
              onChanged: (v) {
                setState(() => _shiftDrag = window - v);
                _wake();
              },
              onChangeEnd: (v) {
                _dragging = false;
                setState(() => _shiftDrag = null);
                _shiftTimer?.cancel();
                unawaited(_shiftTo(Duration(milliseconds: ((window - v) * 1000).round())));
                _wake();
              },
            ),
          ),
        ),
        const Text('Direkte', style: timeStyle),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _ctl(IconData icon, String tooltip, VoidCallback? onPressed, {double size = 24, bool on = false}) {
    return IconButton(
      tooltip: tooltip,
      iconSize: size,
      color: on ? Theme.of(context).colorScheme.primary : Colors.white,
      disabledColor: Colors.white38,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }

  /// «DIREKTE»: rød når du ser direkte; ellers grå, med hvor langt bak du er, og et trykk tar deg til direkte.
  Widget _liveBadge({required bool compact}) {
    final shift = _canShift;
    final at = shift ? _atLive && _playing : _playing;
    final behind = _behind;
    final badge = Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: at ? FyrlysColors.live : Colors.white24,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: SizedBox(width: 8, height: 8),
          ),
          SizedBox(width: 7),
          Text(
            'DIREKTE',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.7),
          ),
        ],
      ),
    );
    final showBehind = shift && !_atLive && behind >= const Duration(seconds: 1);
    if (compact && !shift) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (shift && !at)
            Tooltip(
              message: 'Gå til direkte (L)',
              child: InkWell(borderRadius: BorderRadius.circular(14), onTap: _goLive, child: badge),
            )
          else
            badge,
          if (showBehind)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                '−${formatDuration(behind)}',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]),
              ),
            ),
        ],
      ),
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
          semanticFormatterCallback: (v) => 'Volum ${v.round()} %',
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
        onClose: () {
          _wake();
          _probe();
        },
      );

  /// Kanalinfoen ved bytte, som på en TV-boks: logo, nummer, navn, og programmet nå og etterpå.
  Widget _banner({required bool compact}) {
    final pending = _pendingZap;
    final ch = pending != null ? _list[pending] : _channel;
    final parts = nameParts(ch.name);
    final scheme = Theme.of(context).colorScheme;
    Widget program(List<EpgEntry> epg) {
      final nn = nowAndNext(epg, DateTime.now());
      final cur = nn.now;
      final next = nn.next;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (cur != null) ...[
            Text(cur.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFDFE6EA), fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 5),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${hhmm(cur.start)}–${hhmm(cur.stop)}', style: const TextStyle(color: _dim, fontSize: 12.5)),
                const SizedBox(width: 10),
                SizedBox(
                  width: compact ? 70 : 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: cur.progressAt(DateTime.now()),
                      minHeight: 3,
                      color: scheme.primary,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ),
              ],
            ),
          ] else if (parts.sub.isNotEmpty)
            Text(parts.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink2)),
          if (next != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Så ${hhmm(next.start)}  ${next.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _dim, fontSize: 12.5),
              ),
            ),
        ],
      );
    }

    final Widget info = pending == null
        ? program(_epg)
        : FutureBuilder<List<EpgEntry>>(
            future: _pendingEpg,
            initialData: _session.epgCached(ch.id),
            builder: (context, snap) => program(snap.data ?? const []),
          );
    final loading = pending == null && _switching && !_started;
    return Container(
      key: const ValueKey('channel-banner'),
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.fromLTRB(12, 12, 18, 12),
      decoration: BoxDecoration(
        color: const Color(0xE6091019),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x24FFFFFF)),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 20, offset: Offset(0, 6))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChannelLogo(
            url: _source?.logoUrl(ch.icon),
            name: ch.name,
            width: compact ? 64 : 84,
            height: compact ? 48 : 62,
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (ch.number != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          ch.number!,
                          style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800, fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 9),
                    ],
                    Flexible(
                      child: Text(
                        parts.time.isEmpty ? parts.main : '${parts.time} · ${parts.main}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                    if (loading) ...[
                      const SizedBox(width: 10),
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                info,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _flashBadge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: const Color(0xA6000000), borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
    );
  }

  Widget _card({required String text, required String action, required VoidCallback onPressed}) {
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
              FilledButton(autofocus: true, onPressed: onPressed, child: Text(action)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title(Channel ch, NameParts parts,
      {required double size, required Color color, required Color numberColor, int maxLines = 1}) {
    final scheme = Theme.of(context).colorScheme;
    return Text.rich(
      TextSpan(children: [
        if (ch.number != null)
          TextSpan(
            text: '${ch.number}  ',
            style: TextStyle(color: numberColor, fontSize: (size * 0.65).roundToDouble(), fontWeight: FontWeight.w700),
          ),
        if (parts.time.isNotEmpty) TextSpan(text: '${parts.time}  ', style: TextStyle(color: scheme.primary)),
        TextSpan(text: parts.main),
      ]),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(color: color, fontSize: size, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.25),
    );
  }

  Widget _nowLine(EpgEntry cur, {required Color color, double? bar, double fontSize = 14}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Flexible(
            child: Text(
              cur.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: fontSize),
            ),
          ),
          const SizedBox(width: 10),
          Text('${hhmm(cur.start)}–${hhmm(cur.stop)}', style: TextStyle(color: _dim, fontSize: fontSize - 1)),
          if (bar != null) ...[
            const SizedBox(width: 10),
            SizedBox(
              width: bar,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: cur.progressAt(DateTime.now()),
                  minHeight: 3,
                  color: scheme.primary,
                  backgroundColor: Colors.white24,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _star(Channel ch, {required Color idle}) {
    final scheme = Theme.of(context).colorScheme;
    final fav = _session.isFavorite(ch.id);
    return IconButton(
      key: const ValueKey('player-star'),
      tooltip: fav ? 'Fjern fra favoritter' : 'Legg til i favoritter',
      icon: Icon(fav ? Icons.star : Icons.star_border, size: 26, color: fav ? scheme.primary : idle),
      onPressed: () => _toggleFav(ch),
    );
  }

  /// Under bildet: kanal, stjerne, programmet nå og etterpå, beskrivelse og teknisk info.
  Widget _info({required bool wide}) {
    final ch = _channel;
    final parts = nameParts(ch.name);
    final nn = nowAndNext(_epg, DateTime.now());
    final cur = nn.now;
    final next = nn.next;
    final scheme = Theme.of(context).colorScheme;
    final meta = _meta();
    return Padding(
      padding: wide ? const EdgeInsets.fromLTRB(2, 14, 2, 8) : const EdgeInsets.fromLTRB(14, 8, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Flexible(
                child: _title(
                  ch,
                  parts,
                  size: wide ? 24 : 18,
                  color: scheme.onSurface,
                  numberColor: scheme.onSurfaceVariant,
                  maxLines: wide ? 2 : 1,
                ),
              ),
              _star(ch, idle: scheme.onSurfaceVariant),
            ],
          ),
          if (cur != null)
            _nowLine(cur, color: scheme.onSurface, bar: wide ? 140 : null, fontSize: wide ? 15 : 14)
          else if (parts.sub.isNotEmpty)
            Text(parts.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _ink2)),
          if (next != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Deretter ${hhmm(next.start)}: ${next.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _ink2, fontSize: 14),
              ),
            ),
          if (_hasArchive || _session.canMultiview)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (_hasArchive) ...[
                    OutlinedButton.icon(
                      onPressed: _startable == null ? null : () => unawaited(_startOver()),
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Se fra start'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => unawaited(_openArchive()),
                      icon: const Icon(Icons.history, size: 18),
                      label: const Text('TV-arkiv'),
                    ),
                  ],
                  if (_session.canMultiview)
                    OutlinedButton.icon(
                      onPressed: () => unawaited(_openMultiview()),
                      icon: const Icon(Icons.grid_view_outlined, size: 18),
                      label: const Text('Multiview'),
                    ),
                ],
              ),
            ),
          if (wide && cur != null && cur.description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Text(
                  cur.description,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _ink2, fontSize: 14, height: 1.4),
                ),
              ),
            ),
          if (meta.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                meta,
                maxLines: wide ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, letterSpacing: 0.2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _side({bool overlay = false}) {
    final page = widget.page;
    return Focus(
      focusNode: _sideFocus,
      child: ChannelSideList(
        key: _sideKey,
        session: _session,
        title: page.fromFavorites ? 'Alle kanaler' : page.listTitle,
        channels: page.fromFavorites ? _session.channels : page.channels,
        tab: _tab,
        onTab: (t) => setState(() => _tab = t),
        currentId: _channel.id,
        onPlay: _switchTo,
        onStar: (ch) => _toggleFav(ch, named: true),
        searchFocus: _searchFocus,
        onClose: overlay ? _toggleSide : null,
      ),
    );
  }
}
