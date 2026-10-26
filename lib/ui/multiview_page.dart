import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/failure.dart';
import '../core/models.dart';
import '../core/names.dart';
import '../core/session.dart';
import '../core/source.dart';
import '../l10n/tr.dart';
import '../theme.dart';
import 'channel_card.dart';
import 'channel_number.dart';
import 'playback.dart';
import 'window_effects.dart';

/// Spilleren er alltid mørk, som de andre.
final ThemeData _playerTheme = fyrlysTheme(Brightness.dark);

/// Så mange bilder på en gang.
const multiviewMax = 4;

/// Flere kanaler samtidig: ett bilde per tilkobling i abonnementene dine (to abonnementer med én tilkobling hver gir
/// to bilder), høyst fire. Hvert bilde har sin kanal fra sitt abonnement. Lyden kommer fra bildet som er valgt
/// (klikk), og et dobbeltklikk gjør det stort.
class MultiviewPage extends StatelessWidget {
  const MultiviewPage({super.key, required this.session, this.first, this.startFull = false, this.playback});

  final Session session;

  /// kanalen i det første bildet (fra innloggingen i bruk)
  final Channel? first;

  /// vinduet er alt i fullskjerm (åpnet fra TV-spilleren i fullskjerm)
  final bool startFull;

  /// testene bruker falske avspillere
  final Playback Function()? playback;

  @override
  Widget build(BuildContext context) => Theme(data: _playerTheme, child: _Multiview(page: this));
}

/// Ett bilde: abonnementet det bruker en tilkobling fra, kanalen og avspilleren.
class _Slot {
  _Slot(this.login, this.source, this.pb);

  final SavedLogin login;
  final TvSource source;
  final Playback pb;
  Channel? channel;
  PlayTarget? target;
  int url = 0;
  int seq = 0;
  bool started = false;
  bool buffering = false;
  String? error;
  List<EpgEntry> epg = const [];
  final retries = <DateTime>[];

  /// nye forsøk på å åpne kanalen før feilen vises
  int openTries = 0;
  final subs = <StreamSubscription<Object?>>[];
}

class _Multiview extends StatefulWidget {
  const _Multiview({required this.page});

  final MultiviewPage page;

  @override
  State<_Multiview> createState() => _MultiviewState();
}

class _MultiviewState extends State<_Multiview> {
  final FocusNode _focus = FocusNode(debugLabel: 'multiview');
  final List<_Slot> _slots = [];

  /// kildene denne siden har åpnet (de andre innloggingene), og lukker
  final List<TvSource> _own = [];
  bool _loading = true;
  String? _message;
  int _selected = 0;

  /// stort bilde: bare det valgte vises (de andre spiller videre uten lyd)
  bool _big = false;
  late bool _full = widget.page.startFull;
  bool _controls = true;
  Timer? _hideTimer;
  Timer? _epgTimer;
  late double _volume = _session.volume;
  late bool _muted = _session.muted;

  Session get _session => widget.page.session;

