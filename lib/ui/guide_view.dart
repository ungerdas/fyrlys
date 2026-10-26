import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/names.dart';
import '../core/session.dart';
import '../theme.dart';
import 'channel_card.dart';

/// Hvor mange timer guiden viser, og hvor mange programmer som hentes per kanal (som på nettsiden).
const guideHours = 6;
const guideEpgLimit = 14;

const _rowHeight = 66.0;
const _headHeight = 42.0;

/// Starten på guiden: halvtimen før den halvtimen vi er i (22:44 → 22:00).
DateTime guideStart(DateTime now) =>
    DateTime(now.year, now.month, now.day, now.hour, now.minute < 30 ? 0 : 30).subtract(const Duration(minutes: 30));

/// Spiller av en kanal fra guiden: lista den står i, hvor i lista, navnet på lista og om det er favorittene.
typedef GuidePlay = void Function(List<Channel> channels, int index, String title, bool fromFavorites);

/// TV-guiden: kanalene nedover, de neste timene bortover, med en strek for «nå». Kanalnavnene står fast til
/// venstre og følger med når lista rulles. Som på nettsiden.
class GuideView extends StatefulWidget {
  const GuideView({super.key, required this.session, required this.query, required this.onPlay});

  final Session session;

  /// søket i toppen av siden (kanalnavn)
  final String query;
  final GuidePlay onPlay;

  @override
  State<GuideView> createState() => _GuideViewState();
}

class _GuideViewState extends State<GuideView> {
  final _channelScroll = ScrollController();
  final _rowScroll = ScrollController();
  final _timeScroll = ScrollController();
  bool _syncing = false;
  bool _placed = false;
  Timer? _tick;
  DateTime _now = DateTime.now();
  late DateTime _t0 = guideStart(_now);
  double _ppm = 5;
  late String _filter = _initialFilter();

  Session get s => widget.session;

  String _initialFilter() {
    final saved = s.guideCategory;
    if (saved != null) return saved;
    if (s.favorites.isNotEmpty) return 'fav';
    return s.favoriteCategories.isNotEmpty ? s.favoriteCategories.first : 'all';
  }

