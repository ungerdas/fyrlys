import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/source.dart';
import '../core/vod.dart';
import 'motion.dart';
import 'net_image.dart';
import 'vod_browser.dart';
import 'vod_player_page.dart';

/// Plakaten: bildet fra leverandøren, eller en farget flate (med navnet) når det mangler.
class Poster extends StatelessWidget {
  const Poster({
    super.key,
    required this.url,
    required this.title,
    this.radius = 10,
    this.showTitle = true,
    this.decodeWidth = 240,
  });

  final String? url;
  final String title;
  final double radius;

  /// omtrent hvor bred plakaten vises (bildet pakkes ut i den størrelsen)
  final double decodeWidth;

  /// navnet på flata når bildet mangler (i rutenettet står navnet under plakaten, så der vises et ikon)
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(10),
      child: showTitle
          ? Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w700),
            )
          : Icon(Icons.movie_outlined, size: 40, color: scheme.onSurfaceVariant),
    );
    final u = url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: u == null
            ? fallback
            : NetImage(u, decodeWidth: decodeWidth, fallback: fallback),
      ),
    );
  }
}

/// Filmen som noe å spille, med plass i «Fortsett å se».
VodPlayItem? movieItem(Session s, VodItem item) {
  final src = s.source;
  if (src == null) return null;
  final clean = cleanTitle(item.name);
  final sub = [item.year ?? clean.year ?? '', ratingText(item.rating)].where((t) => t.isNotEmpty).join('  ');
  return VodPlayItem(
    key: 'film:${item.id}',
    title: clean.title,
    subtitle: sub,
    url: src.movieUrl(item),
    continueAs: ContinueItem(
      key: 'film:${item.id}',
      kind: VodKind.movies,
      id: item.id,
      title: item.name,
      icon: item.icon,
      subtitle: sub,
      ext: item.ext,
    ),
  );
}

/// Episodene i en sesong, i rekkefølge, så spilleren kan gå videre til neste.
List<VodPlayItem> seasonItems(Session s, SeriesInfo info, Season season, VodItem series) {
  final src = s.source;
  if (src == null) return const [];
  final name = info.name.isNotEmpty ? info.name : series.name;
  return [
    for (final e in season.episodes)
      () {
        final sub = [episodeCode(season.number, e.number), e.title].where((t) => t.isNotEmpty).join(' ');
        return VodPlayItem(
          key: 'episode:${e.id}',
          title: name,
          subtitle: sub,
          url: src.episodeUrl(e),
          continueAs: ContinueItem(
            key: 'serie:${series.id}',
            kind: VodKind.series,
            id: series.id,
            title: name,
            icon: info.cover ?? series.icon,
            subtitle: sub,
            ext: e.ext,
            episodeId: e.id,
            season: season.number,
          ),
        );
      }(),
  ];
}

/// Spiller det du holdt på med fra «Fortsett å se»: filmen der du slapp, eller episoden i serien (med resten av
/// sesongen etter). Finnes ikke episoden lenger, åpnes serien.
Future<void> playContinue(BuildContext context, Session s, ContinueItem c) async {
  final src = s.source;
  if (src == null) return;
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final series = VodItem(id: c.id, name: c.title, icon: c.icon, ext: c.ext);
  if (c.kind == VodKind.movies) {
    final item = movieItem(s, series);
    if (item == null) return;
    await nav.push(fadeRoute<void>((_) => VodPlayerPage(session: s, items: [item])));
    return;
  }
  try {
    final info = await src.seriesInfo(c.id);
    for (final season in info.seasons) {
      if (season.number != c.season) continue;
      final i = season.episodes.indexWhere((e) => e.id == c.episodeId);
      if (i < 0) break;
      await nav.push(fadeRoute<void>(
        (_) => VodPlayerPage(session: s, items: seasonItems(s, info, season, series), index: i),
      ));
      return;
    }
  } on SourceException catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.message)));
    return;
  }
  await nav.push(MaterialPageRoute<void>(builder: (_) => VodDetailPage(session: s, kind: VodKind.series, item: series)));
}

/// En film eller en serie: plakat, info og handling. Filmen spilles herfra (eller fortsettes der du slapp);
/// serien har sesongene og episodene.
class VodDetailPage extends StatefulWidget {
  const VodDetailPage({super.key, required this.session, required this.kind, required this.item});

