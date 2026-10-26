import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/names.dart';
import '../core/session.dart';
import '../core/vod.dart';
import '../platform.dart';
import '../theme.dart';
import 'language_dialog.dart';
import 'playback.dart';
import 'window_effects.dart';

export '../core/names.dart' show formatDuration;

/// Spilleren er alltid mørk, som på nettsiden.
final ThemeData _playerTheme = fyrlysTheme(Brightness.dark);

/// Noe å spille: en film eller en episode.
class VodPlayItem {
  const VodPlayItem({required this.key, required this.title, required this.url, this.subtitle = '', this.continueAs});

  /// for «fortsett der du slapp», f.eks. «film:123» eller «episode:456»
  final String key;
  final String title;
  final String subtitle;
  final String url;

  /// slik den står i «Fortsett å se» mens du ser den
  final ContinueItem? continueAs;
}


/// Spilleren for filmer og episoder: tidslinje med spoling, ±10 sekunder, neste og forrige episode, lydspor og
/// undertekster, volum og fullskjerm. Husker hvor du slapp, og går videre til neste episode når en er ferdig.
class VodPlayerPage extends StatelessWidget {
  const VodPlayerPage({
    super.key,
    required this.session,
    required this.items,
    this.index = 0,
    this.resume = true,
    this.playback,
  });

  final Session session;

  /// filmen, eller episodene i sesongen (så den kan gå videre til neste)
  final List<VodPlayItem> items;
  final int index;

  /// fortsett der du slapp (false: fra begynnelsen)
  final bool resume;

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

class _VodPlayerState extends State<_VodPlayer> with WidgetsBindingObserver {
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
  bool _full = false;
  double? _seekValue;
  bool _dragging = false;
  late double _volume = _session.volume;
  late bool _muted = _session.muted;
  PointerDeviceKind _pointer = isDesktop ? PointerDeviceKind.mouse : PointerDeviceKind.touch;
  String? _flash;
  Timer? _flashTimer;
  Timer? _hideTimer;
  Timer? _saveTimer;
  Timer? _nextTimer;

  Session get _session => widget.page.session;
  List<VodPlayItem> get _items => widget.page.items;
  VodPlayItem get _item => _items[_index];
  bool get _hasNext => _index + 1 < _items.length;
  bool get _hasPrev => _index > 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subs
      ..add(_pb.playingStream.listen((v) => _set(() => _playing = v)))
      ..add(_pb.bufferingStream.listen((v) => _set(() => _buffering = v)))
      ..add(_pb.durationStream.listen((d) => _set(() => _duration = d)))
      ..add(_pb.positionStream.listen(_onPosition))
      ..add(_pb.errorStream.listen(_onError))
      ..add(_pb.completedStream.listen((done) {
        if (done && _started) _onEnd();
      }));
    _saveTimer = Timer.periodic(const Duration(seconds: 10), (_) => _save());
    if (!isDesktop) unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
    unawaited(_start());
    _wake();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _save();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _flashTimer?.cancel();
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _nextTimer?.cancel();
    unawaited(_pb.dispose());
    _focus.dispose();
    if (isDesktop) {
      if (_full) unawaited(WindowFullscreen.instance.set(false));
    } else {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
    super.dispose();
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // telefon/TV: lagt bort → pause (og husk hvor du var)
    if (!isDesktop && state == AppLifecycleState.paused && _playing) {
      _save();
      unawaited(_pb.playOrPause());
    }
  }

  // ── avspilling ──

  Future<void> _start() async {
    await _pb.setup();
    await _pb.setLanguages(_session.languages);
    await _pb.setPicture(_session.picture);
    await _pb.setVolume(_muted ? 0 : _volume);
    await _open(resume: widget.page.resume);
  }

  Future<void> _open({bool resume = true}) async {
    final item = _item;
    final start = resume ? _session.resumeAt(item.key) : null;
    _set(() {
      _status = null;
      _started = false;
      _ending = false;
      _buffering = true;
      _position = start ?? Duration.zero;
      _duration = Duration.zero;
    });
    if (start != null) _showFlash('Fortsetter fra ${formatDuration(start)}');
    try {
      await _pb.open(item.url, _session.source?.httpHeaders ?? const {}, start: start);
    } on Object catch (e) {
      _set(() {
        _status = 'Kunne ikke spille av (${_session.source?.redact('$e') ?? e}).';
        _buffering = false;
      });
    }
  }

