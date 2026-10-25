import 'dart:async';

import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/vod.dart';
import 'vod_player_page.dart';

/// Plakaten: bildet fra leverandøren, eller en farget flate (med navnet) når det mangler.
class Poster extends StatelessWidget {
  const Poster({super.key, required this.url, required this.title, this.radius = 10, this.showTitle = true});

  final String? url;
  final String title;
  final double radius;

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
            : Image.network(
                u,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (context, error, stackTrace) => fallback,
              ),
      ),
    );
  }
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
  int _season = 0;

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
      } else {
        _series = src.seriesInfo(item.id);
      }
    });
  }

  Future<void> _play(List<VodPlayItem> items, int index, {bool resume = true}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VodPlayerPage(session: s, items: items, index: index, resume: resume),
      ),
    );
    // hvor du slapp, og hva som er sett, kan ha endret seg
    if (mounted) setState(() {});
  }

  void _playMovie({required bool resume}) {
    final src = s.source;
    if (src == null) return;
    final sub = [item.year ?? '', ratingText(item.rating)].where((t) => t.isNotEmpty).join('  ');
    unawaited(_play(
      [VodPlayItem(key: 'film:${item.id}', title: item.name, subtitle: sub, url: src.movieUrl(item))],
      0,
      resume: resume,
    ));
  }

  List<VodPlayItem> _episodes(SeriesInfo info, Season season) {
    final src = s.source;
    if (src == null) return const [];
    final name = info.name.isNotEmpty ? info.name : item.name;
    return [
      for (final e in season.episodes)
        VodPlayItem(
          key: 'episode:${e.id}',
          title: name,
          subtitle: [episodeCode(season.number, e.number), e.title].where((t) => t.isNotEmpty).join(' '),
          url: src.episodeUrl(e),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(item.name, overflow: TextOverflow.ellipsis)),
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

  /// Plakat til venstre og teksten til høyre (under hverandre på smale skjermer).
  Widget _header({required String? cover, required String title, required String meta, required List<Widget> below}) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        if (meta.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(meta, style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ...below,
      ],
    );
    final poster = Poster(url: s.source?.logoUrl(cover), title: title);
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: SizedBox(width: 180, child: poster)),
          const SizedBox(height: 16),
          text,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 220, child: poster),
        const SizedBox(width: 28),
        Expanded(child: text),
      ],
    );
  }

  Widget _paragraph(String text) => Padding(
        padding: const EdgeInsets.only(top: 14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Text(text, style: const TextStyle(height: 1.45)),
        ),
      );

  Widget _movieBody(MovieInfo m) {
    final scheme = Theme.of(context).colorScheme;
    final key = 'film:${item.id}';
    final resumeAt = s.resumeAt(key);
    final meta = [
      m.year.isNotEmpty ? m.year : (item.year ?? ''),
      m.genre,
      m.duration,
      ratingText(item.rating),
    ].where((t) => t.isNotEmpty).join('  ·  ');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: _header(
        cover: item.icon,
        title: item.name,
        meta: meta,
        below: [
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  autofocus: true,
                  onPressed: () => _playMovie(resume: true),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(resumeAt == null ? 'Spill av' : 'Fortsett fra ${formatDuration(resumeAt)}'),
                ),
                if (resumeAt != null)
                  OutlinedButton.icon(
                    onPressed: () => _playMovie(resume: false),
                    icon: const Icon(Icons.replay),
                    label: const Text('Fra begynnelsen'),
                  ),
              ],
            ),
          ),
          if (m.plot.isNotEmpty) _paragraph(m.plot),
          if (m.cast.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Skuespillere: ${m.cast}', style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          if (m.director.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Regi: ${m.director}', style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }

  Widget _seriesBody(SeriesInfo info) {
    final scheme = Theme.of(context).colorScheme;
    final name = info.name.isNotEmpty ? info.name : item.name;
    final meta = [
      info.year.isNotEmpty ? info.year : (item.year ?? ''),
      info.genre,
      ratingText(info.rating ?? item.rating),
    ].where((t) => t.isNotEmpty).join('  ·  ');
    final plot = info.plot.isNotEmpty ? info.plot : item.plot;
    final seasons = info.seasons;
    final index = _season < seasons.length ? _season : 0;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          sliver: SliverToBoxAdapter(
            child: _header(
              cover: info.cover ?? item.icon,
              title: name,
              meta: meta,
              below: [
                if (plot.isNotEmpty) _paragraph(plot),
                if (seasons.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Text('Serien har ingen episoder hos leverandøren.',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Wrap(
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
              ],
            ),
          ),
        ),
        if (seasons.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            sliver: SliverList.builder(
              itemCount: seasons[index].episodes.length,
              itemBuilder: (context, i) => _episodeRow(info, seasons[index], i),
            ),
          ),
      ],
    );
  }

  Widget _episodeRow(SeriesInfo info, Season season, int i) {
    final scheme = Theme.of(context).colorScheme;
    final e = season.episodes[i];
    final code = episodeCode(season.number, e.number);
    final seen = s.watched('episode:${e.id}');
    final image = s.source?.logoUrl(e.image);
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 160,
        height: 90,
        child: image == null
            ? ColoredBox(
                color: scheme.surfaceContainerHighest,
                child: Icon(Icons.play_circle_outline, color: scheme.onSurfaceVariant, size: 36),
              )
            : Image.network(
                image,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => ColoredBox(color: scheme.surfaceContainerHighest),
              ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
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
                          TextSpan(text: e.title.isNotEmpty ? e.title : 'Episode ${e.number ?? i + 1}'),
                        ]),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      if (e.plot.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(e.plot,
                              maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant)),
                        ),
                      if (e.duration.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(e.duration, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                        ),
                      if (seen > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(value: seen, minHeight: 3, backgroundColor: scheme.outline),
                          ),
                        ),
                    ],
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
