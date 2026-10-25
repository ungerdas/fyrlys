import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../core/models.dart';
import '../core/names.dart';
import '../core/session.dart';
import '../core/source.dart';
import '../platform.dart';

/// Spilleren. mpv (via media_kit) spiller strømmen direkte, med kanalbytte, lydspor, undertekster og fullskjerm.
/// Brytes strømmen, eller står bildet fast, prøver den på nytt inntil tre ganger i minuttet.
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.session, required this.channels, required this.index});

  final Session session;
  final List<Channel> channels;
  final int index;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  final Player _player = Player();
  late final VideoController _video = VideoController(_player);
  final FocusNode _focus = FocusNode(debugLabel: 'spiller');
  final List<StreamSubscription<Object?>> _subs = [];
  final List<DateTime> _retries = [];

  late int _index = widget.index;
  Channel? _opened;
  int _seq = 0;
  PlayTarget? _target;
  int _url = 0;
  bool _started = false;
  bool _buffering = true;
  bool _playing = false;
  bool _userPaused = false;
  bool _muted = false;
  bool _fullscreen = false;
  bool _controls = true;
  String? _status;
  BusyException? _busy;
  List<EpgEntry> _epg = const [];
  Timer? _hideTimer;
  Timer? _epgTimer;
  Timer? _watchdog;
  Duration _lastPos = Duration.zero;
  DateTime _lastMove = DateTime.now();

  Channel get _channel => widget.channels[_index];
  TvSource? get _source => widget.session.source;

  @override
  void initState() {
    super.initState();
    _subs
      ..add(_player.stream.playing.listen((v) => _set(() => _playing = v)))
      ..add(_player.stream.buffering.listen((v) => _set(() => _buffering = v)))
      ..add(_player.stream.position.listen((p) {
        if (!_started && p > Duration.zero) {
          _set(() {
            _started = true;
            _status = null;
          });
        }
      }))
      ..add(_player.stream.error.listen(_onError))
      ..add(_player.stream.completed.listen((done) {
        if (done && _started) _ended('sendingen stoppet');
      }));
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    if (!isDesktop) unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    unawaited(_start());
    _wake();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _hideTimer?.cancel();
    _epgTimer?.cancel();
    _watchdog?.cancel();
    final ch = _opened;
    final src = _source;
    if (ch != null && src != null) unawaited(src.close(ch));
    unawaited(_player.dispose());
    _focus.dispose();
    if (_fullscreen) unawaited(windowManager.setFullScreen(false));
    if (!isDesktop) unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  Future<void> _start() async {
    // Direktesending over nett: koble til igjen ved korte brudd, og ikke vent evig på en strøm som er død.
    // setProperty finnes bare på libmpv-spilleren (NativePlayer), derav dynamic.
    final dynamic platform = _player.platform;
    try {
      await platform.setProperty('network-timeout', '20');
      await platform.setProperty(
        'stream-lavf-o',
        'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5',
      );
    } on Object {
      // en spiller uten disse innstillingene spiller likevel
    }
    await _open();
  }

  Future<void> _open({bool takeOver = false}) async {
    final src = _source;
    if (src == null) return;
    final my = ++_seq;
    final ch = _channel;
    final prev = _opened;
    _opened = ch;
    if (prev != null && prev.id != ch.id) unawaited(src.close(prev));
    widget.session.addRecent(ch);
    _loadEpg(ch);
    _set(() {
      _status = null;
      _busy = null;
      _started = false;
      _buffering = true;
      _userPaused = false;
    });
    _lastPos = Duration.zero;
    _lastMove = DateTime.now();
    try {
      final t = await src.open(ch, takeOver: takeOver);
      if (my != _seq || !mounted) return;
      _target = t;
      _url = 0;
      await _player.open(Media(t.urls.first, httpHeaders: src.httpHeaders));
    } on BusyException catch (e) {
      if (my != _seq || !mounted) return;
      await _player.stop();
      _set(() {
        _busy = e;
        _buffering = false;
      });
    } on SourceException catch (e) {
      if (my != _seq || !mounted) return;
      await _player.stop();
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
    unawaited(_player.open(Media(t.urls[_url], httpHeaders: _source?.httpHeaders ?? const {})));
    return true;
  }

  void _onError(String message) {
    debugPrint('mpv: $message');
    if (!mounted || _started || _busy != null || _status != null || _target == null) return;
    if (_nextUrl()) return;
    // Siste adresse: mpv kan fortsatt komme seg, så vent litt før feilen vises.
    final my = _seq;
    Timer(const Duration(seconds: 8), () {
      if (!mounted || my != _seq || _started || _status != null || _busy != null) return;
      unawaited(_player.stop());
      _set(() {
        _status = 'Kanalen kunne ikke spilles ($message).';
        _buffering = false;
      });
    });
  }

  /// Strømmen stoppet etter at den hadde startet. Åpne kanalen på nytt via kilden (så «alle tilkoblinger
  /// i bruk» vises om noen har tatt over), inntil tre ganger i minuttet.
  void _ended(String why) {
    final now = DateTime.now();
    _retries.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (_retries.length >= 3) {
      unawaited(_player.stop());
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

  /// Vakt: står bildet fast uten at mpv sier fra, prøves det på nytt.
  void _check() {
    if (!mounted || _status != null || _busy != null || _target == null) return;
    final now = DateTime.now();
    final pos = _player.state.position;
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
        unawaited(_player.stop());
        _set(() {
          _status = 'Fikk ikke bilde fra kanalen.';
          _buffering = false;
        });
      }
    }
  }

  void _loadEpg(Channel ch) {
    _epgTimer?.cancel();
    _set(() => _epg = const []);
    Future<void> load() async {
      final list = await widget.session.epg(ch.id);
      if (mounted && _opened?.id == ch.id) setState(() => _epg = list);
    }

    unawaited(load());
    _epgTimer = Timer.periodic(const Duration(minutes: 1), (_) => unawaited(load()));
  }

  void _wake() {
    _hideTimer?.cancel();
    if (!_controls) _set(() => _controls = true);
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (_playing && _status == null && _busy == null) _set(() => _controls = false);
    });
  }

  void _togglePlay() {
    _userPaused = _playing;
    unawaited(_player.playOrPause());
    _wake();
  }

  void _toggleMute() {
    _muted = !_muted;
    unawaited(_player.setVolume(_muted ? 0 : 100));
    _set(() {});
  }

  Future<void> _toggleFullscreen() async {
    if (!isDesktop) return;
    final next = !_fullscreen;
    await windowManager.setFullScreen(next);
    _set(() => _fullscreen = next);
  }

  void _zap(int step) {
    final n = widget.channels.length;
    if (n < 2) return;
    _retries.clear();
    _set(() => _index = (_index + step) % n);
    unawaited(_open());
    _wake();
  }

  void _retry({bool takeOver = false}) {
    _retries.clear();
    unawaited(_open(takeOver: takeOver));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    _wake();
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.channelUp) {
      _zap(-1);
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.pageDown ||
        key == LogicalKeyboardKey.channelDown) {
      _zap(1);
    } else if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.keyK ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      _togglePlay();
    } else if (key == LogicalKeyboardKey.keyF) {
      unawaited(_toggleFullscreen());
    } else if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (key == LogicalKeyboardKey.escape) {
      if (_fullscreen) {
        unawaited(_toggleFullscreen());
      } else {
        unawaited(Navigator.of(context).maybePop());
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  static String _trackName(String? title, String? language, String id) {
    final parts = [title, language].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    return parts.isEmpty ? 'Spor $id' : parts.join(' · ');
  }

  Widget _tracksButton() {
    return PopupMenuButton<Object>(
      tooltip: 'Lydspor og undertekster',
      icon: const Icon(Icons.subtitles_outlined, color: Colors.white),
      onOpened: () => _hideTimer?.cancel(),
      onSelected: (value) {
        if (value is AudioTrack) unawaited(_player.setAudioTrack(value));
        if (value is SubtitleTrack) unawaited(_player.setSubtitleTrack(value));
        _wake();
      },
      itemBuilder: (context) {
        final tracks = _player.state.tracks;
        final current = _player.state.track;
        final audio = [for (final t in tracks.audio) if (t.id != 'auto' && t.id != 'no') t];
        final subtitles = [for (final t in tracks.subtitle) if (t.id != 'auto' && t.id != 'no') t];
        return <PopupMenuEntry<Object>>[
          const PopupMenuItem<Object>(enabled: false, child: Text('Lydspor')),
          if (audio.isEmpty) const PopupMenuItem<Object>(enabled: false, child: Text('Bare ett')),
          for (final t in audio)
            CheckedPopupMenuItem<Object>(
              value: t,
              checked: current.audio.id == t.id,
              child: Text(_trackName(t.title, t.language, t.id)),
            ),
          const PopupMenuDivider(),
          const PopupMenuItem<Object>(enabled: false, child: Text('Undertekster')),
          CheckedPopupMenuItem<Object>(
            value: SubtitleTrack.no(),
            checked: current.subtitle.id == 'no',
            child: const Text('Av'),
          ),
          for (final t in subtitles)
            CheckedPopupMenuItem<Object>(
              value: t,
              checked: current.subtitle.id == t.id,
              child: Text(_trackName(t.title, t.language, t.id)),
            ),
        ];
      },
    );
  }

  Widget _card({required String text, required String action, required VoidCallback onPressed}) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 460),
      margin: const EdgeInsets.all(24),
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
    );
  }

  Widget _bars(Channel ch, NameParts parts, EpgEntry? cur, EpgEntry? next) {
    final dim = Colors.white.withValues(alpha: 0.72);
    const shade = Color(0xD9000000);
    const clear = Color(0x00000000);
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [shade, clear]),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 36),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconButton(
                      tooltip: 'Tilbake',
                      color: Colors.white,
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => unawaited(Navigator.of(context).maybePop()),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text.rich(
                            TextSpan(children: [
                              if (ch.number != null)
                                TextSpan(text: '${ch.number}  ', style: TextStyle(color: dim, fontWeight: FontWeight.w600)),
                              if (parts.time.isNotEmpty)
                                TextSpan(
                                  text: '${parts.time}  ',
                                  style: const TextStyle(color: Color(0xFFF2B544), fontWeight: FontWeight.w700),
                                ),
                              TextSpan(text: parts.main),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                          ),
                          if (parts.sub.isNotEmpty)
                            Text(parts.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: dim)),
                          if (cur != null)
                            Text(
                              '${cur.title}  ${hhmm(cur.start)}–${hhmm(cur.stop)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white),
                            ),
                          if (next != null)
                            Text(
                              'Deretter ${hhmm(next.start)}: ${next.title}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: dim),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [shade, clear]),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 36, 12, 12),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: _playing ? 'Pause (mellomrom)' : 'Spill av (mellomrom)',
                      color: Colors.white,
                      iconSize: 32,
                      icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                      onPressed: _togglePlay,
                    ),
                    IconButton(
                      tooltip: 'Forrige kanal (↑)',
                      color: Colors.white,
                      icon: const Icon(Icons.keyboard_arrow_up),
                      onPressed: () => _zap(-1),
                    ),
                    IconButton(
                      tooltip: 'Neste kanal (↓)',
                      color: Colors.white,
                      icon: const Icon(Icons.keyboard_arrow_down),
                      onPressed: () => _zap(1),
                    ),
                    const SizedBox(width: 12),
                    if (cur != null)
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: cur.progressAt(DateTime.now()),
                            minHeight: 4,
                            color: const Color(0xFFF2B544),
                            backgroundColor: Colors.white24,
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: _muted ? 'Lyd på (M)' : 'Lyd av (M)',
                      color: Colors.white,
                      icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
                      onPressed: _toggleMute,
                    ),
                    _tracksButton(),
                    if (isDesktop)
                      IconButton(
                        tooltip: _fullscreen ? 'Avslutt fullskjerm (F)' : 'Fullskjerm (F)',
                        color: Colors.white,
                        icon: Icon(_fullscreen ? Icons.fullscreen_exit : Icons.fullscreen),
                        onPressed: () => unawaited(_toggleFullscreen()),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ch = _channel;
    final parts = nameParts(ch.name);
    final nn = nowAndNext(_epg, DateTime.now());
    final busy = _busy;
    final status = _status;
    final showBars = _controls || busy != null || status != null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          cursor: showBars ? SystemMouseCursors.basic : SystemMouseCursors.none,
          onHover: (_) => _wake(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_controls) {
                _hideTimer?.cancel();
                _set(() => _controls = false);
              } else {
                _wake();
              }
            },
            onDoubleTap: isDesktop ? () => unawaited(_toggleFullscreen()) : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Video(controller: _video, controls: NoVideoControls),
                if (_buffering && busy == null && status == null) const Center(child: CircularProgressIndicator()),
                IgnorePointer(
                  ignoring: !showBars,
                  child: AnimatedOpacity(
                    opacity: showBars ? 1 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: _bars(ch, parts, nn.now, nn.next),
                  ),
                ),
                if (busy != null)
                  Center(
                    child: _card(
                      text: '${busy.message}\nNår noen lukker spilleren, blir tilkoblingen ledig.',
                      action: busy.busy.length == 1 ? 'Stopp ${busy.busy.first} og se her' : 'Ta over en av tilkoblingene',
                      onPressed: () => _retry(takeOver: true),
                    ),
                  ),
                if (status != null && busy == null)
                  Center(child: _card(text: status, action: 'Prøv igjen', onPressed: _retry)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
