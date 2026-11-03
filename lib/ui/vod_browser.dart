import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/source.dart';
import '../core/vod.dart';
import '../l10n/tr.dart';
import 'motion.dart';
import 'net_image.dart';
import 'vod_detail_page.dart';

/// Filmer eller serier. Oversikten har rader bortover: «Fortsett å se» med store bilder og hvor langt du har kommet,
/// favorittene, det som sist kom, og en rad for hver kategori. «Vis alle», en kategori fra knappen øverst eller søket
/// gir plakatene i et rutenett, en side om gangen.
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
  String? _catalogError;

  /// '' = oversikten (radene), 'alle' = alt i rutenettet, ellers en kategori
  String _view = '';
  VodSort _sort = VodSort.provider;

  // rutenettet: det som er hentet, og hvor mange det er i alt
  final List<VodItem> _items = [];
  int _total = 0;
  bool _loading = false;
  bool _loadedOnce = false;
  bool _morePending = false;
  String? _error;
  int _seq = 0;
  Timer? _debounce;

  Session get s => widget.session;

  bool get _grid => _view.isNotEmpty || widget.query.isNotEmpty;

  String get _gridCategory => _view == 'alle' ? '' : _view;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCatalog());
    if (_grid) unawaited(_reload());
  }

  @override
  void didUpdateWidget(VodBrowser old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      _debounce?.cancel();
      if (_grid) _debounce = Timer(const Duration(milliseconds: 350), () => unawaited(_reload()));
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
      if (mounted) {
        setState(() {
          _catalog = c;
          _catalogError = null;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _catalogError = e is SourceException ? e.message : tr('Uventet svar fra serveren'));
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
        category: _gridCategory,
        query: widget.query,
        sort: _sort,
        start: _items.length,
      );
      if (!mounted || my != _seq) return;
      setState(() {
        _items.addAll(page.items);
        // en tom side betyr at det ikke er mer, uansett hva totalen sa (ellers spør vi igjen og igjen)
        _total = page.items.isEmpty ? _items.length : page.total;
        _loadedOnce = true;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted || my != _seq) return;
      setState(() {
        _error = e is SourceException ? e.message : tr('Uventet svar fra serveren');
        _loading = false;
      });
    }
  }

  /// Kalles mens rutenettet bygges: hentingen startes etter at bildet er tegnet.
  void _maybeMore() {
    // etter en feil hentes det ikke mer av seg selv (da ville den spurt igjen for hver ombygging); se «Prøv igjen»
    if (_morePending || _loading || _error != null || _items.length >= _total) return;
    _morePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _morePending = false;
      if (mounted) unawaited(_more());
    });
  }

  /// Oversikten (''), alt ('alle') eller en kategori; [sort] for «Vis alle» på «Nylig lagt til».
  void _setView(String view, {VodSort? sort}) {
    setState(() {
      _view = view;
      if (sort != null) _sort = sort;
    });
    if (_grid) unawaited(_reload());
  }

  Future<void> _open(VodItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => VodDetailPage(session: s, kind: widget.kind, item: item)),
    );
    // «Fortsett å se» og favorittene kan ha endret seg
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

  String get _allName => widget.kind == VodKind.movies ? tr('Alle filmer') : tr('Alle serier');

  String _viewName(String view) {
    if (view.isEmpty) return tr('Kategorier');
    if (view == 'alle') return _allName;
    for (final c in _catalog?.categories ?? const <VodCategory>[]) {
      if (c.id == view) return c.name;
    }
    return tr('Kategorier');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _tools(),
        Expanded(
          child: SmoothSwitch(
            slide: false,
            child: KeyedSubtree(
              key: ValueKey(_grid ? 'rutenett:$_view' : 'oversikt'),
              child: _grid ? _gridContent() : _home(),
            ),
          ),
        ),
      ],
    );
  }

  /// Kategorien øverst (som en knapp med meny), tilbake til oversikten, og sorteringen i rutenettet.
  Widget _tools() {
    final scheme = Theme.of(context).colorScheme;
    final c = _catalog;
    final count = !_grid || !_loadedOnce
        ? ''
        : (_total > _items.length
            ? tr('Viser {shown} av {total}', {'shown': _items.length, 'total': _total})
            : '$_total');
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Row(
        children: [
          if (_view.isNotEmpty)
            IconButton(
              tooltip: tr('Tilbake til oversikten'),
              icon: const Icon(Icons.arrow_back),
              onPressed: () => _setView(''),
            ),
          Flexible(
            child: PopupMenuButton<String>(
              tooltip: tr('Velg kategori'),
              onSelected: _setView,
              itemBuilder: (context) => [
                CheckedPopupMenuItem(value: '', checked: _view.isEmpty, child: Text(tr('Oversikt'))),
                CheckedPopupMenuItem(
                  value: 'alle',
                  checked: _view == 'alle',
                  child: Text(c == null ? _allName : '$_allName (${c.total})'),
                ),
                for (final cat in c?.categories ?? const <VodCategory>[])
                  CheckedPopupMenuItem(
                    value: cat.id,
                    checked: _view == cat.id,
                    child: Text('${cat.name} (${cat.count})', overflow: TextOverflow.ellipsis),
                  ),
              ],
              child: _Pill(
                icon: widget.kind == VodKind.movies ? Icons.movie_outlined : Icons.video_library_outlined,
                label: _viewName(_view),
              ),
            ),
          ),
          const Spacer(),
          if (count.isNotEmpty) Text(count, style: TextStyle(color: scheme.onSurfaceVariant)),
          if (_grid)
            PopupMenuButton<VodSort>(
              tooltip: tr('Sortering'),
              icon: const Icon(Icons.sort),
              onSelected: (v) {
                setState(() => _sort = v);
                unawaited(_reload());
              },
              itemBuilder: (context) => [
                for (final o in VodSort.values) CheckedPopupMenuItem(value: o, checked: o == _sort, child: Text(o.title)),
              ],
            ),
        ],
      ),
    );
  }

  /// Oversikten: «Fortsett å se», favorittene, «Nylig lagt til» og en rad for hver kategori (bygges når du kommer dit).
  Widget _home() {
    final src = s.source;
    if (src == null) return const SizedBox.shrink();
    final width = MediaQuery.sizeOf(context).width;
    final phone = width < 600;
    final posterW = phone ? 132.0 : 164.0;
    final posterH = posterW * 1.5 + 66;
    final wideW = phone ? math.min(width * 0.78, 320.0) : 340.0;
    final wideH = wideW * 9 / 16 + 62;
    final continues = _continueItems;
    final favorites = s.vodFavorites(widget.kind);
    final error = _catalogError;
    final fixed = <Widget>[
      if (continues.isNotEmpty)
        _VodRow(
          title: tr('Fortsett å se'),
          height: wideH,
          count: continues.length,
          builder: (context, i) => _WideContinueCard(
            key: ValueKey('fortsett:${continues[i].key}'),
            session: s,
            item: continues[i],
            width: wideW,
            onTap: () => unawaited(_continue(continues[i])),
            onRemove: () => setState(() => s.removeContinue(continues[i].key)),
          ),
        ),
      if (favorites.isNotEmpty)
        _VodRow(
          title: tr('Favoritter'),
          height: posterH,
          count: favorites.length,
          builder: (context, i) => SizedBox(
            width: posterW,
            child: PosterCard(
              key: ValueKey('favoritt:${favorites[i].id}'),
              item: favorites[i],
              imageUrl: src.logoUrl(favorites[i].icon),
              radius: 14,
              onTap: () => unawaited(_open(favorites[i])),
            ),
          ),
        ),
      _LoadedRow(
        key: const ValueKey('nylig'),
        title: tr('Nylig lagt til'),
        load: () => src.vodPage(widget.kind, sort: VodSort.newest),
        height: posterH,
        posterW: posterW,
        imageUrl: src.logoUrl,
        onOpen: (item) => unawaited(_open(item)),
        onAll: () => _setView('alle', sort: VodSort.newest),
      ),
      if (error != null && _catalog == null)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(error, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => unawaited(_loadCatalog(force: true)), child: Text(tr('Prøv igjen'))),
            ],
          ),
        ),
    ];
    final cats = _catalog?.categories ?? const <VodCategory>[];
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: fixed.length + cats.length,
      itemBuilder: (context, i) {
        if (i < fixed.length) return fixed[i];
        final c = cats[i - fixed.length];
        return _LoadedRow(
          key: ValueKey('kategori:${c.id}'),
          title: c.name,
          load: () => src.vodPage(widget.kind, category: c.id),
          height: posterH,
          posterW: posterW,
          imageUrl: src.logoUrl,
          onOpen: (item) => unawaited(_open(item)),
          onAll: () => _setView(c.id),
        );
      },
    );
  }

  /// Rutenettet: alt, en kategori eller søket.
  Widget _gridContent() {
    final scheme = Theme.of(context).colorScheme;
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
                child: Text(tr('Prøv igjen')),
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
            Text(widget.kind == VodKind.movies
                ? tr('Henter filmer … Første gang kan det ta litt tid.')
                : tr('Henter serier … Første gang kan det ta litt tid.')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(widget.query.isNotEmpty ? tr('Fant ingenting.') : tr('Ingenting her.'),
            style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }
    return CustomScrollView(
      slivers: [
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
                radius: 14,
                onTap: () => unawaited(_open(it)),
              );
            },
          ),
        ),
        if (error != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Row(
                children: [
                  Flexible(child: Text(error, style: TextStyle(color: scheme.error))),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () {
                      setState(() => _error = null);
                      unawaited(_more());
                    },
                    child: Text(tr('Prøv igjen')),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Knappen øverst med kategorien du ser på (som i en strømmetjeneste): ikon, navn og pil ned.
class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, size: 18, color: scheme.onPrimary),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 6),
          Icon(Icons.keyboard_arrow_down, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// Overskriften over en rad, med «Vis alle» til høyre.
class _RowHeader extends StatelessWidget {
  const _RowHeader({required this.title, this.onAll});

  final String title;
  final VoidCallback? onAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: scheme.onSurface.withValues(alpha: 0.88),
              ),
            ),
          ),
          if (onAll != null)
            TextButton(
              onPressed: onAll,
              child: Text(tr('Vis alle'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ),
        ],
      ),
    );
  }
}