  final Session session;
  final VodKind kind;
  final VodItem item;

  @override
  State<VodDetailPage> createState() => _VodDetailPageState();
}

class _VodDetailPageState extends State<VodDetailPage> {
  Future<MovieInfo>? _movie;
  Future<SeriesInfo>? _series;

  /// «Mer fra samme kategori» (filmer), og navnet på kategorien
  Future<({String name, List<VodItem> items})>? _similar;

  /// sesongen du har valgt (null: den med episoden du er på, ellers den første)
  int? _season;

  Session get s => widget.session;
  VodItem get item => widget.item;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final src = s.source;
    if (src == null) return;
    setState(() {
      if (widget.kind == VodKind.movies) {
        _movie = src.movieInfo(item.id);
        _similar ??= _loadSimilar();
      } else {
        _series = src.seriesInfo(item.id);
      }
    });
  }

  Future<({String name, List<VodItem> items})> _loadSimilar() async {
    final src = s.source;
    final cat = item.categoryId;
    if (src == null || cat.isEmpty) return (name: '', items: const <VodItem>[]);
    try {
      final page = await src.vodPage(widget.kind, category: cat);
      final catalog = await src.vodCatalog(widget.kind);
      var name = '';
      for (final c in catalog.categories) {
        if (c.id == cat) name = c.name;
      }
      return (name: name, items: [for (final i in page.items) if (i.id != item.id) i].take(24).toList());
    } on Object {
      return (name: '', items: const <VodItem>[]);
    }
  }

  Future<void> _play(List<VodPlayItem> items, int index, {bool resume = true}) async {
    await Navigator.of(context).push(
      fadeRoute<void>((_) => VodPlayerPage(session: s, items: items, index: index, resume: resume)),
    );
    // hvor du slapp, og hva som er sett, kan ha endret seg
    if (mounted) setState(() {});
  }

  void _playMovie({required bool resume}) {
    final item = movieItem(s, widget.item);
    if (item == null) return;
    unawaited(_play([item], 0, resume: resume));
  }

  List<VodPlayItem> _episodes(SeriesInfo info, Season season) => seasonItems(s, info, season, item);

  /// Episoden «Spill av» på seriesiden starter: den du holder på med (fra «Fortsett å se»), ellers den første
  /// (ekstramateriale i «sesong 0» bare hvis det ikke finnes noe annet).
  ({int season, int episode, Duration? at, bool current})? _startEpisode(SeriesInfo info) {
    final seasons = info.seasons;
    for (final c in s.continueItems) {
      if (c.key != 'serie:${item.id}') continue;
      for (var si = 0; si < seasons.length; si++) {
        final ei = seasons[si].episodes.indexWhere((e) => e.id == c.episodeId);
        if (ei >= 0) return (season: si, episode: ei, at: s.resumeAt('episode:${c.episodeId}'), current: true);
      }
    }
    int? first;
    for (var si = 0; si < seasons.length; si++) {
      if (seasons[si].episodes.isEmpty) continue;
      first ??= si;
      if (int.tryParse(seasons[si].number) != 0) return (season: si, episode: 0, at: null, current: false);
    }
    return first == null ? null : (season: first, episode: 0, at: null, current: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        leading: Padding(
          padding: const EdgeInsets.all(6),
          child: Material(
            color: const Color(0x66000000),
            shape: const CircleBorder(),
            child: IconButton(
              tooltip: 'Tilbake',
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      ),
      body: widget.kind == VodKind.movies
          ? FutureBuilder<MovieInfo>(future: _movie, builder: (context, snap) => _loaded(snap, (m) => _movieBody(m)))
          : FutureBuilder<SeriesInfo>(future: _series, builder: (context, snap) => _loaded(snap, (i) => _seriesBody(i))),
    );
  }

  Widget _loaded<T>(AsyncSnapshot<T> snap, Widget Function(T data) body) {
    final scheme = Theme.of(context).colorScheme;
    if (snap.hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${snap.error}', textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Prøv igjen')),
            ],
          ),
        ),
      );
    }
    final data = snap.data;
    if (data == null) return const Center(child: CircularProgressIndicator());
    return body(data);
  }

  double get _pad => MediaQuery.sizeOf(context).width >= 760 ? 40 : 18;

  Widget _paragraph(String text, {double top = 16}) => Padding(
        padding: EdgeInsets.only(top: top),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Text(text, style: const TextStyle(height: 1.5, fontSize: 15)),
        ),
      );

  Widget _credits(String cast, String director) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(color: scheme.onSurfaceVariant, height: 1.4);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cast.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 12), child: Text('Skuespillere: $cast', style: style)),
          if (director.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('Regi: $director', style: style)),
        ],
      ),
    );
  }

  /// «12» → «12+», ellers som leverandøren skriver den
  static String _ageText(String age) => int.tryParse(age.trim()) != null ? '${age.trim()}+' : age.trim();

  Widget _movieBody(MovieInfo m) {
    final key = 'film:${item.id}';
    final resumeAt = s.resumeAt(key);
    final clean = cleanTitle(item.name);
    final year = m.year.isNotEmpty ? m.year : (item.year ?? clean.year ?? '');
    final chips = [
      if (year.isNotEmpty) year,
      if (m.genre.isNotEmpty) m.genre,
      if (runtimeText(m.seconds, m.duration).isNotEmpty) runtimeText(m.seconds, m.duration),
      if (ratingText(item.rating).isNotEmpty) ratingText(item.rating),
      if (m.age.trim().isNotEmpty) _ageText(m.age),
      if (m.country.isNotEmpty) m.country,
      ...m.tech.badges,
    ];
    final seen = s.watched(key);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _Hero(
            backdrop: s.source?.logoUrl(m.backdrop),
            poster: s.source?.logoUrl(item.icon),
            title: clean.title,
            tags: clean.tags,
            chips: chips,
            progress: seen > 0 && seen < 0.95 ? seen : null,
            actions: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  autofocus: true,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
                  onPressed: () => _playMovie(resume: true),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(resumeAt == null ? 'Spill av' : 'Fortsett fra ${formatDuration(resumeAt)}'),
                ),
                if (resumeAt != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
                    onPressed: () => _playMovie(resume: false),
                    icon: const Icon(Icons.replay),
                    label: const Text('Fra begynnelsen'),
                  ),
              ],
            ),
            below: [
              if (hasText(m.plot)) _paragraph(m.plot),
              _credits(m.cast, m.director),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: FutureBuilder<({String name, List<VodItem> items})>(
            future: _similar,
            builder: (context, snap) {
              final d = snap.data;
              if (d == null || d.items.isEmpty) return const SizedBox(height: 32);
              return _similarRow(d.name, d.items);
            },
          ),
        ),
      ],
    );
  }

  /// Plakater fra samme kategori, bortover.
  Widget _similarRow(String category, List<VodItem> items) {
    final pad = _pad;
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Text(
              category.isEmpty ? 'Mer som dette' : 'Mer fra ${cleanTitle(category).title}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 300,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: pad - 3),
              itemCount: items.length,
              separatorBuilder: (context, i) => const SizedBox(width: 10),
              itemBuilder: (context, i) => SizedBox(
                width: 150,
                child: PosterCard(
                  item: items[i],
                  imageUrl: s.source?.logoUrl(items[i].icon),
                  onTap: () => unawaited(Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => VodDetailPage(session: s, kind: widget.kind, item: items[i])),
                  )),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _seriesBody(SeriesInfo info) {
    final scheme = Theme.of(context).colorScheme;
    final clean = cleanTitle(info.name.isNotEmpty ? info.name : item.name);
    final year = info.year.isNotEmpty ? info.year : (item.year ?? clean.year ?? '');
    final seasons = info.seasons;
    final episodes = seasons.fold<int>(0, (n, x) => n + x.episodes.length);
    final chips = [
      if (year.isNotEmpty) year,
      if (info.genre.isNotEmpty) info.genre,
      if (seasons.length > 1) '${seasons.length} sesonger',
      if (episodes > 0) '$episodes episoder',
      if (ratingText(info.rating ?? item.rating).isNotEmpty) ratingText(info.rating ?? item.rating),
    ];
    final plot = hasText(info.plot) ? info.plot : (hasText(item.plot) ? item.plot : '');
    final start = _startEpisode(info);
    final picked = _season ?? start?.season ?? 0;
    final index = picked < seasons.length ? picked : 0;
    final pad = _pad;
    final thumbFallback = s.source?.logoUrl(info.backdrop ?? info.cover ?? item.icon);
    Widget? play;
    if (start != null) {
      final season = seasons[start.season];
      final e = season.episodes[start.episode];
      final code = episodeCode(season.number, e.number);
      final at = start.at;
      // «Fortsett S01E03» der du slapp, «Spill av S01E04» når den forrige er sett ferdig, ellers «Spill av S01E01»
      final label = at != null ? 'Fortsett $code' : 'Spill av $code';
      play = FilledButton.icon(
        autofocus: true,
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
        onPressed: () => unawaited(_play(_episodes(info, season), start.episode)),
        icon: const Icon(Icons.play_arrow),
        label: Text(label.trim()),
      );
      if (start.current && at != null) {
        // hvor du er i episoden, ved siden av knappen
        final seen = s.watched('episode:${e.id}');
        final runtime = runtimeText(e.seconds, e.duration);
        final title = episodeTitle(e.title, series: info.name.isNotEmpty ? info.name : item.name);
        play = Wrap(
          spacing: 14,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            play,
            Text(
              [
                if (title.isNotEmpty) title,
                runtime.isNotEmpty ? '${formatDuration(at)} av $runtime' : 'Stoppet ved ${formatDuration(at)}',
              ].join(' · '),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            if (seen > 0)
              SizedBox(
                width: 120,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(value: seen, minHeight: 4, backgroundColor: scheme.outline),
                ),
              ),
          ],
        );
      }
    }
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _Hero(
            backdrop: s.source?.logoUrl(info.backdrop),
            poster: s.source?.logoUrl(info.cover ?? item.icon),
            title: clean.title,
            tags: clean.tags,
            chips: chips,
            actions: play,
            below: [
              if (plot.isNotEmpty) _paragraph(plot),
              _credits(info.cast, info.director),
            ],
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 24, pad, 8),
          sliver: SliverToBoxAdapter(
            child: seasons.isEmpty
                ? Text('Serien har ingen episoder hos leverandøren.', style: TextStyle(color: scheme.onSurfaceVariant))
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < seasons.length; i++)
                        ChoiceChip(
                          label: Text('Sesong ${seasons[i].number}'),
                          selected: i == index,
                          onSelected: (_) => setState(() => _season = i),
                        ),
                    ],
                  ),
          ),
        ),
        if (seasons.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad - 8, 8, pad - 8, 32),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 760,
                mainAxisExtent: 132,
                crossAxisSpacing: 8,
                mainAxisSpacing: 4,
              ),
              itemCount: seasons[index].episodes.length,
              itemBuilder: (context, i) => _episodeRow(info, seasons[index], i, thumbFallback),
            ),
          ),
      ],
    );
  }

  Widget _episodeRow(SeriesInfo info, Season season, int i, String? fallback) {
    final scheme = Theme.of(context).colorScheme;
    final e = season.episodes[i];
    final code = episodeCode(season.number, e.number);
    final seen = s.watched('episode:${e.id}');
    final image = s.source?.logoUrl(e.image);
    final title = episodeTitle(e.title, series: info.name.isNotEmpty ? info.name : item.name);
    final runtime = runtimeText(e.seconds, e.duration);
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 192,
        height: 108,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image != null)
              NetImage(image, decodeWidth: 192, fallback: _EpisodeFallback(url: fallback))
            else
              _EpisodeFallback(url: fallback),
            // nummeret på alle, også når episoden har eget bilde
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Color(0xA6000000), Color(0x00000000)],
                ),
              ),
            ),
            Positioned(
              left: 10,
              bottom: 4,
              child: Text('${e.number ?? i + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, height: 1)),
            ),
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0x66000000), shape: BoxShape.circle),
                child: Padding(padding: EdgeInsets.all(6), child: Icon(Icons.play_arrow, color: Colors.white, size: 26)),
              ),
            ),
            if (seen > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(value: seen, minHeight: 4, backgroundColor: const Color(0x66000000)),
              ),
          ],
        ),
      ),
    );
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => unawaited(_play(_episodes(info, season), i)),
        focusColor: scheme.tertiary.withValues(alpha: 0.22),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              thumb,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        if (code.isNotEmpty)
                          TextSpan(text: '$code  ', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
                        TextSpan(text: title.isNotEmpty ? title : 'Episode ${e.number ?? i + 1}'),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    if (runtime.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(runtime, style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
                      ),
                    if (hasText(e.plot))
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(e.plot,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35)),
                        ),
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
}

