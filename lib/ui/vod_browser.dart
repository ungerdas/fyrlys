import 'dart:async';

import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/source.dart';
import '../core/vod.dart';
import 'vod_detail_page.dart';

/// Filmer eller serier: plakatene i et rutenett, med kategori, sortering og søket i toppen av siden.
/// Lista hentes en side om gangen, og flere hentes når du nærmer deg slutten.
class VodBrowser extends StatefulWidget {
  const VodBrowser({super.key, required this.session, required this.kind, required this.query});

  final Session session;
  final VodKind kind;

  /// søket i toppen av siden
  final String query;

  @override
  State<VodBrowser> createState() => _VodBrowserState();
}

class _VodBrowserState extends State<VodBrowser> {
  VodCatalog? _catalog;
  String? _error;
  String _category = '';
  VodSort _sort = VodSort.provider;
  final List<VodItem> _items = [];
  int _total = 0;
  bool _loading = false;
  bool _loadedOnce = false;
  bool _morePending = false;
  int _seq = 0;
  Timer? _debounce;

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCatalog());
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(VodBrowser old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 350), () => unawaited(_reload()));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadCatalog({bool force = false}) async {
    final src = s.source;
    if (src == null) return;
    try {
      final c = await src.vodCatalog(widget.kind, force: force);
      if (mounted) setState(() => _catalog = c);
    } on SourceException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _reload() async {
    _seq++;
    setState(() {
      _items.clear();
      _total = 0;
      _loadedOnce = false;
      _error = null;
      _loading = false;
    });
    await _more();
  }

  Future<void> _more() async {
    final src = s.source;
    if (src == null || _loading || (_loadedOnce && _items.length >= _total)) return;
    final my = _seq;
    setState(() => _loading = true);
    try {
      final page = await src.vodPage(
        widget.kind,
        category: _category,
        query: widget.query,
        sort: _sort,
        start: _items.length,
      );
      if (!mounted || my != _seq) return;
      setState(() {
        _items.addAll(page.items);
        _total = page.total;
        _loadedOnce = true;
        _loading = false;
      });
    } on SourceException catch (e) {
      if (!mounted || my != _seq) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// Kalles mens rutenettet bygges: hentingen startes etter at bildet er tegnet.
  void _maybeMore() {
    if (_morePending || _loading || _items.length >= _total) return;
    _morePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _morePending = false;
      if (mounted) unawaited(_more());
    });
  }

  Future<void> _open(VodItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VodDetailPage(session: s, kind: widget.kind, item: item)),
    );
    // «Fortsett å se» kan ha endret seg
    if (mounted) setState(() {});
  }

  Future<void> _continue(ContinueItem c) async {
    await playContinue(context, s, c);
    if (mounted) setState(() {});
  }

  /// Det du har begynt på (filmer som ikke er sett ferdig; serier med episoden du er på eller den neste).
  List<ContinueItem> get _continueItems => [
        for (final c in s.continueItems)
          if (c.kind == widget.kind && (c.kind == VodKind.series || s.resumeAt(c.key) != null)) c,
      ].take(20).toList();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tools(),
        Expanded(child: _content(scheme)),
      ],
    );
  }

  Widget _tools() {
    final scheme = Theme.of(context).colorScheme;
    final c = _catalog;
    final count = !_loadedOnce
        ? ''
        : _total > _items.length
            ? 'Viser ${_items.length} av $_total'
            : '$_total';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Flexible(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _category,
              items: [
                DropdownMenuItem(value: '', child: Text('Alle kategorier${c == null ? '' : ' (${c.total})'}')),
                for (final cat in c?.categories ?? const <VodCategory>[])
                  DropdownMenuItem(value: cat.id, child: Text('${cat.name} (${cat.count})', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                setState(() => _category = v ?? '');
                unawaited(_reload());
              },
            ),
          ),
          const SizedBox(width: 16),
          DropdownButton<VodSort>(
            value: _sort,
            items: [for (final o in VodSort.values) DropdownMenuItem(value: o, child: Text(o.title))],
            onChanged: (v) {
              setState(() => _sort = v ?? VodSort.provider);
              unawaited(_reload());
            },
          ),
          const SizedBox(width: 16),
          Text(count, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _content(ColorScheme scheme) {
    final error = _error;
    if (error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () {
                  unawaited(_loadCatalog(force: true));
                  unawaited(_reload());
                },
                child: const Text('Prøv igjen'),
              ),
            ],
          ),
        ),
      );
    }
    if (!_loadedOnce) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Henter ${widget.kind.title.toLowerCase()} … Første gang kan det ta litt tid.'),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(widget.query.isNotEmpty ? 'Fant ingenting.' : 'Ingenting her.',
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    final continues = widget.query.isEmpty && _category.isEmpty ? _continueItems : const <ContinueItem>[];
    return CustomScrollView(
      slivers: [
        if (continues.isNotEmpty) ...[
          const SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 10, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Text('Fortsett å se', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: continues.length,
                separatorBuilder: (context, i) => const SizedBox(width: 12),
                itemBuilder: (context, i) => ContinueCard(
                  key: ValueKey(continues[i].key),
                  session: s,
                  item: continues[i],
                  onTap: () => unawaited(_continue(continues[i])),
                  onRemove: () => setState(() => s.removeContinue(continues[i].key)),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Text('Alle ${widget.kind.title.toLowerCase()}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 180,
              mainAxisSpacing: 16,
              crossAxisSpacing: 14,
              childAspectRatio: 0.5,
            ),
            itemCount: _items.length,
            itemBuilder: (context, i) {
              if (i >= _items.length - 30) _maybeMore();
              final it = _items[i];
              return PosterCard(
                key: ValueKey('${it.id}#$i'),
                item: it,
                imageUrl: s.source?.logoUrl(it.icon),
                onTap: () => unawaited(_open(it)),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Plakat med navn, år og vurdering. Markert når den har fokus (fjernkontroll og tastatur).
class PosterCard extends StatefulWidget {
  const PosterCard({super.key, required this.item, required this.imageUrl, required this.onTap});

  final VodItem item;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final it = widget.item;
    final sub = [it.year ?? '', ratingText(it.rating)].where((t) => t.isNotEmpty).join('  ');
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (f) => setState(() => _focused = f),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _focused ? scheme.tertiary : Colors.transparent, width: 3),
                ),
                child: Poster(url: widget.imageUrl, title: it.name, showTitle: false),
              ),
              const SizedBox(height: 6),
              Text(
                it.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.25),
              ),
              if (sub.isNotEmpty)
                Text(sub, maxLines: 1, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Et kort i «Fortsett å se»: plakat, navn, episoden og hvor mye som er igjen, med en strek for hvor langt du er.
class ContinueCard extends StatefulWidget {
  const ContinueCard({super.key, required this.session, required this.item, required this.onTap, required this.onRemove});

  final Session session;
  final ContinueItem item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<ContinueCard> createState() => _ContinueCardState();
}

class _ContinueCardState extends State<ContinueCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = widget.session;
    final c = widget.item;
    final state = s.resumeState(c.resumeKey);
    final seen = s.watched(c.resumeKey);
    final String status;
    if (state != null) {
      final left = state.length - state.position;
      status = left.inMinutes >= 1 ? '${left.inMinutes} min igjen' : 'Snart ferdig';
    } else if (seen >= 0.95 || seen == 0) {
      // en serie der forrige episode er sett: denne er den neste
      status = c.kind == VodKind.series ? 'Neste episode' : '';
    } else {
      status = '';
    }
    final lines = [
      if (c.kind == VodKind.series && c.subtitle.isNotEmpty) c.subtitle,
      if (status.isNotEmpty) status,
    ];
    return SizedBox(
      width: 300,
      child: Material(
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _focused ? scheme.tertiary : scheme.outline, width: _focused ? 2 : 1),
        ),
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 74,
                child: Poster(url: s.source?.logoUrl(c.icon), title: c.title, radius: 0, showTitle: false),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(c.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                      for (final l in lines)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(l,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                        ),
                      if (seen > 0 && seen < 0.95)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(value: seen, minHeight: 3, backgroundColor: scheme.outline),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  tooltip: 'Fjern fra «Fortsett å se»',
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                  onPressed: widget.onRemove,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
