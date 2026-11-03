// En film eller serie fra Plex: bakgrunnsbilde, plakat, info og «Spill av»/«Fortsett», sett/ikke sett, og for serier
// sesongene og episodene (med hvor langt du har kommet i hver).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/plex/plex_account.dart';
import '../../core/plex/plex_api.dart';
import '../../core/plex/plex_models.dart';
import '../../core/session.dart';
import '../../core/vod.dart' show hasText, ratingText, runtimeText;
import '../../l10n/tr.dart';
import '../net_image.dart';
import '../vod_detail_page.dart' show DetailHero, EpisodeFallback;
import '../vod_player_page.dart' show formatDuration;
import 'plex_play.dart';
import 'plex_widgets.dart';

/// «Sesong 2», «Spesialer» (sesong 0)
String plexSeasonName(PlexItem season) {
  final n = season.index;
  if (n == 0) return tr('Spesialer');
  if (n != null) return tr('Sesong {n}', {'n': n});
  return season.title;
}

class PlexDetailPage extends StatefulWidget {
  const PlexDetailPage({super.key, required this.session, required this.item});

  final Session session;

  /// filmen eller serien; en sesong eller episode åpner serien på den sesongen
  final PlexItem item;

  @override
  State<PlexDetailPage> createState() => _PlexDetailPageState();
}

class _PlexDetailPageState extends State<PlexDetailPage> {
  PlexItem? _info;
  List<PlexItem> _seasons = const [];
  final Map<String, List<PlexItem>> _episodes = {};
  List<PlexItem> _similar = const [];
  String? _error;
  bool _busy = false;

  /// sesongen som vises (plassen i [_seasons])
  int? _season;

  Session get s => widget.session;
  PlexAccount get plex => s.plex;

  bool get _isShow => widget.item.type != PlexType.movie;

  /// filmen eller serien
  late final String _key = switch (widget.item.type) {
    PlexType.episode => widget.item.grandparentRatingKey ?? widget.item.ratingKey,
    PlexType.season => widget.item.parentRatingKey ?? widget.item.ratingKey,
    _ => widget.item.ratingKey,
  };

  /// sesongen som skal vises først (nummeret), når det ble åpnet fra en sesong eller episode
  late final int? _wanted = switch (widget.item.type) {
    PlexType.episode => widget.item.parentIndex,
    PlexType.season => widget.item.index,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final info = await plex.run((api) => api.metadata(_key, onDeck: _isShow));
      var seasons = const <PlexItem>[];
      if (_isShow) {
        seasons = [...await plex.run((api) => api.children(_key))]
          ..sort((a, b) => (a.index ?? 0).compareTo(b.index ?? 0));
      }
      if (!mounted) return;
      setState(() {
        _info = info;
        _seasons = seasons;
        _error = null;
        _season ??= _firstSeason(info, seasons);
      });
      if (_isShow) {
        await _loadEpisodes(force: true);
      } else if (_similar.isEmpty) {
        unawaited(_loadSimilar());
      }
    } on PlexException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  /// Sesongen som vises først: den du kom fra, den med episoden du skal se nå, ellers den første (ekstramateriale
  /// i sesong 0 bare når det ikke er noe annet).
  int _firstSeason(PlexItem show, List<PlexItem> seasons) {
    int find(int? n) => n == null ? -1 : seasons.indexWhere((x) => x.index == n);
    for (final n in [_wanted, show.onDeck?.parentIndex]) {
      final i = find(n);
      if (i >= 0) return i;
    }
    final i = seasons.indexWhere((x) => (x.index ?? 1) != 0);
    return i >= 0 ? i : 0;
  }

  PlexItem? get _currentSeason {
    final i = _season ?? 0;
    return i < _seasons.length ? _seasons[i] : null;
  }

  Future<void> _loadEpisodes({bool force = false}) async {
    final season = _currentSeason;
    if (season == null || (!force && _episodes.containsKey(season.ratingKey))) return;
    try {
      final list = await plex.run((api) => api.children(season.ratingKey));
      if (mounted) setState(() => _episodes[season.ratingKey] = list);
    } on PlexException catch (e) {
      if (mounted) setState(() => _error ??= e.message);
    }
  }

  Future<void> _loadSimilar() async {
    try {
      final list = await plex.run((api) => api.related(_key));
      if (mounted) setState(() => _similar = [for (final i in list) if (i.ratingKey != _key) i].take(24).toList());
    } on PlexException {
      // ingen rad
    }
  }

