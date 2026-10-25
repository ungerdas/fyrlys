import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/names.dart';
import '../core/session.dart';
import 'channel_card.dart';

/// Hvilken liste kanallista i spilleren viser.
enum SideTab { list, fav }

/// Kanallista ved siden av spilleren, som på nettsiden: lista du kom fra og favorittene, med søk.
/// Kanalen som spilles er markert, og lista holder den synlig når du bytter kanal.
class ChannelSideList extends StatefulWidget {
  const ChannelSideList({
    super.key,
    required this.session,
    required this.title,
    required this.channels,
    required this.tab,
    required this.onTab,
    required this.currentId,
    required this.onPlay,
    required this.onStar,
    required this.searchFocus,
    this.onClose,
  });

  final Session session;

  /// navnet på lista du kom fra, f.eks. «Alle kanaler» eller en kategori
  final String title;
  final List<Channel> channels;
  final SideTab tab;
  final ValueChanged<SideTab> onTab;
  final String currentId;

  /// lista det ble valgt fra, og plassen i den (så ▲▼ fortsetter i samme liste)
  final void Function(List<Channel> list, int index) onPlay;
  final ValueChanged<Channel> onStar;
  final FocusNode searchFocus;

  /// vises som ✕ når lista ligger over bildet i fullskjerm
  final VoidCallback? onClose;

  @override
  State<ChannelSideList> createState() => ChannelSideListState();
}

class ChannelSideListState extends State<ChannelSideList> {
  static const rowHeight = 56.0;

  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _tabFocus = FocusNode(debugLabel: 'fanen');

  /// radene som er bygget nå, etter kanal-id (for å flytte fokus til kanalen som spilles)
  final Map<String, _SideRowState> _rows = {};
  String _query = '';
  Object? _matchKey;
  List<int>? _matches;