/// En rad bortover med overskrift.
class _VodRow extends StatelessWidget {
  const _VodRow({required this.title, required this.height, required this.count, required this.builder, this.onAll});

  final String title;
  final double height;
  final int count;
  final Widget Function(BuildContext context, int index) builder;
  final VoidCallback? onAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RowHeader(title: title, onAll: onAll),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 13),
            itemCount: count,
            separatorBuilder: (context, i) => const SizedBox(width: 12),
            itemBuilder: builder,
          ),
        ),
      ],
    );
  }
}

/// En rad med plakater som hentes når raden bygges (det som sist kom, eller en kategori). Tom eller feil: ingen rad.
class _LoadedRow extends StatefulWidget {
  const _LoadedRow({
    super.key,
    required this.title,
    required this.load,
    required this.height,
    required this.posterW,
    required this.imageUrl,
    required this.onOpen,
    this.onAll,
  });

  final String title;
  final Future<VodPage> Function() load;
  final double height;
  final double posterW;
  final String? Function(String? icon) imageUrl;
  final void Function(VodItem item) onOpen;
  final VoidCallback? onAll;

  @override
  State<_LoadedRow> createState() => _LoadedRowState();
}

class _LoadedRowState extends State<_LoadedRow> {
  List<VodItem>? _items;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final page = await widget.load();
      if (mounted) setState(() => _items = page.items.take(24).toList());
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (_failed || (items != null && items.isEmpty)) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return _VodRow(
      title: widget.title,
      height: widget.height,
      count: items?.length ?? 6,
      onAll: widget.onAll,
      builder: (context, i) => SizedBox(
        width: widget.posterW,
        child: items == null
            // mens raden hentes: tomme plakater, så siden ikke hopper
            ? Padding(
                padding: const EdgeInsets.all(3),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: AspectRatio(
                    aspectRatio: 2 / 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              )
            : PosterCard(
                key: ValueKey('${items[i].id}#$i'),
                item: items[i],
                imageUrl: widget.imageUrl(items[i].icon),
                radius: 14,
                onTap: () => widget.onOpen(items[i]),
              ),
      ),
    );
  }
}