/// Når episoden ikke har eget bilde: seriens bakgrunnsbilde, dempet (nummeret legges over i raden).
class _EpisodeFallback extends StatelessWidget {
  const _EpisodeFallback({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final u = url;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (u == null)
          ColoredBox(color: scheme.surfaceContainerHighest)
        else
          NetImage(u, decodeWidth: 192, fallback: ColoredBox(color: scheme.surfaceContainerHighest)),
        const ColoredBox(color: Color(0x66000000)),
      ],
    );
  }
}

/// Toppen av en film- eller serieside: stort bakgrunnsbilde (eller plakaten, uskarp) som tones ut mot bakgrunnen,
/// med plakat, tittel, merker, knapper og teksten over.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.backdrop,
    required this.poster,
    required this.title,
    required this.tags,
    required this.chips,
    this.actions,
    this.progress,
    this.below = const [],
  });

  final String? backdrop;
  final String? poster;
  final String title;

  /// merker fra navnet hos leverandøren («PRE»)
  final List<String> tags;

  /// år, sjanger, spilletid, vurdering, kvalitet …
  final List<String> chips;
  final Widget? actions;

  /// hvor langt du har sett (filmer)
  final double? progress;
  final List<Widget> below;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = theme.scaffoldBackgroundColor;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 760;
    final pad = wide ? 40.0 : 18.0;
    final heroHeight = wide ? (size.height * 0.62).clamp(380.0, 640.0).toDouble() : 300.0;
    final topBar = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final top = math.max(topBar + 12, heroHeight * (wide ? 0.30 : 0.42));

    Widget blurredPoster() {
      final p = poster;
      if (p == null) return ColoredBox(color: scheme.surfaceContainerHighest);
      return ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        // uskarp uansett: holder med et lite bilde
        child: NetImage(p, decodeWidth: 240, fallback: ColoredBox(color: scheme.surfaceContainerHighest)),
      );
    }

    final b = backdrop;
    final background = Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: heroHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (b != null)
            NetImage(b, alignment: Alignment.topCenter, decodeWidth: size.width, fallback: blurredPoster())
          else
            blurredPoster(),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bg.withValues(alpha: 0.30), bg.withValues(alpha: 0.55), bg],
                stops: const [0, 0.55, 1],
              ),
            ),
          ),
          if (wide)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [bg.withValues(alpha: 0.90), bg.withValues(alpha: 0)],
                  stops: const [0.2, 0.8],
                ),
              ),
            ),
        ],
      ),
    );

    final posterBox = Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: Column(
        children: [
          Poster(url: poster, title: title, radius: 12),
          if (progress != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: scheme.outline),
              ),
            ),
        ],
      ),
    );

    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: (wide ? theme.textTheme.headlineLarge : theme.textTheme.headlineSmall)
              ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.15),
        ),
        if (chips.isNotEmpty || tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in tags) _Badge(text: t, accent: true),
                for (final c in chips) _Badge(text: c),
              ],
            ),
          ),
        if (actions != null) Padding(padding: const EdgeInsets.only(top: 20), child: actions),
        ...below,
      ],
    );

    return Stack(
      children: [
        background,
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: heroHeight),
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, top, pad, 0),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 230, child: posterBox),
                      const SizedBox(width: 32),
                      Expanded(child: text),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 150, child: posterBox),
                      const SizedBox(height: 16),
                      text,
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

/// Et lite merke: år, sjanger, «4K» … (fremhevet for merker fra navnet, som «PRE»).
class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.accent = false});

  final String text;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent ? scheme.primary.withValues(alpha: 0.18) : scheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent ? scheme.primary.withValues(alpha: 0.7) : scheme.outline),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: accent ? FontWeight.w700 : FontWeight.w500,
          color: accent ? scheme.primary : scheme.onSurface,
        ),
      ),
    );
  }
}