  @override
  void initState() {
    super.initState();
    _channelScroll.addListener(() => _sync(_channelScroll, _rowScroll));
    _rowScroll.addListener(() => _sync(_rowScroll, _channelScroll));
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _onTick());
  }

  @override
  void dispose() {
    _tick?.cancel();
    _channelScroll.dispose();
    _rowScroll.dispose();
    _timeScroll.dispose();
    super.dispose();
  }

  /// Kanalnavnene og programmene er to lister som rulles sammen.
  void _sync(ScrollController from, ScrollController to) {
    if (_syncing || !from.hasClients || !to.hasClients) return;
    final target = from.offset.clamp(to.position.minScrollExtent, to.position.maxScrollExtent).toDouble();
    if ((to.offset - target).abs() < 0.5) return;
    _syncing = true;
    to.jumpTo(target);
    _syncing = false;
  }

  void _onTick() {
    if (!mounted) return;
    final now = DateTime.now();
    final t0 = guideStart(now);
    setState(() {
      if (t0 != _t0 && _timeScroll.hasClients) {
        // guiden flytter seg en halvtime fram, men det du ser på, blir stående
        final shift = t0.difference(_t0).inMinutes * _ppm;
        _timeScroll.jumpTo((_timeScroll.offset - shift).clamp(0.0, _timeScroll.position.maxScrollExtent).toDouble());
      }
      _t0 = t0;
      _now = now;
    });
  }

  double _x(DateTime t) => t.difference(_t0).inSeconds / 60 * _ppm;

  /// Rett før «nå», så du ser litt av det som har gått.
  void _toNow({bool animate = true}) {
    if (!_timeScroll.hasClients) return;
    final x = (_x(_now) - 90).clamp(0.0, _timeScroll.position.maxScrollExtent).toDouble();
    if (animate) {
      unawaited(_timeScroll.animateTo(x, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic));
    } else {
      _timeScroll.jumpTo(x);
    }
  }

  void _jumpToNow() {
    final now = DateTime.now();
    setState(() {
      _now = now;
      _t0 = guideStart(now);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _toNow());
  }

  void _choose(String filter) {
    setState(() => _filter = filter);
    s.saveGuideCategory(filter);
    for (final c in [_channelScroll, _rowScroll]) {
      if (c.hasClients) c.jumpTo(0);
    }
  }

  /// Kategorien som er valgt, om den fortsatt finnes.
  String get _validFilter {
    if (_filter == 'fav' || _filter == 'all') return _filter;
    return s.categories.any((c) => c.id == _filter) ? _filter : 'all';
  }

  String _title(String filter) => switch (filter) {
        'all' => 'Alle kanaler',
        'fav' => 'Favoritter',
        _ => s.categoryName(filter),
      };

  List<Channel> _channels(String filter) {
    final base = s.channelsIn(filter);
    final words = widget.query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return base;
    return [
      for (final c in base)
        if (words.every(c.name.toLowerCase().contains)) c,
    ];
  }

  void _play(List<Channel> list, int index, String filter) {
    final title = widget.query.isEmpty ? _title(filter) : 'Treff i ${_title(filter).toLowerCase()}';
    widget.onPlay(List.of(list), index, title, filter == 'fav');
  }

  void _info(List<Channel> list, int index, String filter, EpgEntry e) {
    final ch = list[index];
    final now = DateTime.now();
    final tomorrow = e.start.day != now.day && e.start.isAfter(now) ? 'I morgen ' : '';
    final when = '$tomorrow${hhmm(e.start)}–${hhmm(e.stop)}';
    unawaited(showDialog<void>(
      context: context,
      builder: (context) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: Text(e.title),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${nameParts(ch.name).main}  ·  $when', style: TextStyle(color: scheme.onSurfaceVariant)),
                  if (e.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(e.description, style: const TextStyle(height: 1.45)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Lukk')),
            FilledButton(
              autofocus: true,
              onPressed: () {
                Navigator.of(context).pop();
                _play(list, index, filter);
              },
              child: const Text('Se kanalen'),
            ),
          ],
        );
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final narrow = MediaQuery.sizeOf(context).width < 700;
    _ppm = narrow ? 4.0 : 5.0;
    final filter = _validFilter;
    final list = _channels(filter);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tools(filter),
        Expanded(child: _content(scheme, list, filter, narrow)),
      ],
    );
  }

  Widget _tools(String filter) {
    final pinned = [
      for (final id in s.favoriteCategories)
        for (final c in s.categories)
          if (c.id == id) c,
    ];
    final rest = [for (final c in s.categories) if (!s.isFavoriteCategory(c.id)) c];
    String label(Category c) {
      final n = s.categoryCounts[c.id] ?? 0;
      return n > 0 ? '${c.name} ($n)' : c.name;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: DropdownButton<String>(
                isExpanded: true,
                value: filter,
                items: [
                  DropdownMenuItem(value: 'fav', child: Text('★ Favorittkanaler (${s.favorites.length})')),
                  DropdownMenuItem(value: 'all', child: Text('Alle kanaler (${s.channels.length})')),
                  for (final c in pinned)
                    DropdownMenuItem(value: c.id, child: Text('☆ ${label(c)}', overflow: TextOverflow.ellipsis)),
                  for (final c in rest)
                    DropdownMenuItem(value: c.id, child: Text(label(c), overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) {
                  if (v != null) _choose(v);
                },
              ),
            ),
          ),
          const SizedBox(width: 16),
          OutlinedButton(onPressed: _jumpToNow, child: const Text('Til nå')),
        ],
      ),
    );
  }

  Widget _content(ColorScheme scheme, List<Channel> list, String filter, bool narrow) {
    final error = s.error;
    Widget message(String text, {bool isError = false}) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(text,
                textAlign: TextAlign.center, style: TextStyle(color: isError ? scheme.error : scheme.onSurfaceVariant)),
          ),
        );
    if (s.channels.isEmpty && error != null) return message(error, isError: true);
    if (s.channels.isEmpty && s.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Henter kanaler …')],
        ),
      );
    }
    if (list.isEmpty) {
      _placed = false;
      return message(widget.query.isNotEmpty
          ? 'Fant ingenting.'
          : filter == 'fav'
              ? 'Ingen favoritter ennå. Trykk ☆ på en kanal under TV, eller velg en kategori over.'
              : 'Ingen kanaler her.');
    }
    if (!_placed) {
      // første gang guiden vises: rett før «nå»
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_timeScroll.hasClients) return;
        _placed = true;
        _toNow(animate: false);
      });
    }
    return _grid(scheme, list, filter, narrow);
  }

  Widget _grid(ColorScheme scheme, List<Channel> list, String filter, bool narrow) {
    final line = BorderSide(color: scheme.outline);
    final channelWidth = narrow ? 112.0 : 210.0;
    final width = guideHours * 60 * _ppm;
    final nowX = _x(_now);
    final behavior = ScrollConfiguration.of(context).copyWith(
      scrollbars: false,
      // på PC kan guiden også dras med musa
      dragDevices: {...ScrollConfiguration.of(context).dragDevices, PointerDeviceKind.mouse},
    );
    final channels = ListView.builder(
      controller: _channelScroll,
      itemExtent: _rowHeight,
      itemCount: list.length,
      itemBuilder: (context, i) => _ChannelCell(
        key: ValueKey('$filter:${list[i].id}'),
        session: s,
        channel: list[i],
        narrow: narrow,
        onTap: () => _play(list, i, filter),
      ),
    );
    final rows = ListView.builder(
      controller: _rowScroll,
      itemExtent: _rowHeight,
      itemCount: list.length,
      itemBuilder: (context, i) => _GuideRow(
        key: ValueKey('$filter:${list[i].id}'),
        session: s,
        channel: list[i],
        t0: _t0,
        now: _now,
        ppm: _ppm,
        timeScroll: _timeScroll,
        onPlay: () => _play(list, i, filter),
        onInfo: (e) => _info(list, i, filter, e),
      ),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.fromBorderSide(line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ScrollConfiguration(
        behavior: behavior,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: channelWidth,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: _headHeight,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(border: Border(bottom: line, right: line)),
                    child: Text(
                      hhmm(_now),
                      style: const TextStyle(color: FyrlysColors.live, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                  Expanded(child: channels),
                ],
              ),
            ),
            Expanded(
              // loddrett rullefelt for programmene (lista ligger inne i den vannrette), og vannrett nederst
              child: Scrollbar(
                controller: _rowScroll,
                notificationPredicate: (n) => n.depth == 1 && n.metrics.axis == Axis.vertical,
                child: Scrollbar(
                  controller: _timeScroll,
                  child: SingleChildScrollView(
                    controller: _timeScroll,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: width,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(height: _headHeight, child: _timeHeader(scheme, line)),
                              Expanded(child: rows),
                            ],
                          ),
                          if (nowX >= 0 && nowX <= width)
                            Positioned(
                              left: nowX - 5,
                              top: _headHeight - 5,
                              bottom: 0,
                              width: 10,
                              child: const IgnorePointer(child: _NowLine()),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeHeader(ColorScheme scheme, BorderSide line) {
    final slot = 30 * _ppm;
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: line)),
      child: Stack(
        children: [
          for (var i = 0; i < guideHours * 2; i++)
            Positioned(
              left: i * slot,
              top: 0,
              bottom: 0,
              width: slot,
              child: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(border: Border(left: line)),
                child: Text(
                  hhmm(_t0.add(Duration(minutes: 30 * i))),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Den røde streken for «nå», med en prikk øverst.
class _NowLine extends StatelessWidget {
  const _NowLine();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(color: FyrlysColors.live, shape: BoxShape.circle),
        ),
        Expanded(child: Container(width: 2, color: FyrlysColors.live)),
      ],
    );
  }
}

/// Kanalen til venstre i guiden: logo og navn. Trykk for å se den.
class _ChannelCell extends StatelessWidget {
  const _ChannelCell({super.key, required this.session, required this.channel, required this.narrow, required this.onTap});

  final Session session;
  final Channel channel;
  final bool narrow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final line = BorderSide(color: scheme.outline);
    return Material(
      color: scheme.surface,
      child: InkWell(
        onTap: onTap,
        focusColor: scheme.tertiary.withValues(alpha: 0.22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(border: Border(bottom: line, right: line)),
          child: Row(
            children: [
              if (!narrow) ...[
                ChannelLogo(url: session.source?.logoUrl(channel.icon), name: channel.name, width: 52, height: 36),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  nameParts(channel.name).main,
                  maxLines: narrow ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Programmene for én kanal. Hentes når raden har vært framme litt (så rask rulling ikke spør om alt).
class _GuideRow extends StatefulWidget {
  const _GuideRow({
    super.key,
    required this.session,
    required this.channel,
    required this.t0,
    required this.now,
    required this.ppm,
    required this.timeScroll,
    required this.onPlay,
    required this.onInfo,
  });

  final Session session;
  final Channel channel;
  final DateTime t0;
  final DateTime now;
  final double ppm;
  final ScrollController timeScroll;
  final VoidCallback onPlay;
  final void Function(EpgEntry entry) onInfo;

  @override
  State<_GuideRow> createState() => _GuideRowState();
}

class _GuideRowState extends State<_GuideRow> {
  List<EpgEntry>? _list;
  Timer? _wait;
  bool _fetching = false;

  Channel get ch => widget.channel;

  /// Eventkanaler har kampen i navnet og sjelden EPG; der står det som står i navnet.
  String? get _fixedText {
    final p = nameParts(ch.name);
    if (p.sub.isNotEmpty) return p.sub;
    if (p.time.isNotEmpty) return 'Starter ${p.time}';
    if (!ch.hasEpg) return 'Ingen programinformasjon';
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_GuideRow old) {
    super.didUpdateWidget(old);
    // hvert halve minutt: nye programmer når de gamle er utgått av mellomlageret
    _load();
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  void _load() {
    if (_fixedText != null || _fetching || _wait != null) return;
    final cached = widget.session.epgCached(ch.id, limit: guideEpgLimit);
    if (cached != null) {
      _list = cached;
      return;
    }
    _wait = Timer(const Duration(milliseconds: 150), () async {
      _wait = null;
      _fetching = true;
      final list = await widget.session.epg(ch.id, limit: guideEpgLimit);
      _fetching = false;
      if (mounted) setState(() => _list = list);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fixed = _fixedText;
    final list = _list;
    final t0 = widget.t0;
    final t1 = t0.add(const Duration(hours: guideHours));
    Widget body;
    if (fixed != null) {
      body = _StickyText(text: fixed, timeScroll: widget.timeScroll);
    } else if (list == null) {
      body = const SizedBox.shrink();
    } else {
      final items = [for (final e in list) if (e.stop.isAfter(t0) && e.start.isBefore(t1)) e];
      body = items.isEmpty
          ? _StickyText(text: 'Ingen programinformasjon', timeScroll: widget.timeScroll)
          : Stack(
              children: [
                for (final e in items) _block(e, t0, t1),
              ],
            );
    }
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: scheme.outline))),
      child: body,
    );
  }

  Widget _block(EpgEntry e, DateTime t0, DateTime t1) {
    final a = e.start.isBefore(t0) ? t0 : e.start;
    final b = e.stop.isAfter(t1) ? t1 : e.stop;
    final ppm = widget.ppm;
    final left = a.difference(t0).inSeconds / 60 * ppm + 2;
    final width = math.max(4.0, b.difference(a).inSeconds / 60 * ppm - 4);
    final now = e.isOnAt(widget.now);
    return Positioned(
      left: left,
      top: 6,
      bottom: 6,
      width: width,
      child: _ProgramBlock(
        entry: e,
        left: left,
        width: width,
        now: now,
        past: !e.stop.isAfter(widget.now),
        timeScroll: widget.timeScroll,
        // det som går nå, spilles med en gang; ellers vises hva det er
        onTap: now ? widget.onPlay : () => widget.onInfo(e),
      ),
    );
  }
}

/// Tekst som blir stående ved venstre kant av det synlige når guiden rulles bortover.
class _StickyText extends StatelessWidget {
  const _StickyText({required this.text, required this.timeScroll});

  final String text;
  final ScrollController timeScroll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: timeScroll,
      builder: (context, child) => Padding(
        padding: EdgeInsets.only(left: (timeScroll.hasClients ? timeScroll.offset : 0) + 14),
        child: child,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
      ),
    );
  }
}

/// Ett program: tittel og tid. Det som går nå, er markert, og det som er ferdig, er dempet. Tittelen flytter
/// seg inn når programmet begynte før det du ser, så den ikke gjemmer seg bak kanalnavnene.
class _ProgramBlock extends StatefulWidget {
  const _ProgramBlock({
    required this.entry,
    required this.left,
    required this.width,
    required this.now,
    required this.past,
    required this.timeScroll,
    required this.onTap,
  });

  final EpgEntry entry;
  final double left;
  final double width;
  final bool now;
  final bool past;
  final ScrollController timeScroll;
  final VoidCallback onTap;

  @override
  State<_ProgramBlock> createState() => _ProgramBlockState();
}

class _ProgramBlockState extends State<_ProgramBlock> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final e = widget.entry;
    final tiny = widget.width < 72;
    final time = '${hhmm(e.start)}–${hhmm(e.stop)}';
    final bg = widget.now
        ? Color.alphaBlend(scheme.primary.withValues(alpha: 0.18), scheme.surface)
        : scheme.surfaceContainerHighest;
    final side = _focused
        ? BorderSide(color: scheme.tertiary, width: 2)
        : widget.now
            ? BorderSide(color: scheme.primary.withValues(alpha: 0.55))
            : BorderSide.none;
    final text = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          e.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
        if (!tiny)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(time,
                maxLines: 1, softWrap: false, overflow: TextOverflow.clip, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ),
      ],
    );
    Widget block = Material(
      color: bg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9), side: side),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (f) => setState(() => _focused = f),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: tiny ? 4 : 10),
          child: ListenableBuilder(
            listenable: widget.timeScroll,
            builder: (context, child) {
              final visible = widget.timeScroll.hasClients ? widget.timeScroll.offset : 0.0;
              final inset = (visible - widget.left).clamp(0.0, math.max(0.0, widget.width - 70)).toDouble();
              return Padding(padding: EdgeInsets.only(left: inset), child: child);
            },
            child: text,
          ),
        ),
      ),
    );
    if (widget.past) block = Opacity(opacity: 0.5, child: block);
    block = Tooltip(
      message: '${e.title}\n$time${e.description.isEmpty ? '' : '\n\n${e.description}'}',
      waitDuration: const Duration(milliseconds: 600),
      child: block,
    );
    return block;
  }
}