/// Et bredt kort i «Fortsett å se»: bakgrunnsbildet (ellers plakaten), en hvit strek for hvor langt du har kommet,
/// ♡ for favorittene og × for å fjerne det, med navnet og episoden under.
class _WideContinueCard extends StatefulWidget {
  const _WideContinueCard({
    super.key,
    required this.session,
    required this.item,
    required this.width,
    required this.onTap,
    required this.onRemove,
  });

  final Session session;
  final ContinueItem item;
  final double width;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_WideContinueCard> createState() => _WideContinueCardState();
}

class _WideContinueCardState extends State<_WideContinueCard> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = widget.session;
    final c = widget.item;
    final src = s.source;
    final state = s.resumeState(c.resumeKey);
    final seen = s.watched(c.resumeKey);
    final String status;
    if (state != null) {
      final left = state.length - state.position;
      status = left.inMinutes >= 1 ? tr('{n} min igjen', {'n': left.inMinutes}) : tr('Snart ferdig');
    } else if (seen >= 0.95 || seen == 0) {
      // en serie der forrige episode er sett: denne er den neste
      status = c.kind == VodKind.series ? tr('Neste episode') : '';
    } else {
      status = '';
    }
    final line = [
      if (c.kind == VodKind.series && c.subtitle.isNotEmpty) c.subtitle,
      if (status.isNotEmpty) status,
    ].join(' · ');
    final favorite = s.isVodFavorite(c.kind, c.id);
    final backdrop = src?.logoUrl(c.backdrop);
    final poster = src?.logoUrl(c.icon);
    final title = cleanTitle(c.title).title;
    final fill = _PosterFill(url: poster, title: title);
    return SizedBox(
      width: widget.width,
      child: Lift(
        up: _focused || _hovered,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (f) => setState(() => _focused = f),
            onHover: (h) => setState(() => _hovered = h),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _focused ? scheme.tertiary : Colors.transparent, width: 3),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (backdrop != null)
                              NetImage(backdrop, decodeWidth: widget.width, fallback: fill)
                            else
                              fill,
                            // mørkere nederst, så streken synes på lyse bilder
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.center,
                                  colors: [Color(0x8C000000), Color(0x00000000)],
                                ),
                              ),
                            ),
                            if (seen > 0 && seen < 0.95)
                              Positioned(left: 16, right: 16, bottom: 14, child: _ArtProgress(value: seen)),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _RoundButton(
                                    icon: favorite ? Icons.favorite : Icons.favorite_border,
                                    color: favorite ? scheme.primary : Colors.white,
                                    tooltip: favorite ? tr('Fjern fra favoritter') : tr('Legg til i favoritter'),
                                    onPressed: () {
                                      s.toggleVodFavorite(
                                        c.kind,
                                        VodItem(
                                          id: c.id,
                                          name: c.title,
                                          icon: c.icon,
                                          ext: c.ext,
                                          backdrop: c.backdrop,
                                        ),
                                      );
                                      setState(() {});
                                    },
                                  ),
                                  const SizedBox(width: 6),
                                  _RoundButton(
                                    icon: Icons.close,
                                    color: Colors.white,
                                    tooltip: tr('Fjern fra «Fortsett å se»'),
                                    onPressed: widget.onRemove,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                    ),
                  ),
                  if (line.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
                      child: Text(
                        line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
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
}

/// Hvor langt du har kommet: en hvit strek på et gjennomsiktig spor, med runde ender.
class _ArtProgress extends StatelessWidget {
  const _ArtProgress({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0x59FFFFFF)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(0.0, 1.0).toDouble(),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Når det ikke finnes et bakgrunnsbilde: plakaten uskarp over hele kortet, og skarp til venstre.
class _PosterFill extends StatelessWidget {
  const _PosterFill({required this.url, required this.title});

  final String? url;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final u = url;
    if (u == null) {
      return Container(
        color: scheme.surfaceContainerHighest,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(16),
        child: Text(
          title,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700, fontSize: 18),
        ),
      );
    }
    final plain = ColoredBox(color: scheme.surfaceContainerHighest);
    return Stack(
      fit: StackFit.expand,
      children: [
        ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: NetImage(u, decodeWidth: 160, fallback: plain),
        ),
        const ColoredBox(color: Color(0x40000000)),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: NetImage(u, decodeWidth: 120, fallback: plain),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// En liten rund knapp oppå et bilde (♡ og ×).
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.color, required this.tooltip, required this.onPressed});

  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x8C000000),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        iconSize: 18,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        padding: EdgeInsets.zero,
        color: color,
        icon: Icon(icon),
        onPressed: onPressed,
      ),
    );
  }
}

