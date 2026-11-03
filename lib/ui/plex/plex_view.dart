// Plex-fanen: Hjem (Fortsett å se og det som sist kom i hvert bibliotek), bibliotekene (sidemeny i et bredt vindu,
// ellers nedtrekksliste) med sjanger og sortering, og søket i toppen av siden.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/plex/plex_account.dart';
import '../../core/plex/plex_api.dart';
import '../../core/plex/plex_models.dart';
import '../../core/session.dart';
import '../../l10n/tr.dart';
import '../motion.dart';
import 'plex_detail_page.dart';
import 'plex_play.dart';
import 'plex_widgets.dart';

class PlexView extends StatefulWidget {
  const PlexView({super.key, required this.session, required this.query});

  final Session session;

  /// søket i toppen av siden (i biblioteket du står i, ellers i alle)
  final String query;

  @override
  State<PlexView> createState() => _PlexViewState();
}

class _PlexViewState extends State<PlexView> {
  /// 'home' eller nøkkelen til et bibliotek
  String _place = 'home';

  /// økes når du kommer tilbake fra en detaljside eller spilleren: «Fortsett å se» og hva som er sett, hentes på nytt
  final _refresh = ValueNotifier<int>(0);

  Session get s => widget.session;
  PlexAccount get plex => s.plex;

  @override
  void initState() {
    super.initState();
    plex.addListener(_changed);
    unawaited(_connect());
  }

  @override
  void dispose() {
    plex.removeListener(_changed);
    _refresh.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _connect({bool force = false}) async {
    try {
      await plex.connect(force: force);
    } on PlexException {
      // vises fra plex.status og plex.error
    }
  }

  Future<void> _open(PlexItem item) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => PlexDetailPage(session: s, item: item)));
    _refresh.value++;
  }

  Future<void> _play(PlexItem item) async {
    await playPlexItem(context, s, item);
    _refresh.value++;
  }

  PlexLibrary? get _library {
    for (final l in plex.libraries) {
      if (l.key == _place) return l;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (plex.api == null) {
      if (plex.status == PlexStatus.failed) {
        return PlexMessage(
          text: plex.error ?? tr('Fikk ikke kontakt med Plex.'),
          error: true,
          onRetry: () => unawaited(_connect(force: true)),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(tr('Kobler til Plex …')),
          ],
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final library = _library;
    final place = library?.key ?? 'home';
    final searching = widget.query.isNotEmpty;
    final Widget content = searching
        ? _PlexSearch(plex: plex, query: widget.query, library: library, onOpen: _open)
        : library == null
            ? _PlexHome(plex: plex, refresh: _refresh, onOpen: _open, onPlay: _play)
            : _PlexLibraryView(
                key: ValueKey('bibliotek:${library.key}'),
                plex: plex,
                library: library,
                refresh: _refresh,
                onOpen: _open,
              );
    final switched = SmoothSwitch(
      child: KeyedSubtree(key: ValueKey(searching ? 'søk:$place' : place), child: content),
    );
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 260, child: _sidebar(place)),
          VerticalDivider(width: 1, color: scheme.outline),
          Expanded(child: switched),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_picker(place), Expanded(child: switched)],
    );
  }

  Widget _sidebar(String place) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _tile('home', tr('Hjem'), Icons.home_outlined, place),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 6),
          child: Text(
            tr('Biblioteker').toUpperCase(),
            style: TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
          ),
        ),
        for (final l in plex.libraries) _tile(l.key, l.title, l.shows ? Icons.tv_outlined : Icons.movie_outlined, place),
        if (plex.libraries.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 16, 4),
            child: Text(tr('Ingen biblioteker med filmer eller serier.'), style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
      ],
    );
  }

  Widget _tile(String id, String name, IconData icon, String place) {
    final scheme = Theme.of(context).colorScheme;
    final selected = id == place;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? scheme.surfaceContainerHighest : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _place = id),
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(icon, size: 20, color: selected ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? scheme.primary : null,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Smalt vindu: Hjem og bibliotekene i en nedtrekksliste.
  Widget _picker(String place) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: DropdownButton<String>(
          isExpanded: true,
          value: place,
          items: [
            DropdownMenuItem(value: 'home', child: Text(tr('Hjem'))),
            for (final l in plex.libraries)
              DropdownMenuItem(value: l.key, child: Text(l.title, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setState(() => _place = v ?? 'home'),
        ),
      );
}

/// Hjem: «Fortsett å se» og det som sist kom i hvert bibliotek, i rader bortover.
class _PlexHome extends StatefulWidget {
  const _PlexHome({required this.plex, required this.refresh, required this.onOpen, required this.onPlay});

  final PlexAccount plex;
  final Listenable refresh;
  final void Function(PlexItem item) onOpen;
  final void Function(PlexItem item) onPlay;

  @override
  State<_PlexHome> createState() => _PlexHomeState();
}

class _PlexHomeState extends State<_PlexHome> {
  List<PlexItem>? _continue;
  final Map<String, List<PlexItem>> _recent = {};

  /// feilene per rad ('fortsett' eller bibliotekets nøkkel)
  final Map<String, String> _errors = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_reload);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_reload);
    super.dispose();
  }

  void _reload() => unawaited(_load());

  Future<void> _row(String key, Future<List<PlexItem>> Function(PlexServerApi api) call,
      void Function(List<PlexItem> items) done) async {
    try {
      final list = await widget.plex.run(call);
      if (!mounted) return;
      setState(() {
        done(list);
        _errors.remove(key);
      });
    } on PlexException catch (e) {
      if (mounted) setState(() => _errors[key] = e.message);
    }
  }

  Future<void> _load() async {
    final plex = widget.plex;
    await Future.wait([
      _row('fortsett', (api) => api.continueWatching(), (list) => _continue = list),
      for (final l in plex.libraries) _row(l.key, (api) => api.recentlyAdded(l), (list) => _recent[l.key] = list),
    ]);
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final plex = widget.plex;
    final rows = <Widget>[];
    final cont = _continue ?? const <PlexItem>[];
    if (cont.isNotEmpty) {
      rows.add(PlexRow(
        title: tr('Fortsett å se'),
        height: 216,
        itemWidth: 280,
        count: cont.length,
        builder: (context, i) => PlexWideCard(
          key: ValueKey('fortsett:${cont[i].ratingKey}'),
          plex: plex,
          item: cont[i],
          onTap: () => widget.onPlay(cont[i]),
          onInfo: () => widget.onOpen(cont[i]),
        ),
      ));
    }
    for (final l in plex.libraries) {
      final list = _recent[l.key] ?? const <PlexItem>[];
      if (list.isEmpty) continue;
      rows.add(PlexRow(
        title: tr('Nylig lagt til i {library}', {'library': l.title}),
        height: 300,
        itemWidth: 150,
        count: list.length,
        builder: (context, i) => PlexPosterCard(
          key: ValueKey('nylig:${l.key}:${list[i].ratingKey}'),
          plex: plex,
          item: list[i],
          onTap: () => widget.onOpen(list[i]),
        ),
      ));
    }
    if (rows.isEmpty) {
      if (!_loaded) return const Center(child: CircularProgressIndicator());
      if (_errors.isNotEmpty) return PlexMessage(text: _errors.values.first, error: true, onRetry: _reload);
      return PlexMessage(text: tr('Ingenting her ennå. Legg til filmer eller serier på Plex-serveren.'));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: rows);
  }
}

