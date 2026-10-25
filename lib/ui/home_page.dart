import 'dart:async';

import 'package:flutter/material.dart';

import '../build_info.dart';
import '../core/models.dart';
import '../core/session.dart';
import '../core/updater.dart';
import 'channel_card.dart';
import 'player_page.dart';

/// TV-siden: kategorier (sidemeny på PC og TV, nedtrekksliste på telefon), søk og kanalkort.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.session, this.updater});

  final Session session;

  /// oppdateringer fra GitHub (Windows); null i testene og der appen ikke oppdaterer seg selv
  final Updater? updater;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _search = TextEditingController();
  String _filter = 'all';
  String _query = '';
  bool _searching = false;
  Timer? _clock;
  StreamSubscription<String>? _messages;

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    // «nå»-linja og fremdriften på kortene flytter seg
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
    _messages = s.messages.listen((m) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    unawaited(_messages?.cancel());
    _search.dispose();
    super.dispose();
  }

  List<Channel> get _visible {
    final words = _query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final base = s.channelsIn(_filter);
    if (words.isEmpty) return base;
    return [
      for (final c in base)
        if (words.every(c.name.toLowerCase().contains)) c,
    ];
  }

  String get _title => switch (_filter) {
        'all' => 'Alle kanaler',
        'fav' => 'Favoritter',
        'recent' => 'Sist sett',
        _ => s.categoryName(_filter),
      };

  void _play(List<Channel> list, int i) {
    final title = _query.isEmpty ? _title : 'Treff i ${_title.toLowerCase()}';
    final fromFavorites = _filter == 'fav';
    unawaited(Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerPage(
          session: s,
          channels: List.of(list),
          index: i,
          listTitle: title,
          fromFavorites: fromFavorites,
        ),
      ),
    ));
  }

  void _select(String filter) => setState(() => _filter = filter);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final list = _visible;
    final content = _content(list);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: !wide && _searching
            ? _searchField(autofocus: true)
            : Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: Image.asset('assets/fyrlys.png', width: 30, height: 30),
                  ),
                  const SizedBox(width: 10),
                  const Text('Fyrlys', style: TextStyle(fontWeight: FontWeight.w700)),
                  if (wide) ...[
                    const SizedBox(width: 32),
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: _searchField()),
                      ),
                    ),
                  ],
                ],
              ),
        actions: [
          if (!wide)
            IconButton(
              tooltip: _searching ? 'Lukk søket' : 'Søk',
              icon: Icon(_searching ? Icons.close : Icons.search),
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _search.clear();
                  _query = '';
                }
              }),
            ),
          IconButton(
            tooltip: 'Lys eller mørk',
            icon: Icon(theme.brightness == Brightness.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => s.toggleTheme(theme.brightness),
          ),
          PopupMenuButton<String>(
            tooltip: 'Meny',
            onSelected: (v) {
              if (v == 'reload') unawaited(s.load(force: true));
              if (v == 'update') unawaited(_checkUpdates());
              if (v == 'logout') unawaited(s.logout());
            },
            itemBuilder: (context) => [
              PopupMenuItem<String>(enabled: false, child: Text(s.source?.label ?? '')),
              const PopupMenuItem<String>(value: 'reload', child: Text('Hent listene på nytt')),
              if (widget.updater?.enabled ?? false)
                const PopupMenuItem<String>(value: 'update', child: Text('Se etter oppdateringer')),
              const PopupMenuItem<String>(value: 'logout', child: Text('Logg ut')),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                enabled: false,
                child: Text(appBuildLabel, style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.updater case final u?) ListenableBuilder(listenable: u, builder: (context, _) => _updateBanner(u)),
          Expanded(
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(width: 280, child: _sidebar()),
                      VerticalDivider(width: 1, color: theme.colorScheme.outline),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [_header(list), Expanded(child: content)],
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [_picker(), Expanded(child: content)],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkUpdates() async {
    final u = widget.updater;
    if (u == null) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final info = await u.check(manual: true);
      if (info == null) messenger.showSnackBar(SnackBar(content: Text('Du har siste versjon ($appBuildLabel).')));
    } on UpdateException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Fikk ikke sjekket oppdateringer: ${e.message}')));
    }
  }

  /// Ny versjon: lastes ned i bakgrunnen og legges inn når du lukker Fyrlys (eller med «Start på nytt nå»).
  Widget _updateBanner(Updater u) {
    final scheme = Theme.of(context).colorScheme;
    final info = u.available;
    String? text;
    double? progress;
    final actions = <Widget>[];
    final close = IconButton(tooltip: 'Lukk', icon: const Icon(Icons.close), onPressed: u.dismiss);
    switch (u.state) {
      case UpdateState.available:
        text = 'Ny versjon: ${info?.title ?? ''}';
        if (info != null && info.notes.isNotEmpty) actions.add(_notesButton(info));
        actions.add(FilledButton(onPressed: () => unawaited(u.download()), child: const Text('Last ned')));
      case UpdateState.downloading:
        text = 'Laster ned ${info?.title ?? 'ny versjon'} … ${(u.progress * 100).round()} %';
        progress = u.progress;
      case UpdateState.ready:
        text = '${info?.title ?? 'En ny versjon'} er lastet ned og legges inn når du lukker Fyrlys.';
        if (info != null && info.notes.isNotEmpty) actions.add(_notesButton(info));
        actions.add(FilledButton(onPressed: () => unawaited(u.restartNow()), child: const Text('Start på nytt nå')));
      case UpdateState.failed:
        text = u.error ?? 'Oppdateringen feilet.';
        actions
          ..add(TextButton(onPressed: () => unawaited(u.check()), child: const Text('Prøv igjen')))
          ..add(close);
      case UpdateState.idle:
      case UpdateState.checking:
        text = u.notice;
        actions.add(close);
    }
    if (text == null) return const SizedBox.shrink();
    return Material(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  u.state == UpdateState.failed ? Icons.error_outline : Icons.system_update_alt,
                  color: u.state == UpdateState.failed ? scheme.error : scheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(text)),
                for (final a in actions) Padding(padding: const EdgeInsets.only(left: 8), child: a),
              ],
            ),
            if (progress != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(36, 6, 8, 4),
                child: LinearProgressIndicator(value: progress),
              ),
          ],
        ),
      ),
    );
  }

  Widget _notesButton(UpdateInfo info) => TextButton(
        onPressed: () => unawaited(showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(info.title),
            content: SingleChildScrollView(child: SelectableText(info.notes)),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Lukk'))],
          ),
        )),
        child: const Text('Hva er nytt?'),
      );

  Widget _searchField({bool autofocus = false}) => TextField(
        controller: _search,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search), hintText: 'Søk etter kanal'),
        onChanged: (v) => setState(() => _query = v.trim()),
      );

  Widget _header(List<Channel> list) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _query.isEmpty ? _title : 'Treff i ${_title.toLowerCase()}',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text('${list.length}', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _content(List<Channel> list) {
    final scheme = Theme.of(context).colorScheme;
    final error = s.error;
    if (s.channels.isEmpty && error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(error, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
              const SizedBox(height: 12),
              FilledButton(onPressed: () => unawaited(s.load(force: true)), child: const Text('Prøv igjen')),
            ],
          ),
        ),
      );
    }
    if (s.channels.isEmpty && s.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Henter kanaler … Første gang kan det ta litt tid.'),
          ],
        ),
      );
    }
    if (list.isEmpty) {
      final text = _query.isNotEmpty
          ? 'Fant ingenting.'
          : _filter == 'fav'
              ? 'Ingen favoritter ennå. Trykk ☆ på en kanal for å legge den til.'
              : _filter == 'recent'
                  ? 'Du har ikke sett noen kanaler ennå.'
                  : 'Ingen kanaler her.';
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(text, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisExtent: 84,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: list.length,
      itemBuilder: (context, i) => ChannelCard(
        key: ValueKey('${list[i].id}:$_filter'),
        session: s,
        channel: list[i],
        onTap: () => _play(list, i),
      ),
    );
  }

  /// Kategoriene du har lagt øverst, i din rekkefølge, og resten.
  ({List<Category> pinned, List<Category> rest}) _groups() {
    final byId = {for (final c in s.categories) c.id: c};
    return (
      pinned: [for (final id in s.favoriteCategories) if (byId[id] != null) byId[id]!],
      rest: [for (final c in s.categories) if (!s.isFavoriteCategory(c.id)) c],
    );
  }

  Widget _sidebar() {
    final scheme = Theme.of(context).colorScheme;
    final g = _groups();
    Widget head(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 6),
          child: Text(
            text.toUpperCase(),
            style: TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
          ),
        );
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        _categoryTile('all', 'Alle kanaler', s.channels.length),
        _categoryTile('fav', '★ Favoritter', s.favorites.length),
        _categoryTile('recent', 'Sist sett', s.recent.length),
        if (g.pinned.isNotEmpty) head('Dine kategorier'),
        for (var i = 0; i < g.pinned.length; i++)
          _categoryTile(
            g.pinned[i].id,
            g.pinned[i].name,
            s.categoryCounts[g.pinned[i].id] ?? 0,
            pinnable: true,
            first: i == 0,
            last: i == g.pinned.length - 1,
          ),
        head(g.pinned.isEmpty ? 'Kategorier · ☆ legger dem øverst' : 'Alle kategorier'),
        for (final c in g.rest) _categoryTile(c.id, c.name, s.categoryCounts[c.id] ?? 0, pinnable: true),
      ],
    );
  }

  Widget _categoryTile(String id, String name, int count, {bool pinnable = false, bool first = false, bool last = false}) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _filter == id;
    final pinned = pinnable && s.isFavoriteCategory(id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: selected ? scheme.surfaceContainerHighest : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _select(id),
          child: SizedBox(
            height: 40,
            child: Row(
              children: [
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
                Text('$count', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                if (pinned) ...[
                  _miniButton(Icons.arrow_upward, 'Flytt opp', first ? null : () => unawaited(s.moveFavoriteCategory(id, -1))),
                  _miniButton(Icons.arrow_downward, 'Flytt ned', last ? null : () => unawaited(s.moveFavoriteCategory(id, 1))),
                ],
                if (pinnable)
                  _miniButton(
                    pinned ? Icons.star : Icons.star_border,
                    pinned ? 'Fjern fra toppen' : 'Legg øverst',
                    () => unawaited(s.toggleFavoriteCategory(id)),
                    color: pinned ? scheme.primary : null,
                  )
                else
                  const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniButton(IconData icon, String tooltip, VoidCallback? onPressed, {Color? color}) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: color),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      );

  /// Telefon: kategoriene i en nedtrekksliste, med stjerne for å legge kategorien øverst.
  Widget _picker() {
    final g = _groups();
    final seen = <String>{'all', 'fav', 'recent'};
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(value: 'all', child: Text('Alle kanaler (${s.channels.length})')),
      DropdownMenuItem(value: 'fav', child: Text('★ Favoritter (${s.favorites.length})')),
      DropdownMenuItem(value: 'recent', child: Text('Sist sett (${s.recent.length})')),
      for (final c in [...g.pinned, ...g.rest])
        if (seen.add(c.id))
          DropdownMenuItem(
            value: c.id,
            child: Text(
              '${s.isFavoriteCategory(c.id) ? '★ ' : ''}${c.name} (${s.categoryCounts[c.id] ?? 0})',
              overflow: TextOverflow.ellipsis,
            ),
          ),
    ];
    final value = seen.contains(_filter) ? _filter : 'all';
    final isCategory = value != 'all' && value != 'fav' && value != 'recent';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              items: items,
              onChanged: (v) => _select(v ?? 'all'),
            ),
          ),
          if (isCategory)
            IconButton(
              tooltip: s.isFavoriteCategory(value) ? 'Fjern fra toppen' : 'Legg øverst',
              icon: Icon(s.isFavoriteCategory(value) ? Icons.star : Icons.star_border),
              onPressed: () => unawaited(s.toggleFavoriteCategory(value)),
            ),
        ],
      ),
    );
  }
}