  @override
  void initState() {
    super.initState();
    unawaited(_setup());
    _epgTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      for (final s in _slots) {
        _loadEpg(s);
      }
    });
    _wake();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _epgTimer?.cancel();
    for (final s in _slots) {
      for (final sub in s.subs) {
        unawaited(sub.cancel());
      }
      unawaited(s.pb.dispose());
    }
    for (final src in _own) {
      src.dispose();
    }
    _focus.dispose();
    // åpnet fra TV-spilleren i fullskjerm: den fortsetter i fullskjerm
    if (_full && !widget.page.startFull) unawaited(WindowFullscreen.instance.set(false));
    super.dispose();
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  // ── abonnementene og bildene ──

  /// Ett bilde per tilkobling: innloggingen i bruk først, så de andre.
  Future<void> _setup() async {
    final s = _session;
    final active = s.activeLogin;
    final order = [...s.logins.where((l) => l.id == active), ...s.logins.where((l) => l.id != active)];
    for (final login in order) {
      if (_slots.length >= multiviewMax) break;
      final src = await s.sourceFor(login.id);
      if (src == null) continue;
      final own = !identical(src, s.source);
      if (!mounted) {
        if (own) src.dispose();
        return;
      }
      if (own) _own.add(src);
      var connections = 1;
      try {
        connections = (await src.account().timeout(const Duration(seconds: 10))).maxConnections;
      } on Object {
        // vet ikke: én
      }
      if (!mounted) return;
      for (var i = 0; i < math.max(1, connections) && _slots.length < multiviewMax; i++) {
        final slot = await _newSlot(login, src);
        if (!mounted) {
          _drop(slot);
          return;
        }
        _slots.add(slot);
      }
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (_slots.length < 2) _message = tr('Fant bare én tilkobling. Legg til et abonnement til i innstillingene.');
    });
    _applyVolumes();
    final first = widget.page.first;
    if (first != null && _slots.isNotEmpty && identical(_slots.first.source, s.source)) {
      unawaited(_play(_slots.first, first));
    }
  }

  Future<_Slot> _newSlot(SavedLogin login, TvSource src) async {
    final pb = (widget.page.playback ?? playbackFactory)();
    final slot = _Slot(login, src, pb);
    slot.subs
      ..add(pb.positionStream.listen((p) {
        if (!slot.started && p > Duration.zero) {
          _set(() {
            slot.started = true;
            slot.openTries = 0;
            slot.buffering = false;
            slot.error = null;
          });
        }
      }))
      ..add(pb.bufferingStream.listen((b) => _set(() => slot.buffering = b)))
      ..add(pb.errorStream.listen((e) => _onError(slot, e)))
      ..add(pb.completedStream.listen((done) {
        if (done && slot.started) _ended(slot);
      }));
    // uten det store bufferet for pause og spoling: det er fire av dem
    await pb.setup();
    await pb.setLanguages(_session.languages);
    await pb.setPicture(_session.picture);
    await pb.setVolume(0);
    return slot;
  }

  /// Et bilde som ikke ble tatt i bruk (siden ble lukket imens).
  void _drop(_Slot s) {
    for (final sub in s.subs) {
      unawaited(sub.cancel());
    }
    unawaited(s.pb.dispose());
  }

  /// [retry]: et nytt forsøk av seg selv (ellers begynner tellingen av forsøk på nytt)
  Future<void> _play(_Slot s, Channel ch, {bool retry = false}) async {
    if (!retry) s.openTries = 0;
    final my = ++s.seq;
    _set(() {
      s.channel = ch;
      s.error = null;
      s.started = false;
      s.buffering = true;
      s.target = null;
      s.epg = const [];
    });
    _loadEpg(s);
    try {
      final t = await s.source.open(ch);
      if (!mounted || my != s.seq) return;
      s.target = t;
      s.url = 0;
      await s.pb.open(t.urls.first, s.source.httpHeaders);
    } on SourceException catch (e) {
      if (!mounted || my != s.seq) return;
      await s.pb.stop();
      _set(() {
        s.error = e.message;
        s.buffering = false;
      });
    }
  }

  /// Før bildet har startet: neste adresse (HLS → MPEG-TS), ellers en beskjed i bildet.
  void _onError(_Slot s, String raw) {
    final message = s.source.redact(raw);
    debugPrint('mpv (multiview): $message');
    final t = s.target;
    if (!mounted || s.started || s.error != null || t == null) return;
    if (s.url + 1 < t.urls.length) {
      s.url++;
      unawaited(s.pb.open(t.urls[s.url], s.source.httpHeaders));
      return;
    }
    final my = s.seq;
    // rett etter en annen strøm (TV-spilleren) kan leverandøren ennå telle den: to nye forsøk før feilen vises
    final ch = s.channel;
    if (ch != null && s.openTries < 2) {
      s.openTries++;
      Timer(const Duration(seconds: 3), () {
        if (mounted && my == s.seq && !s.started) unawaited(_play(s, ch, retry: true));
      });
      return;
    }
    final url = t.urls[s.url];
    unawaited(() async {
      await s.pb.stop();
      final text = await explainFailure(s.source, url,
          fallback: tr('Kanalen kunne ikke spilles ({message}).', {'message': plainMessage(message)}));
      if (my != s.seq) return;
      _set(() {
        s.error = text;
        s.buffering = false;
      });
    }());
  }

  /// Strømmen stoppet: åpnes igjen, inntil tre ganger i minuttet.
  void _ended(_Slot s) {
    final ch = s.channel;
    if (ch == null) return;
    final now = DateTime.now();
    s.retries.removeWhere((t) => now.difference(t) > const Duration(minutes: 1));
    if (s.retries.length >= 3) {
      unawaited(s.pb.stop());
      _set(() {
        s.error = tr('Kanalen stoppet.');
        s.buffering = false;
      });
      return;
    }
    s.retries.add(now);
    final my = s.seq;
    Timer(const Duration(milliseconds: 1500), () {
      if (mounted && my == s.seq) unawaited(_play(s, ch, retry: true));
    });
  }

  void _loadEpg(_Slot s) {
    final ch = s.channel;
    if (ch == null || !ch.hasEpg) return;
    final my = s.seq;
    final list = identical(s.source, _session.source) ? _session.epg(ch.id) : s.source.epg(ch.id).then(cleanEpg);
    unawaited(list.then(
      (epg) => _set(() {
        if (my == s.seq) s.epg = epg;
      }),
      onError: (Object _) {},
    ));
  }

  // ── valg, lyd og visning ──

  /// Lyden kommer fra bildet som er valgt; de andre er stille.
  void _applyVolumes() {
    for (var i = 0; i < _slots.length; i++) {
      unawaited(_slots[i].pb.setVolume(i == _selected && !_muted ? _volume : 0));
    }
  }

  void _select(int i) {
    if (i < 0 || i >= _slots.length) return;
    setState(() => _selected = i);
    _applyVolumes();
    _wake();
  }

  void _toggleBig(int i) {
    _select(i);
    setState(() => _big = !_big);
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      if (!_muted && _volume == 0) _volume = 50;
    });
    _session.saveVolume(_volume, _muted);
    _applyVolumes();
  }

  void _onWheel(PointerSignalEvent event) {
    GestureBinding.instance.pointerSignalResolver.register(event, (e) {
      if (e is! PointerScrollEvent || e.scrollDelta.dy == 0) return;
      setState(() {
        _volume = (_volume + (e.scrollDelta.dy < 0 ? 5 : -5)).clamp(0, 100).toDouble();
        _muted = _volume == 0;
      });
      _session.saveVolume(_volume, _muted);
      _applyVolumes();
      _wake();
    });
  }

  void _toggleFull() {
    setState(() => _full = !_full);
    unawaited(WindowFullscreen.instance.set(_full));
    _wake();
  }

  void _close() {
    final nav = Navigator.of(context);
    if (nav.canPop()) nav.pop();
  }

  void _wake() {
    _hideTimer?.cancel();
    if (!_controls) _set(() => _controls = true);
    _hideTimer = Timer(const Duration(seconds: 3), () => _set(() => _controls = false));
  }

  /// Kanalen i et bilde: favorittene eller alle kanalene i abonnementet det bruker.
  Future<void> _pick(int i) async {
    if (i < 0 || i >= _slots.length) return;
    final s = _slots[i];
    _select(i);
    _hideTimer?.cancel();
    final active = identical(s.source, _session.source);
    final ch = await showDialog<Channel>(
      context: context,
      builder: (_) => _ChannelPicker(
        title: _session.logins.length > 1 ? tr('Velg kanal · {name}', {'name': s.login.name}) : tr('Velg kanal'),
        channels: active ? Future.value(_session.channels) : s.source.channels(),
        favorites: _session.favoritesOf(s.login.id),
        logoUrl: s.source.logoUrl,
      ),
    );
    if (!mounted) return;
    if (ch != null) unawaited(_play(s, ch));
    _focus.requestFocus();
    _wake();
  }

  static final _okKeys = {LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter, LogicalKeyboardKey.select};

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isMetaPressed || keyboard.isAltPressed) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final n = _slots.length;
    _wake();
    final digit = int.tryParse(digitOf(key) ?? '');
    if (key == LogicalKeyboardKey.escape) {
      if (_big) {
        setState(() => _big = false);
      } else if (_full) {
        _toggleFull();
      } else {
        _close();
      }
    } else if (n == 0) {
      return KeyEventResult.ignored;
    } else if (digit != null && digit >= 1 && digit <= n) {
      _select(digit - 1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _select((_selected + 1) % n);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _select((_selected - 1 + n) % n);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      if (_selected + 2 < n) _select(_selected + 2);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      if (_selected - 2 >= 0) _select(_selected - 2);
    } else if (_okKeys.contains(key)) {
      _toggleBig(_selected);
    } else if (key == LogicalKeyboardKey.keyC || key == LogicalKeyboardKey.contextMenu) {
      unawaited(_pick(_selected));
    } else if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (key == LogicalKeyboardKey.keyF) {
      _toggleFull();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_full && !_big,
      onPopInvokedWithResult: (didPop, _) {
        // ut: strømmene stopper med en gang, så tilkoblingene er ledige for TV-spilleren under
        if (didPop) {
          for (final s in _slots) {
            unawaited(s.pb.stop());
          }
          return;
        }
        if (_big) {
          setState(() => _big = false);
        } else if (_full) {
          _toggleFull();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Listener(
            onPointerSignal: _onWheel,
            child: MouseRegion(
              cursor: _controls ? MouseCursor.defer : SystemMouseCursors.none,
              onHover: (_) => _wake(),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_loading)
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(tr('Kobler til abonnementene …'), style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                    )
                  else
                    Padding(padding: EdgeInsets.only(top: _full ? 0 : 56), child: _grid()),
                  Positioned(left: 0, right: 0, top: 0, child: _topBar()),
                  if (_message != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 24,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(color: const Color(0xE60C1B29), borderRadius: BorderRadius.circular(12)),
                          child: Text(_message!, style: const TextStyle(color: Colors.white)),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// To bilder side om side (over hverandre i et høyt vindu), tre eller fire i et rutenett.
  Widget _grid() {
    final n = _slots.length;
    if (n == 0) return const SizedBox.shrink();
    if (_big || n == 1) return _tile(math.min(_selected, n - 1));
    const gap = 4.0;
    if (n == 2) {
      return LayoutBuilder(builder: (context, box) {
        final tall = box.maxHeight > box.maxWidth;
        final children = [
          Expanded(child: _tile(0)),
          const SizedBox(width: gap, height: gap),
          Expanded(child: _tile(1)),
        ];
        return tall ? Column(children: children) : Row(children: children);
      });
    }
    Widget row(int a) => Expanded(
          child: Row(
            children: [
              Expanded(child: _tile(a)),
              const SizedBox(width: gap),
              Expanded(child: a + 1 < n ? _tile(a + 1) : const ColoredBox(color: Colors.black)),
            ],
          ),
        );
    return Column(children: [row(0), const SizedBox(height: gap), row(2)]);
  }

  Widget _tile(int i) {
    final s = _slots[i];
    final scheme = Theme.of(context).colorScheme;
    final selected = i == _selected && _slots.length > 1;
    final ch = s.channel;
    final error = s.error;
    return KeyedSubtree(
      key: GlobalObjectKey(s),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(i),
        onDoubleTap: () => _toggleBig(i),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 3),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              const ColoredBox(color: Colors.black),
              if (ch != null) s.pb.view(),
              if (ch == null)
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_session.logins.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(s.login.name, style: const TextStyle(color: Colors.white70)),
                        ),
                      FilledButton.icon(
                        onPressed: () => unawaited(_pick(i)),
                        icon: const Icon(Icons.add),
                        label: Text(tr('Velg kanal')),
                      ),
                    ],
                  ),
                ),
              if (ch != null && s.buffering && error == null)
                const IgnorePointer(child: Center(child: CircularProgressIndicator())),
              if (ch != null && error != null)
                Center(
                  child: Container(
                    margin: const EdgeInsets.all(12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xE60C1B29), borderRadius: BorderRadius.circular(12)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          children: [
                            FilledButton(
                              onPressed: () {
                                s.retries.clear();
                                unawaited(_play(s, ch));
                              },
                              child: Text(tr('Prøv igjen')),
                            ),
                            TextButton(onPressed: () => unawaited(_pick(i)), child: Text(tr('Annen kanal'))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              if (ch != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ExcludeFocus(
                    excluding: !_controls,
                    child: IgnorePointer(
                      ignoring: !_controls,
                      child: AnimatedOpacity(
                        opacity: _controls ? 1 : 0,
                        duration: const Duration(milliseconds: 250),
                        child: _tileBar(i, s, ch),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Nederst i et bilde: lyd, kanal, programmet nå og abonnementet; bytt kanal og stort bilde.
  Widget _tileBar(int i, _Slot s, Channel ch) {
    final cur = nowAndNext(s.epg, DateTime.now()).now;
    final sound = i == _selected && !_muted;
    final details = [
      if (cur != null) '${cur.title} · ${hhmm(cur.start)}–${hhmm(cur.stop)}',
      if (_session.logins.length > 1) s.login.name,
    ].join(' · ');
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xDB000000), Color(0x00000000)],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 28, 4, 6),
        child: Row(
          children: [
            Icon(sound ? Icons.volume_up : Icons.volume_off, size: 18, color: sound ? Colors.white : Colors.white54),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    nameParts(ch.name).main,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  if (details.isNotEmpty)
                    Text(
                      details,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFB3C1CD), fontSize: 12),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: tr('Bytt kanal (C)'),
              color: Colors.white,
              icon: const Icon(Icons.list),
              onPressed: () => unawaited(_pick(i)),
            ),
            if (_slots.length > 1)
              IconButton(
                tooltip: _big ? tr('Alle bildene (Enter)') : tr('Stort bilde (Enter)'),
                color: Colors.white,
                icon: Icon(_big ? Icons.grid_view : Icons.open_in_full),
                onPressed: () => _toggleBig(i),
              ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    return ExcludeFocus(
      excluding: !_controls,
      child: IgnorePointer(
        ignoring: !_controls,
        child: AnimatedOpacity(
          opacity: _controls ? 1 : 0,
          duration: const Duration(milliseconds: 250),
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: _full ? const Color(0xA6000000) : Colors.black,
            child: Row(
              children: [
                IconButton(
                    tooltip: tr('Lukk (Esc)'), color: Colors.white, icon: const Icon(Icons.close), onPressed: _close),
                const SizedBox(width: 8),
                Text(tr('Multiview'),
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(width: 16),
                if (wide && _slots.length > 1)
                  Expanded(
                    child: Text(
                      tr('Klikk et bilde for lyden · dobbeltklikk for stort bilde · C bytter kanal'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                  )
                else
                  const Spacer(),
                IconButton(
                  tooltip: _muted ? tr('Lyd på (M)') : tr('Lyd av (M)'),
                  color: Colors.white,
                  icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
                  onPressed: _toggleMute,
                ),
                IconButton(
                  tooltip: _full ? tr('Avslutt fullskjerm (F)') : tr('Fullskjerm (F)'),
                  color: Colors.white,
                  icon: Icon(_full ? Icons.fullscreen_exit : Icons.fullscreen),
                  onPressed: _toggleFull,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Velg en kanal: favorittene (eller alle) i abonnementet, med søk.
class _ChannelPicker extends StatefulWidget {
  const _ChannelPicker({required this.title, required this.channels, required this.favorites, required this.logoUrl});

  final String title;
  final Future<List<Channel>> channels;
  final List<Channel> favorites;
  final String? Function(String? icon) logoUrl;

  @override
  State<_ChannelPicker> createState() => _ChannelPickerState();
}

class _ChannelPickerState extends State<_ChannelPicker> {
  String _query = '';
  late bool _fav = widget.favorites.isNotEmpty;

  List<Channel> _list(List<Channel> all) {
    final words = _query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return _fav ? widget.favorites : all;
    return [
      for (final c in all)
        if (words.every(c.name.toLowerCase().contains)) c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 460,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                  isDense: true, prefixIcon: const Icon(Icons.search), hintText: tr('Søk etter kanal')),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
            if (widget.favorites.isNotEmpty && _query.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: true, label: Text(tr('★ Favoritter'))),
                    ButtonSegment(value: false, label: Text(tr('Alle kanaler'))),
                  ],
                  selected: {_fav},
                  onSelectionChanged: (v) => setState(() => _fav = v.first),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<Channel>>(
                future: widget.channels,
                builder: (context, snap) {
                  if (snap.hasError) {
                    final e = snap.error;
                    return Center(
                      child: Text(e is SourceException ? e.message : tr('Fikk ikke hentet kanalene.'),
                          textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
                    );
                  }
                  final all = snap.data;
                  if (all == null) return const Center(child: CircularProgressIndicator());
                  final list = _list(all);
                  if (list.isEmpty) {
                    return Center(
                        child: Text(tr('Fant ingenting.'), style: TextStyle(color: scheme.onSurfaceVariant)));
                  }
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (context, i) {
                      final c = list[i];
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                        leading: ChannelLogo(url: widget.logoUrl(c.icon), name: c.name, width: 46, height: 32),
                        title: Text(nameParts(c.name).main, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: c.number == null ? null : Text(tr('Kanal {n}', {'n': c.number})),
                        onTap: () => Navigator.of(context).pop(c),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Avbryt')))],
    );
  }
}