/// Et bibliotek: plakatene i et rutenett, med sjanger og sortering. Lista hentes en side om gangen.
class _PlexLibraryView extends StatefulWidget {
  const _PlexLibraryView({
    super.key,
    required this.plex,
    required this.library,
    required this.refresh,
    required this.onOpen,
  });

  final PlexAccount plex;
  final PlexLibrary library;
  final Listenable refresh;
  final void Function(PlexItem item) onOpen;

  @override
  State<_PlexLibraryView> createState() => _PlexLibraryViewState();
}

class _PlexLibraryViewState extends State<_PlexLibraryView> {
  /// sorteringen per bibliotek, så lenge appen er åpen
  static final Map<String, PlexSort> _sorts = {};

  static const _page = 100;

  late PlexSort _sort = _sorts[widget.library.key] ?? PlexSort.added;
  String _genre = '';
  List<PlexTag> _genres = const [];
  final List<PlexItem> _items = [];
  int _total = 0;
  bool _loading = false;
  bool _loadedOnce = false;
  bool _morePending = false;
  String? _error;
  int _seq = 0;

  PlexAccount get plex => widget.plex;

  @override
  void initState() {
    super.initState();
    widget.refresh.addListener(_refreshLoaded);
    unawaited(_loadGenres());
    unawaited(_reload());
  }

  @override
  void dispose() {
    widget.refresh.removeListener(_refreshLoaded);
    super.dispose();
  }