  List<Channel> get _list => widget.tab == SideTab.fav ? widget.session.favorites : widget.channels;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(center: true));
  }

  @override
  void didUpdateWidget(ChannelSideList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab) {
      _search.clear();
      _query = '';
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(center: true));
    } else if (oldWidget.currentId != widget.currentId) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal(center: false));
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    _tabFocus.dispose();
    super.dispose();
  }

  /// Plassene i lista som passer med søket (alle ordene), eller null uten søk.
  List<int>? _filtered(List<Channel> list) {
    if (_query.isEmpty) return null;
    final key = (list, _query);
    if (key != _matchKey) {
      final words = _query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
      _matchKey = key;
      _matches = [
        for (var i = 0; i < list.length; i++)
          if (words.every(list[i].name.toLowerCase().contains)) i,
      ];
    }
    return _matches;
  }

  int _currentRow(List<Channel> list, List<int>? matches) {
    if (matches == null) return list.indexWhere((c) => c.id == widget.currentId);
    return matches.indexWhere((i) => list[i].id == widget.currentId);
  }

  /// Viser kanalen som spilles: midt i lista, eller bare så vidt innenfor (center: false).
  void _reveal({required bool center}) {
    if (!mounted || !_scroll.hasClients) return;
    final list = _list;
    final row = _currentRow(list, _filtered(list));
    if (row < 0) return;
    final pos = _scroll.position;
    final top = row * rowHeight;
    final view = pos.viewportDimension;
    double? target;
    if (center) {
      target = top - (view - rowHeight) / 2;
    } else if (top < pos.pixels) {
      target = top;
    } else if (top + rowHeight > pos.pixels + view) {
      target = top + rowHeight - view;
    }
    if (target != null) _scroll.jumpTo(target.clamp(pos.minScrollExtent, pos.maxScrollExtent).toDouble());
  }

  /// Flytter fokus til kanalen som spilles (tastatur og fjernkontroll), eller til fanen hvis den ikke er i lista.
  void focusCurrent() {
    _reveal(center: false);
    void go() {
      if (!mounted) return;
      final row = _rows[widget.currentId];
      (row != null ? row.focusNode : _tabFocus).requestFocus();
    }

    if (_rows.containsKey(widget.currentId)) {
      go();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => go());
    WidgetsBinding.instance.scheduleFrame();
  }

  void _clearSearch() {
    _search.clear();
    setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = _list;
    final matches = _filtered(list);
    final count = matches?.length ?? list.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16, widget.onClose == null ? 14 : 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Kanaler',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: scheme.onSurface),
                ),
              ),
              if (widget.onClose != null)
                IconButton(
                  tooltip: 'Lukk kanallista (Esc)',
                  icon: const Icon(Icons.close),
                  color: scheme.onSurface,
                  onPressed: widget.onClose,
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: Row(
            children: [
              Expanded(child: _tabButton(SideTab.list, widget.title, focusNode: _tabFocus)),
              const SizedBox(width: 6),
              Expanded(child: _tabButton(SideTab.fav, '★ Favoritter')),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
          child: TextField(
            controller: _search,
            focusNode: widget.searchFocus,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Søk i lista',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(tooltip: 'Tøm søket', icon: const Icon(Icons.close, size: 18), onPressed: _clearSearch),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
        ),
        Expanded(
          child: count == 0
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Text(
                    _query.isNotEmpty
                        ? 'Fant ingenting.'
                        : widget.tab == SideTab.fav
                            ? 'Ingen favoritter ennå. Trykk ☆ på en kanal for å legge den til.'
                            : 'Ingen kanaler her.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  controller: _scroll,
                  itemExtent: rowHeight,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
                  itemCount: count,
                  itemBuilder: (context, row) {
                    final i = matches?[row] ?? row;
                    final ch = list[i];
                    return _SideRow(
                      key: ValueKey('${ch.id}#$i'),
                      owner: this,
                      session: widget.session,
                      channel: ch,
                      current: ch.id == widget.currentId,
                      onTap: () => widget.onPlay(list, i),
                      onStar: () => widget.onStar(ch),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _tabButton(SideTab tab, String label, {FocusNode? focusNode}) {
    final scheme = Theme.of(context).colorScheme;
    final on = widget.tab == tab;
    return Semantics(
      selected: on,
      button: true,
      child: Material(
        color: on ? scheme.onSurface : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: on ? scheme.onSurface : scheme.outline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          focusNode: focusNode,
          focusColor: scheme.tertiary.withValues(alpha: 0.3),
          onTap: () => widget.onTab(tab),
          child: SizedBox(
            height: 34,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                    color: on ? scheme.surfaceContainerLowest : const Color(0xFFB3C1CD),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// En kanal i lista: logo, navn, programmet som går nå (eller ligaen for eventkanaler), nummer og stjerne.
class _SideRow extends StatefulWidget {
  const _SideRow({
    super.key,
    required this.owner,
    required this.session,
    required this.channel,
    required this.current,
    required this.onTap,
    required this.onStar,
  });

  final ChannelSideListState owner;
  final Session session;
  final Channel channel;
  final bool current;
  final VoidCallback onTap;
  final VoidCallback onStar;

  @override
  State<_SideRow> createState() => _SideRowState();
}

class _SideRowState extends State<_SideRow> {
  final focusNode = FocusNode(debugLabel: 'kanal i lista');
  Future<List<EpgEntry>>? _epg;

  @override
  void initState() {
    super.initState();
    widget.owner._rows[widget.channel.id] = this;
    _load();
  }

  @override
  void didUpdateWidget(_SideRow old) {
    super.didUpdateWidget(old);
    if (old.channel.id != widget.channel.id) {
      if (widget.owner._rows[old.channel.id] == this) widget.owner._rows.remove(old.channel.id);
      widget.owner._rows[widget.channel.id] = this;
      _load();
    }
  }

  @override
  void dispose() {
    if (widget.owner._rows[widget.channel.id] == this) widget.owner._rows.remove(widget.channel.id);
    focusNode.dispose();
    super.dispose();
  }

  void _load() {
    final ch = widget.channel;
    // eventkanaler har kampen i navnet, og ofte ingen EPG
    _epg = ch.hasEpg && nameParts(ch.name).sub.isEmpty ? widget.session.epg(ch.id) : null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ch = widget.channel;
    final parts = nameParts(ch.name);
    final fav = widget.session.isFavorite(ch.id);
    final small = TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: widget.current ? scheme.surfaceContainerHighest : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          focusNode: focusNode,
          onTap: widget.onTap,
          hoverColor: scheme.surface,
          focusColor: scheme.tertiary.withValues(alpha: 0.22),
          child: Row(
            children: [
              SizedBox(
                width: 3,
                height: double.infinity,
                child: ColoredBox(color: widget.current ? scheme.primary : Colors.transparent),
              ),
              const SizedBox(width: 5),
              ChannelLogo(url: widget.session.source?.logoUrl(ch.icon), name: ch.name, width: 56, height: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        if (parts.time.isNotEmpty)
                          TextSpan(
                            text: '${parts.time}  ',
                            style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
                          ),
                        TextSpan(text: parts.main),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: scheme.onSurface),
                    ),
                    if (parts.sub.isNotEmpty)
                      Text(parts.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: small)
                    else if (_epg != null)
                      FutureBuilder<List<EpgEntry>>(
                        future: _epg,
                        builder: (context, snap) {
                          final cur = nowAndNext(snap.data ?? const [], DateTime.now()).now;
                          if (cur == null) return const SizedBox.shrink();
                          return Text(
                            '${hhmm(cur.start)} ${cur.title}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: small,
                          );
                        },
                      ),
                  ],
                ),
              ),
              if (ch.number != null)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Text(ch.number!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ),
              IconButton(
                tooltip: fav ? 'Fjern fra favoritter' : 'Legg til i favoritter',
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  fav ? Icons.star : Icons.star_border,
                  size: 20,
                  color: fav ? scheme.primary : scheme.onSurfaceVariant,
                ),
                onPressed: widget.onStar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