  void _onPosition(Duration p) {
    if (!_started && p > Duration.zero) _set(() => _started = true);
    // spolt tilbake etter slutten: ikke ferdig likevel (og ikke videre til neste episode)
    if (_ending && _duration > Duration.zero && p < _duration - const Duration(seconds: 10)) _ending = false;
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
    _set(() {
      _status = 'Kunne ikke spille av ($message).';
      _buffering = false;
    });
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
      _showFlash('Neste: ${_items[_index + 1].subtitle}');
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
    setState(() => _index = index);
    unawaited(_open());
    _wake();
  }

  void _togglePlay() {
    unawaited(_pb.playOrPause());
    _wake();
  }

  void _seekBy(int seconds) {
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

  void _wake({bool stay = false}) {
    _hideTimer?.cancel();
    if (!_controls) _set(() => _controls = true);
    if (stay) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (_playing && _status == null && !_dragging) _set(() => _controls = false);
    });
  }

  void _toggleFull() {
    if (!isDesktop) return;
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
      unawaited(_open());
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
    } else if (key == LogicalKeyboardKey.keyN || key == LogicalKeyboardKey.pageDown || key == LogicalKeyboardKey.mediaTrackNext) {
      if (_hasNext) _go(_index + 1);
    } else if (key == LogicalKeyboardKey.keyP || key == LogicalKeyboardKey.pageUp || key == LogicalKeyboardKey.mediaTrackPrevious) {
      if (_hasPrev) _go(_index - 1);
    } else if (key == LogicalKeyboardKey.escape) {
      if (_full) {
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
      canPop: !_full,
      onPopInvokedWithResult: (didPop, _) {
        // lagres med en gang du går ut, så siden du kommer tilbake til («Fortsett fra …») er oppdatert
        if (didPop) _save();
        if (!didPop && _full) _toggleFull();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Listener(
            onPointerDown: (e) => _pointer = e.kind,
            onPointerSignal: isDesktop ? _onWheel : null,
            child: MouseRegion(
              cursor: showBars ? MouseCursor.defer : SystemMouseCursors.none,
              onHover: (_) => _wake(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onTap,
                    onDoubleTap: isDesktop ? _toggleFull : null,
                    child: _pb.view(),
                  ),
                  if (_buffering && status == null) const IgnorePointer(child: Center(child: CircularProgressIndicator())),
                  if (flash != null)
                    Positioned(
                      top: 96,
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
                        child: Stack(
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
                  tooltip: 'Lukk (Esc)',
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
                                unawaited(_pb.seek(to));
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
                  _ctl(_playing ? Icons.pause : Icons.play_arrow, _playing ? 'Pause (mellomrom)' : 'Spill av (mellomrom)',
                      _togglePlay,
                      size: 30),
                  _ctl(Icons.replay_10, '10 sekunder tilbake (←)', () => _seekBy(-10)),
                  _ctl(Icons.forward_10, '10 sekunder fram (→)', () => _seekBy(10)),
                  if (_items.length > 1) ...[
                    _ctl(Icons.skip_previous, 'Forrige episode (P)', _hasPrev ? () => _go(_index - 1) : null),
                    _ctl(Icons.skip_next, 'Neste episode (N)', _hasNext ? () => _go(_index + 1) : null),
                  ],
                  const Spacer(),
                  _ctl(volumeIcon, _muted ? 'Lyd på (M)' : 'Lyd av (M)', _toggleMute),
                  if (isDesktop && !compact) _volumeSlider(volume),
                  _tracksButton(),
                  if (isDesktop)
                    _ctl(_full ? Icons.fullscreen_exit : Icons.fullscreen,
                        _full ? 'Avslutt fullskjerm (F)' : 'Fullskjerm (F)', _toggleFull),
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
        onClose: _wake,
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
              FilledButton(autofocus: true, onPressed: () => unawaited(_open()), child: const Text('Prøv igjen')),
            ],
          ),
        ),
      ),
    );
  }
}