  void _snack(String text) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 4)));

  /// Etter avspilling: hvor du slapp og hva som er sett, hentes på nytt (Plex har fått beskjed underveis).
  Future<void> _after(Future<void> playing) async {
    await playing;
    if (mounted) await _load();
  }

  Future<void> _setWatched(PlexItem item, bool watched) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await plex.run((api) => api.setWatched(item.ratingKey, watched));
      await _load();
    } on PlexException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _playEpisodes(PlexItem season, List<PlexItem> episodes, int index, {bool resume = true}) {
    final n = season.index;
    unawaited(_after(openPlexPlayer(
      context,
      s,
      episodes,
      index,
      resume: resume,
      more: n == null ? null : plexNextSeasons(plex, _key, n),
    )));
  }

  /// Første episode i serien (når Plex ikke har en du skal se nå).
  Future<void> _playFirst() async {
    for (final season in _seasons) {
      if ((season.index ?? 1) == 0 && _seasons.length > 1) continue;
      try {
        final list = _episodes[season.ratingKey] ?? await plex.run((api) => api.children(season.ratingKey));
        if (!mounted) return;
        if (list.isNotEmpty) {
          _playEpisodes(season, list, 0, resume: false);
          return;
        }
      } on PlexException catch (e) {
        _snack(e.message);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final error = _error;
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
              tooltip: tr('Tilbake'),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      ),
      body: info == null
          ? (error != null
              ? PlexMessage(text: error, error: true, onRetry: () => unawaited(_load()))
              : const Center(child: CircularProgressIndicator()))
          : (_isShow ? _showBody(info) : _movieBody(info)),
    );
  }

  double get _pad => MediaQuery.sizeOf(context).width >= 760 ? 40 : 18;

  Widget _paragraph(String text, {double top = 16}) => Padding(
        padding: EdgeInsets.only(top: top),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Text(text, style: const TextStyle(height: 1.5, fontSize: 15)),
        ),
      );

  Widget _credits(PlexItem item) {
    final scheme = Theme.of(context).colorScheme;
    final style = TextStyle(color: scheme.onSurfaceVariant, height: 1.4);
    final cast = item.cast.take(8).join(', ');
    final directors = item.directors.take(3).join(', ');
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 820),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (cast.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(tr('Skuespillere: {cast}', {'cast': cast}), style: style),
            ),
          if (directors.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(tr('Regi: {director}', {'director': directors}), style: style),
            ),
        ],
      ),
    );
  }

  Widget _watchedButton(PlexItem item) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16)),
        onPressed: _busy ? null : () => unawaited(_setWatched(item, !item.watched)),
        icon: Icon(item.watched ? Icons.remove_done : Icons.done_all),
        label: Text(item.watched ? tr('Merk som ikke sett') : tr('Merk som sett')),
      );

  List<String> _chips(PlexItem m) => [
        if (m.year != null) '${m.year}',
        if (m.genres.isNotEmpty) m.genres.take(2).join(', '),
        if (m.type == PlexType.movie && m.duration > Duration.zero) runtimeText(m.duration.inSeconds),
        if (m.type == PlexType.show && _seasons.where((x) => (x.index ?? 1) != 0).length > 1)
          tr('{n} sesonger', {'n': _seasons.where((x) => (x.index ?? 1) != 0).length}),
        if (m.type == PlexType.show && m.leafCount == 1) tr('1 episode'),
        if (m.type == PlexType.show && m.leafCount > 1) tr('{n} episoder', {'n': m.leafCount}),
        if (ratingText(m.rating).isNotEmpty) ratingText(m.rating),
        if (m.contentRating.isNotEmpty) m.contentRating,
        ...m.tech.badges,
      ];

  Widget _movieBody(PlexItem m) {
    final resumeAt = m.resumeAt;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: DetailHero(
            backdrop: plex.image(m.backdrop, width: 1280, height: 720),
            poster: plex.image(m.thumb, width: 300, height: 450),
            title: m.title,
            tags: const [],
            chips: _chips(m),
            progress: resumeAt == null ? null : m.progress,
            actions: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  autofocus: true,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
                  onPressed: () => unawaited(_after(openPlexPlayer(context, s, [m], 0))),
                  icon: const Icon(Icons.play_arrow),
                  label: Text(resumeAt == null
                      ? tr('Spill av')
                      : tr('Fortsett fra {time}', {'time': formatDuration(resumeAt)})),
                ),
                if (resumeAt != null)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
                    onPressed: () => unawaited(_after(openPlexPlayer(context, s, [m], 0, resume: false))),
                    icon: const Icon(Icons.replay),
                    label: Text(tr('Fra begynnelsen')),
                  ),
                _watchedButton(m),
              ],
            ),
            below: [
              if (m.tagline.isNotEmpty) _paragraph(m.tagline),
              if (hasText(m.summary)) _paragraph(m.summary, top: m.tagline.isNotEmpty ? 8 : 16),
              _credits(m),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: _similar.isEmpty
              ? const SizedBox(height: 32)
              : Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 32),
                  child: PlexRow(
                    title: tr('Mer som dette'),
                    padding: _pad,
                    height: 300,
                    itemWidth: 150,
                    count: _similar.length,
                    builder: (context, i) => PlexPosterCard(
                      plex: plex,
                      item: _similar[i],
                      onTap: () => unawaited(Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => PlexDetailPage(session: s, item: _similar[i]),
                      ))),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _showBody(PlexItem show) {
    final scheme = Theme.of(context).colorScheme;
    final deck = show.onDeck;
    final season = _currentSeason;
    final episodes = season == null ? null : _episodes[season.ratingKey];
    final pad = _pad;
    Widget play;
    if (deck != null) {
      final at = deck.resumeAt;
      final code = deck.code;
      play = FilledButton.icon(
        autofocus: true,
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
        onPressed: () => unawaited(_after(playPlexItem(context, s, deck))),
        icon: const Icon(Icons.play_arrow),
        label: Text(code.isEmpty
            ? (at != null ? tr('Fortsett') : tr('Spill av'))
            : (at != null ? tr('Fortsett {code}', {'code': code}) : tr('Spill av {code}', {'code': code}))),
      );
      if (at != null) {
        play = Wrap(
          spacing: 14,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            play,
            Text(
              [
                if (deck.title.isNotEmpty) deck.title,
                tr('{time} av {length}', {'time': formatDuration(at), 'length': runtimeText(deck.duration.inSeconds)}),
              ].join(' · '),
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        );
      }
    } else {
      play = FilledButton.icon(
        autofocus: true,
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16)),
        onPressed: _seasons.isEmpty ? null : () => unawaited(_playFirst()),
        icon: const Icon(Icons.play_arrow),
        label: Text(show.watched ? tr('Se fra begynnelsen') : tr('Spill av')),
      );
    }
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: DetailHero(
            backdrop: plex.image(show.backdrop, width: 1280, height: 720),
            poster: plex.image(show.thumb, width: 300, height: 450),
            title: show.title,
            tags: const [],
            chips: _chips(show),
            actions: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [play, _watchedButton(show)],
            ),
            below: [
              if (hasText(show.summary)) _paragraph(show.summary),
              _credits(show),
            ],
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 24, pad, 8),
          sliver: SliverToBoxAdapter(
            child: _seasons.isEmpty
                ? Text(tr('Serien har ingen episoder på Plex-serveren.'), style: TextStyle(color: scheme.onSurfaceVariant))
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < _seasons.length; i++)
                        ChoiceChip(
                          avatar: _seasons[i].watched ? const Icon(Icons.check, size: 18) : null,
                          label: Text(plexSeasonName(_seasons[i])),
                          selected: i == (_season ?? 0),
                          onSelected: (_) {
                            setState(() => _season = i);
                            unawaited(_loadEpisodes());
                          },
                        ),
                    ],
                  ),
          ),
        ),
        if (season != null)
          if (episodes == null)
            const SliverToBoxAdapter(
              child: Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad - 8, 8, pad - 8, 32),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 760,
                  mainAxisExtent: 132,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 4,
                ),
                itemCount: episodes.length,
                itemBuilder: (context, i) => _episodeRow(show, season, episodes, i),
              ),
            ),
      ],
    );
  }

  Widget _episodeRow(PlexItem show, PlexItem season, List<PlexItem> episodes, int i) {
    final scheme = Theme.of(context).colorScheme;
    final e = episodes[i];
    final image = plex.image(e.thumb, width: 384, height: 216);
    final fallback = plex.image(show.backdrop, width: 384, height: 216);
    final runtime = e.duration > Duration.zero ? runtimeText(e.duration.inSeconds) : '';
    final progress = e.progress;
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 192,
        height: 108,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image != null)
              NetImage(image, decodeWidth: 192, fallback: EpisodeFallback(url: fallback))
            else
              EpisodeFallback(url: fallback),
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
              child: Text('${e.index ?? i + 1}',
                  style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, height: 1)),
            ),
            const Center(
              child: DecoratedBox(
                decoration: BoxDecoration(color: Color(0x66000000), shape: BoxShape.circle),
                child: Padding(padding: EdgeInsets.all(6), child: Icon(Icons.play_arrow, color: Colors.white, size: 26)),
              ),
            ),
            if (e.watched)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                  child: Icon(Icons.check, size: 15, color: scheme.onPrimary),
                ),
              ),
            if (progress != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: const Color(0x66000000)),
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
        onTap: () => _playEpisodes(season, episodes, i),
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
                        if (e.code.isNotEmpty)
                          TextSpan(text: '${e.code}  ', style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700)),
                        TextSpan(text: e.title.isNotEmpty ? e.title : tr('Episode {n}', {'n': e.index ?? i + 1})),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    if (runtime.isNotEmpty || e.resumeAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          [
                            if (runtime.isNotEmpty) runtime,
                            if (e.resumeAt case final at?) tr('Stoppet ved {time}', {'time': formatDuration(at)}),
                          ].join(' · '),
                          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                        ),
                      ),
                    if (hasText(e.summary))
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(e.summary,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: scheme.onSurfaceVariant, height: 1.35)),
                        ),
                      ),
                  ],
                ),
              ),
              PopupMenuButton<bool>(
                tooltip: tr('Mer'),
                icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
                onSelected: (watched) => unawaited(_setWatched(e, watched)),
                itemBuilder: (context) => [
                  if (!e.watched) PopupMenuItem(value: true, child: Text(tr('Merk som sett'))),
                  if (e.watched || e.progress != null) PopupMenuItem(value: false, child: Text(tr('Merk som ikke sett'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
