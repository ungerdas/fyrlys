import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/models.dart';
import '../core/session.dart';
import '../core/updater.dart';
import '../core/vod.dart';
import '../l10n/tr.dart';
import 'archive_page.dart';
import 'channel_card.dart';
import 'channel_number.dart';
import 'guide_view.dart';
import 'motion.dart';
import 'multiview_page.dart';
import 'player_page.dart';
import 'settings_page.dart';
import 'start_view.dart';
import 'vod_browser.dart';

/// TV-siden: startsiden («Hjem»), kategorier (sidemeny i et bredt vindu, ellers nedtrekksliste), søk og kanalkort.
/// Tall på tastaturet eller fjernkontrollen går rett til kanalen med det nummeret.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.session, this.updater});

  final Session session;

  /// oppdateringer fra GitHub (Windows); null i testene og der appen ikke oppdaterer seg selv
  final Updater? updater;

  @override
  State<HomePage> createState() => _HomePageState();
}

/// TV, TV-guide, Filmer og Serier: valget i toppen (bredt vindu) eller nederst (smalt vindu).
/// Filmer og Serier bare når kilden har dem (Xtream Codes, ikke en vanlig M3U-liste).
enum _Section { tv, guide, movies, series }

class _HomePageState extends State<HomePage> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'søk');
  _Section _section = _Section.tv;

  /// 'home' (startsiden), 'all', 'fav', 'recent' eller en kategori-id
  String _filter = 'home';
  String _query = '';
  bool _searching = false;
  Timer? _clock;

  /// tall du taster for å gå til en kanal; samles til det har gått 1,4 sekunder uten nye
  String _digits = '';
  Timer? _digitTimer;

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    // «nå»-linja og fremdriften på kortene flytter seg
    _clock = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _clock?.cancel();
    _digitTimer?.cancel();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// startsiden søker i alle kanalene
  String get _listFilter => _filter == 'home' ? 'all' : _filter;

  List<Channel> get _visible {
    final words = _query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final base = s.channelsIn(_listFilter);
    if (words.isEmpty) return base;
    return [
      for (final c in base)
        if (words.every(c.name.toLowerCase().contains)) c,
    ];
  }

  String get _title => switch (_filter) {
        'all' || 'home' => tr('Alle kanaler'),
        'fav' => tr('Favoritter'),
        'recent' => tr('Sist sett'),
        _ => s.categoryName(_filter),
      };

  void _play(List<Channel> list, int i) {
    final title = _query.isEmpty ? _title : tr('Treff i {list}', {'list': _title.toLowerCase()});
    _openPlayer(List.of(list), i, title, _filter == 'fav');
  }

  void _openPlayer(List<Channel> list, int i, String title, bool fromFavorites) {
    unawaited(Navigator.of(context).push(
      fadeRoute<void>(
        (_) => PlayerPage(
          session: s,
          channels: list,
          index: i,
          listTitle: title,
          fromFavorites: fromFavorites,
        ),
      ),
    ));
  }

  void _select(String filter) => setState(() => _filter = filter);

  void _openArchive(Channel ch) =>
      unawaited(Navigator.of(context).push(fadeRoute<void>((_) => ArchivePage(session: s, channel: ch))));

  // ── kanalnummer ──

  /// Tall på TV-siden og i TV-guiden (ikke mens du skriver i søket, og ikke når noe ligger over siden).
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    if (_current != _Section.tv && _current != _Section.guide) return false;
    if (_searchFocus.hasFocus || !(ModalRoute.of(context)?.isCurrent ?? false)) return false;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isMetaPressed || keyboard.isAltPressed) return false;
    final digit = digitOf(event.logicalKey);
    if (digit != null) {
      _digitTimer?.cancel();
      final next = _digits + digit;
      setState(() => _digits = next.length > 4 ? next.substring(next.length - 4) : next);
      _digitTimer = Timer(const Duration(milliseconds: 1400), _goToNumber);
      return true;
    }
    final ok = {LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter, LogicalKeyboardKey.select};
    if (_digits.isNotEmpty && ok.contains(event.logicalKey)) {
      _goToNumber();
      return true;
    }
    return false;
  }

  /// Kanalen med nummeret: i lista du ser på først, ellers blant alle kanalene.
  void _goToNumber() {
    _digitTimer?.cancel();
    final digits = _digits;
    if (!mounted) return;
    setState(() => _digits = '');
    if (digits.isEmpty) return;
    if (_current == _Section.tv) {
      final list = s.channelsIn(_listFilter);
      final i = channelByNumber(list, digits);
      if (i >= 0) {
        _openPlayer(list, i, _title, _filter == 'fav');
        return;
      }
    }
    final j = channelByNumber(s.channels, digits);
    if (j >= 0) {
      _openPlayer(s.channels, j, tr('Alle kanaler'), false);
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(tr('Fant ikke kanal {n}', {'n': int.parse(digits)}))));
    }
  }

  /// Bytter mellom TV, TV-guide, Filmer og Serier. Søket gjelder siden du er på, så det tømmes.
  void _setSection(_Section section) {
    if (section == _section) return;
    setState(() {
      _section = section;
      _search.clear();
      _query = '';
      _searching = false;
    });
  }

  /// fanene kilden har
  List<_Section> get _sectionList =>
      (s.source?.hasVod ?? false) ? _Section.values : const [_Section.tv, _Section.guide];

  /// fanen som vises (TV hvis du sto på Filmer/Serier og kilden ikke har dem)
  _Section get _current => _sectionList.contains(_section) ? _section : _Section.tv;

  String get _searchHint => switch (_current) {
        _Section.tv || _Section.guide => tr('Søk etter kanal'),
        _Section.movies => tr('Søk i filmer'),
        _Section.series => tr('Søk i serier'),
      };

  /// Valget i toppen; ikonene bare når det er god plass.
  Widget _sections(bool icons) => SegmentedButton<_Section>(
        showSelectedIcon: false,
        segments: [
          for (final x in _sectionList)
            ButtonSegment(value: x, icon: icons ? Icon(_sectionIcon(x)) : null, label: Text(_sectionName(x))),
        ],
        selected: {_current},
        onSelectionChanged: (v) => _setSection(v.first),
      );

  static String _sectionName(_Section x) => switch (x) {
        _Section.tv => tr('TV'),
        _Section.guide => tr('TV-guide'),
        _Section.movies => tr('Filmer'),
        _Section.series => tr('Serier'),
      };

  static IconData _sectionIcon(_Section x) => switch (x) {
        _Section.tv => Icons.live_tv,
        _Section.guide => Icons.view_timeline_outlined,
        _Section.movies => Icons.movie_outlined,
        _Section.series => Icons.video_library_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final list = _visible;
    final content = _content(list);
    final home = _filter == 'home' && _query.isEmpty;
    final section = _current;
    final sections = _sectionList;
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
                    const SizedBox(width: 24),
                    _sections(MediaQuery.sizeOf(context).width >= 1200),
                    const SizedBox(width: 24),
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
              tooltip: _searching ? tr('Lukk søket') : tr('Søk'),
              icon: Icon(_searching ? Icons.close : Icons.search),
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) {
                  _search.clear();
                  _query = '';
                }
              }),
            ),
          if (s.canMultiview)
            IconButton(
              tooltip: tr('Multiview'),
              icon: const Icon(Icons.grid_view_outlined),
              onPressed: _openMultiview,
            ),
          IconButton(
            tooltip: tr('Lys eller mørk'),
            icon: Icon(theme.brightness == Brightness.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () => s.toggleTheme(theme.brightness),
          ),
          IconButton(
            tooltip: tr('Innstillinger'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.updater case final u?) ListenableBuilder(listenable: u, builder: (context, _) => _updateBanner(u)),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // fanene og listene glir over i hverandre
                SmoothSwitch(
                  slide: false,
                  child: KeyedSubtree(
                    key: ValueKey(section),
                    child: switch (section) {
                      _Section.guide => GuideView(
                          key: const ValueKey('guide'),
                          session: s,
                          query: _query,
                          onPlay: _openPlayer,
                          onArchive: _openArchive,
                        ),
                      _Section.movies =>
                        VodBrowser(key: const ValueKey('filmer'), session: s, kind: VodKind.movies, query: _query),
                      _Section.series =>
                        VodBrowser(key: const ValueKey('serier'), session: s, kind: VodKind.series, query: _query),
                      _Section.tv => wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(width: 280, child: _sidebar()),
                                VerticalDivider(width: 1, color: theme.colorScheme.outline),
                                Expanded(
                                  child: SmoothSwitch(
                                    child: KeyedSubtree(
                                      key: ValueKey(home ? 'start' : 'liste:$_filter'),
                                      child: home
                                          ? _start()
                                          : Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [_header(list), Expanded(child: content)],
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _picker(),
                                Expanded(
                                  child: SmoothSwitch(
                                    child: KeyedSubtree(
                                      key: ValueKey(home ? 'start' : 'liste:$_filter'),
                                      child: home ? _start() : content,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    },
                  ),
                ),
                if (_digits.isNotEmpty)
                  Positioned(top: 16, right: 20, child: IgnorePointer(child: NumberBadge(digits: _digits))),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: sections.indexOf(section),
              onDestinationSelected: (i) => _setSection(sections[i]),
              destinations: [
                for (final x in sections) NavigationDestination(icon: Icon(_sectionIcon(x)), label: _sectionName(x)),
              ],
            ),
    );
  }

  /// Flere kanaler samtidig, med kanalen du så sist i det første bildet.
  void _openMultiview() => unawaited(Navigator.of(context).push(fadeRoute<void>(
      (_) => MultiviewPage(session: s, first: s.recent.isEmpty ? null : s.recent.first))));

  /// Innstillingene: innloggingene, utseende, avspilling, listene og oppdateringer.
  void _openSettings() => unawaited(Navigator.of(context)
      .push(fadeRoute<void>((_) => SettingsPage(session: s, updater: widget.updater))));

  /// Ny versjon: lastes ned i bakgrunnen og legges inn når du lukker Fyrlys (eller med «Start på nytt nå»).
  Widget _updateBanner(Updater u) {
    final scheme = Theme.of(context).colorScheme;
    final info = u.available;
    String? text;
    double? progress;
    final actions = <Widget>[];
    final close = IconButton(tooltip: tr('Lukk'), icon: const Icon(Icons.close), onPressed: u.dismiss);
    switch (u.state) {
      case UpdateState.available:
        text = tr('Ny versjon: {version}', {'version': info?.label ?? ''});
        if (info != null && info.notes.isNotEmpty) actions.add(_notesButton(info));
        actions.add(FilledButton(onPressed: () => unawaited(u.download()), child: Text(tr('Last ned'))));
      case UpdateState.downloading:
        final version = info?.label ?? tr('ny versjon');
        final percent = (u.progress * 100).round();
        text = info != null && info.size > 0
            ? tr('Laster ned {version} … {percent} % av {size} MB',
                {'version': version, 'percent': percent, 'size': (info.size / 1048576).round()})
            : tr('Laster ned {version} … {percent} %', {'version': version, 'percent': percent});
        progress = u.progress;
      case UpdateState.ready:
        text = tr('{version} er lastet ned og legges inn når du lukker Fyrlys.',
            {'version': info?.label ?? tr('En ny versjon')});
        if (info != null && info.notes.isNotEmpty) actions.add(_notesButton(info));
        actions.add(FilledButton(onPressed: () => unawaited(u.restartNow()), child: Text(tr('Start på nytt nå'))));
      case UpdateState.failed:
        text = u.error ?? tr('Oppdateringen feilet.');
        actions
          ..add(TextButton(onPressed: () => unawaited(u.check()), child: Text(tr('Prøv igjen'))))
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
            title: Text(info.label),
            content: SingleChildScrollView(child: SelectableText(info.notes)),
            actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Lukk')))],
          ),
        )),
        child: Text(tr('Hva er nytt?')),
      );

  Widget _searchField({bool autofocus = false}) => TextField(
        controller: _search,
        focusNode: _searchFocus,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(isDense: true, prefixIcon: const Icon(Icons.search), hintText: _searchHint),
        onChanged: (v) => setState(() => _query = v.trim()),
      );

  /// Startsiden («Hjem»).
  Widget _start() => StartView(
        session: s,
        onPlay: _openPlayer,
        onShow: _select,
      );

  Widget _header(List<Channel> list) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _query.isEmpty ? _title : tr('Treff i {list}', {'list': _title.toLowerCase()}),
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
              FilledButton(onPressed: () => unawaited(s.load(force: true)), child: Text(tr('Prøv igjen'))),
            ],
          ),
        ),
      );
    }
    if (s.channels.isEmpty && s.loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(tr('Henter kanaler … Første gang kan det ta litt tid.')),
          ],
        ),
      );
    }
    if (list.isEmpty) {
      final text = _query.isNotEmpty
          ? tr('Fant ingenting.')
          : _filter == 'fav'
              ? tr('Ingen favoritter ennå. Trykk ☆ på en kanal for å legge den til.')
              : _filter == 'recent'
                  ? tr('Du har ikke sett noen kanaler ennå.')
                  : tr('Ingen kanaler her.');
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
        _categoryTile('home', tr('Hjem'), null, icon: Icons.home_outlined),
        _categoryTile('all', tr('Alle kanaler'), s.channels.length, icon: Icons.apps),
        _categoryTile('fav', tr('Favoritter'), s.favorites.length, icon: Icons.star_outline),
        _categoryTile('recent', tr('Sist sett'), s.recent.length, icon: Icons.history),
        if (g.pinned.isNotEmpty) head(tr('Dine kategorier')),
        for (var i = 0; i < g.pinned.length; i++)
          _categoryTile(
            g.pinned[i].id,
            g.pinned[i].name,
            s.categoryCounts[g.pinned[i].id] ?? 0,
            pinnable: true,
            first: i == 0,
            last: i == g.pinned.length - 1,
          ),
        head(g.pinned.isEmpty ? tr('Kategorier · ☆ legger dem øverst') : tr('Alle kategorier')),
        for (final c in g.rest) _categoryTile(c.id, c.name, s.categoryCounts[c.id] ?? 0, pinnable: true),
      ],
    );
  }

  Widget _categoryTile(String id, String name, int? count,
      {IconData? icon, bool pinnable = false, bool first = false, bool last = false}) {
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
                if (icon != null) ...[
                  Icon(icon, size: 20, color: selected ? scheme.primary : scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                ],
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
                if (count != null) Text('$count', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                if (pinned) ...[
                  _miniButton(
                      Icons.arrow_upward, tr('Flytt opp'), first ? null : () => unawaited(s.moveFavoriteCategory(id, -1))),
                  _miniButton(
                      Icons.arrow_downward, tr('Flytt ned'), last ? null : () => unawaited(s.moveFavoriteCategory(id, 1))),
                ],
                if (pinnable)
                  _miniButton(
                    pinned ? Icons.star : Icons.star_border,
                    pinned ? tr('Fjern fra toppen') : tr('Legg øverst'),
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

  /// Smalt vindu: kategoriene i en nedtrekksliste, med stjerne for å legge kategorien øverst.
  Widget _picker() {
    final g = _groups();
    final seen = <String>{'home', 'all', 'fav', 'recent'};
    final items = <DropdownMenuItem<String>>[
      DropdownMenuItem(value: 'home', child: Text(tr('Hjem'))),
      DropdownMenuItem(value: 'all', child: Text(tr('Alle kanaler ({n})', {'n': s.channels.length}))),
      DropdownMenuItem(value: 'fav', child: Text(tr('★ Favoritter ({n})', {'n': s.favorites.length}))),
      DropdownMenuItem(value: 'recent', child: Text(tr('Sist sett ({n})', {'n': s.recent.length}))),
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
    final value = seen.contains(_filter) ? _filter : 'home';
    final isCategory = !const {'home', 'all', 'fav', 'recent'}.contains(value);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: DropdownButton<String>(
              isExpanded: true,
              value: value,
              items: items,
              onChanged: (v) => _select(v ?? 'home'),
            ),
          ),
          if (isCategory)
            IconButton(
              tooltip: s.isFavoriteCategory(value) ? tr('Fjern fra toppen') : tr('Legg øverst'),
              icon: Icon(s.isFavoriteCategory(value) ? Icons.star : Icons.star_border),
              onPressed: () => unawaited(s.toggleFavoriteCategory(value)),
            ),
        ],
      ),
    );
  }
}
