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

  void _open(VodItem item) {
    unawaited(Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VodDetailPage(session: s, kind: widget.kind, item: item)),
    ));
  }

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
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
          onTap: () => _open(it),
        );
      },
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