  Future<void> _loadGenres() async {
    try {
      final list = await plex.run((api) => api.genres(widget.library));
      if (mounted) setState(() => _genres = list);
    } on PlexException {
      // uten sjangervalg
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
    if (_loading || (_loadedOnce && _items.length >= _total)) return;
    final my = _seq;
    setState(() => _loading = true);
    try {
      final page = await plex.run(
        (api) => api.items(widget.library, sort: _sort, genre: _genre, start: _items.length, size: _page),
      );
      if (!mounted || my != _seq) return;
      setState(() {
        _items.addAll(page.items);
        // en tom side betyr at det ikke er mer, uansett hva totalen sa
        _total = page.items.isEmpty ? _items.length : math.max(page.total, _items.length);
        _loadedOnce = true;
        _loading = false;
      });
    } on PlexException catch (e) {
      if (!mounted || my != _seq) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// Tilbake fra en detaljside eller spilleren: det som alt er hentet, hentes på nytt på samme plass (sett og
  /// framdrift), så du blir stående der du var.
  Future<void> _refreshLoaded() async {
    if (_loading || _items.isEmpty) return;
    final my = ++_seq;
    try {
      final page = await plex.run(
        (api) => api.items(widget.library, sort: _sort, genre: _genre, size: math.min(math.max(_items.length, _page), 600)),
      );
      if (!mounted || my != _seq) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _total = math.max(page.total, _items.length);
      });
    } on PlexException {
      // står som før
    }
  }

  void _maybeMore() {
    if (_morePending || _loading || _error != null || _items.length >= _total) return;
    _morePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _morePending = false;
      if (mounted) unawaited(_more());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_tools(), Expanded(child: _content())],
    );
  }

  Widget _tools() {
    final scheme = Theme.of(context).colorScheme;
    final count = !_loadedOnce
        ? ''
        : (_total > _items.length
            ? tr('Viser {shown} av {total}', {'shown': _items.length, 'total': _total})
            : '$_total');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Flexible(
            child: DropdownButton<String>(
              isExpanded: true,
              value: _genres.any((g) => g.key == _genre) ? _genre : '',
              items: [
                DropdownMenuItem(value: '', child: Text(tr('Alle sjangre'))),
                for (final g in _genres) DropdownMenuItem(value: g.key, child: Text(g.title, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) {
                setState(() => _genre = v ?? '');
                unawaited(_reload());
              },
            ),
          ),
          const SizedBox(width: 16),
          DropdownButton<PlexSort>(
            value: _sort,
            items: [for (final o in PlexSort.values) DropdownMenuItem(value: o, child: Text(o.title))],
            onChanged: (v) {
              final sort = v ?? PlexSort.added;
              _sorts[widget.library.key] = sort;
              setState(() => _sort = sort);
              unawaited(_reload());
            },
          ),
          const SizedBox(width: 16),
          Text(count, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _content() {
    final scheme = Theme.of(context).colorScheme;
    final error = _error;
    if (error != null && _items.isEmpty) return PlexMessage(text: error, error: true, onRetry: () => unawaited(_reload()));
    if (!_loadedOnce) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return PlexMessage(text: tr('Ingenting her.'));
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
              return PlexPosterCard(
                key: ValueKey('${it.ratingKey}#$i'),
                plex: plex,
                item: it,
                onTap: () => widget.onOpen(it),
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

/// Søket: filmer, serier og episoder (i biblioteket du står i, ellers i alle).
class _PlexSearch extends StatefulWidget {
  const _PlexSearch({required this.plex, required this.query, required this.library, required this.onOpen});

  final PlexAccount plex;
  final String query;
  final PlexLibrary? library;
  final void Function(PlexItem item) onOpen;

  @override
  State<_PlexSearch> createState() => _PlexSearchState();
}

class _PlexSearchState extends State<_PlexSearch> {
  List<PlexItem>? _results;
  String? _error;
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(_PlexSearch old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query || old.library?.key != widget.library?.key) _schedule();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => unawaited(_search()));
  }

  Future<void> _search() async {
    final my = ++_seq;
    final query = widget.query;
    final section = widget.library?.key;
    try {
      final list = await widget.plex.run((api) => api.search(query, section: section));
      if (!mounted || my != _seq) return;
      setState(() {
        _results = list;
        _error = null;
      });
    } on PlexException catch (e) {
      if (mounted && my == _seq) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    final results = _results;
    if (error != null) return PlexMessage(text: error, error: true, onRetry: () => unawaited(_search()));
    if (results == null) return const Center(child: CircularProgressIndicator());
    if (results.isEmpty) return PlexMessage(text: tr('Fant ingenting.'));
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        mainAxisSpacing: 16,
        crossAxisSpacing: 14,
        childAspectRatio: 0.5,
      ),
      itemCount: results.length,
      itemBuilder: (context, i) => PlexPosterCard(
        key: ValueKey('treff:${results[i].ratingKey}'),
        plex: widget.plex,
        item: results[i],
        onTap: () => widget.onOpen(results[i]),
      ),
    );
  }
}