/// Plakat med navn, år og vurdering. Markert når den har fokus (fjernkontroll og tastatur).
class PosterCard extends StatefulWidget {
  const PosterCard({super.key, required this.item, required this.imageUrl, required this.onTap, this.radius = 10});

  final VodItem item;
  final String? imageUrl;
  final VoidCallback onTap;

  /// hjørnene på plakaten
  final double radius;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final it = widget.item;
    // «Matchbox the Movie [PRE] [2026]»: navnet uten merker, året under og merkene på plakaten
    final clean = cleanTitle(it.name);
    final sub = [it.year ?? clean.year ?? '', ratingText(it.rating)].where((t) => t.isNotEmpty).join('  ');
    return Lift(
      up: _focused || _hovered,
      scale: 1.04,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(widget.radius + 2),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          onHover: (h) => setState(() => _hovered = h),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.radius),
                    border: Border.all(color: _focused ? scheme.tertiary : Colors.transparent, width: 3),
                  ),
                  child: Stack(
                    children: [
                      Poster(url: widget.imageUrl, title: clean.title, showTitle: false, radius: widget.radius),
                      if (clean.tags.isNotEmpty)
                        Positioned(
                          left: 6,
                          top: 6,
                          right: 6,
                          child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [for (final t in clean.tags.take(2)) PosterTag(text: t)],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  clean.title,
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
  bool _hovered = false;

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
      status = left.inMinutes >= 1 ? tr('{n} min igjen', {'n': left.inMinutes}) : tr('Snart ferdig');
    } else if (seen >= 0.95 || seen == 0) {
      // en serie der forrige episode er sett: denne er den neste
      status = c.kind == VodKind.series ? tr('Neste episode') : '';
    } else {
      status = '';
    }
    final lines = [
      if (c.kind == VodKind.series && c.subtitle.isNotEmpty) c.subtitle,
      if (status.isNotEmpty) status,
    ];
    return SizedBox(
      width: 300,
      child: Lift(
        up: _focused || _hovered,
        child: Material(
          color: scheme.surface,
          clipBehavior: Clip.antiAlias,
          elevation: _focused || _hovered ? 6 : 0,
          shadowColor: Colors.black54,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: _focused ? scheme.tertiary : scheme.outline, width: _focused ? 2 : 1),
          ),
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (f) => setState(() => _focused = f),
            onHover: (h) => setState(() => _hovered = h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 74,
                  child: Poster(url: s.source?.logoUrl(c.icon), title: c.title, radius: 0, showTitle: false, decodeWidth: 80),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(cleanTitle(c.title).title,
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
                    tooltip: tr('Fjern fra «Fortsett å se»'),
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
      ),
    );
  }
}

/// Et merke fra navnet hos leverandøren («PRE», «KIDS») i hjørnet av en plakat.
class PosterTag extends StatelessWidget {
  const PosterTag({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: const Color(0xD9000000), borderRadius: BorderRadius.circular(5)),
      child: Text(
        text.toUpperCase(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: scheme.primary, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 0.4),
      ),
    );
  }
}
