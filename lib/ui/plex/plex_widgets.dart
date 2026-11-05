// Kortene og radene i Plex-fanen: plakater med sett/igjen/framdrift, brede kort for «Fortsett å se», og rader bortover.

import 'package:flutter/material.dart';

import '../../core/plex/plex_account.dart';
import '../../core/plex/plex_models.dart';
import '../../core/vod.dart' show ratingText;
import '../../l10n/tr.dart';
import '../motion.dart';
import '../net_image.dart';
import '../vod_detail_page.dart' show Poster;

/// Plakaten til [item] i rutenett og rader (Plex skalerer den).
String? plexPoster(PlexAccount plex, PlexItem item) => plex.image(item.poster, width: 300, height: 450);

/// En plakat med navn og år (eller episoden), et merke når den er sett, hvor mange episoder som er igjen, og en strek
/// for hvor langt du har kommet.
class PlexPosterCard extends StatefulWidget {
  const PlexPosterCard({super.key, required this.plex, required this.item, required this.onTap});

  final PlexAccount plex;
  final PlexItem item;
  final VoidCallback onTap;

  @override
  State<PlexPosterCard> createState() => _PlexPosterCardState();
}

class _PlexPosterCardState extends State<PlexPosterCard> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final it = widget.item;
    final line = [it.cardLine, if (it.type == PlexType.movie) ratingText(it.rating)].where((t) => t.isNotEmpty).join('  ');
    final progress = it.progress;
    return Lift(
      up: _focused || _hovered,
      scale: 1.04,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
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
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _focused ? scheme.tertiary : Colors.transparent, width: 3),
                  ),
                  child: Stack(
                    children: [
                      Poster(url: plexPoster(widget.plex, it), title: it.cardTitle, showTitle: false),
                      if (it.watched)
                        const Positioned(top: 6, right: 6, child: _WatchedMark())
                      else if (it.isShowLike && it.unwatched > 0 && it.viewedLeafCount > 0)
                        Positioned(top: 6, right: 6, child: _CountMark(count: it.unwatched)),
                      if (progress != null)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 4,
                            backgroundColor: const Color(0x99000000),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  it.cardTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5, height: 1.25),
                ),
                if (line.isNotEmpty)
                  Text(line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ✓ i hjørnet: sett ferdig.
class _WatchedMark extends StatelessWidget {
  const _WatchedMark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tr('Sett'),
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
        child: Icon(Icons.check, size: 16, color: scheme.onPrimary),
      ),
    );
  }
}

/// Episodene som er igjen i en serie du har begynt på.
class _CountMark extends StatelessWidget {
  const _CountMark({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: count == 1 ? tr('1 episode igjen') : tr('{n} episoder igjen', {'n': count}),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(10)),
        child: Text('$count', style: TextStyle(color: scheme.onPrimary, fontSize: 12, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

/// Et bredt kort i «Fortsett å se»: bildet fra episoden (eller filmens bakgrunn), navnet, episoden og hvor langt du
/// har kommet.
class PlexWideCard extends StatefulWidget {
  const PlexWideCard({super.key, required this.plex, required this.item, required this.onTap, this.onInfo});

  final PlexAccount plex;
  final PlexItem item;
  final VoidCallback onTap;

  /// til detaljsiden (filmen eller serien)
  final VoidCallback? onInfo;

  @override
  State<PlexWideCard> createState() => _PlexWideCardState();
}

class _PlexWideCardState extends State<PlexWideCard> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final it = widget.item;
    final image = widget.plex.image(
      it.type == PlexType.episode ? (it.thumb ?? it.grandparentArt) : (it.art ?? it.thumb),
      width: 480,
      height: 270,
    );
    final left = it.duration - it.viewOffset;
    final status = it.progress == null
        ? tr('Neste episode')
        : (left.inMinutes >= 1 ? tr('{n} min igjen', {'n': left.inMinutes}) : tr('Snart ferdig'));
    final line = [if (it.type == PlexType.episode) it.code, status].where((t) => t.isNotEmpty).join(' · ');
    final fallback = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(child: Icon(Icons.movie_outlined, size: 36, color: scheme.onSurfaceVariant)),
    );
    return SizedBox(
      width: 280,
      child: Lift(
        up: _focused || _hovered,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onLongPress: widget.onInfo,
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
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _focused ? scheme.tertiary : Colors.transparent, width: 3),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            if (image != null) NetImage(image, decodeWidth: 280, fallback: fallback) else fallback,
                            const Center(
                              child: DecoratedBox(
                                decoration: BoxDecoration(color: Color(0x66000000), shape: BoxShape.circle),
                                child: Padding(
                                  padding: EdgeInsets.all(8),
                                  child: Icon(Icons.play_arrow, color: Colors.white, size: 30),
                                ),
                              ),
                            ),
                            if (it.progress case final p?)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: LinearProgressIndicator(
                                  value: p,
                                  minHeight: 4,
                                  backgroundColor: const Color(0x99000000),
                                ),
                              ),
                            if (widget.onInfo != null)
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Material(
                                  color: const Color(0x8C000000),
                                  shape: const CircleBorder(),
                                  child: IconButton(
                                    tooltip: it.type == PlexType.episode ? tr('Om serien') : tr('Om filmen'),
                                    iconSize: 18,
                                    visualDensity: VisualDensity.compact,
                                    color: Colors.white,
                                    icon: const Icon(Icons.info_outline),
                                    onPressed: widget.onInfo,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    it.cardTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  Text(
                    it.type == PlexType.episode && it.title.isNotEmpty ? '$line · ${it.title}' : line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
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

/// En rad bortover med overskrift (startsiden i Plex-fanen og «Mer som dette»), med «Vis alle» når [onAll] er satt.
class PlexRow extends StatelessWidget {
  const PlexRow({
    super.key,
    required this.title,
    required this.height,
    required this.itemWidth,
    required this.count,
    required this.builder,
    this.padding = 16,
    this.onAll,
    this.allKey,
  });

  final String title;
  final double height;
  final double itemWidth;
  final int count;
  final Widget Function(BuildContext context, int index) builder;
  final double padding;

  /// hele raden
  final VoidCallback? onAll;

  /// nøkkelen til «Vis alle» (testene)
  final Key? allKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(padding, onAll == null ? 18 : 10, onAll == null ? padding : padding - 8,
              onAll == null ? 10 : 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
              if (onAll != null)
                TextButton(
                  key: allKey,
                  onPressed: onAll,
                  child: Text(tr('Vis alle'), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: padding - 3),
            itemCount: count,
            separatorBuilder: (context, i) => const SizedBox(width: 10),
            itemBuilder: (context, i) => SizedBox(width: itemWidth, child: builder(context, i)),
          ),
        ),
      ],
    );
  }
}

/// En feil eller tom side, med «Prøv igjen».
class PlexMessage extends StatelessWidget {
  const PlexMessage({super.key, required this.text, this.error = false, this.onRetry, this.extra});

  final String text;
  final bool error;
  final VoidCallback? onRetry;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(text,
                  textAlign: TextAlign.center, style: TextStyle(color: error ? scheme.error : scheme.onSurfaceVariant)),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: onRetry, child: Text(tr('Prøv igjen'))),
            ],
            if (extra case final e?) e,
          ],
        ),
      ),
    );
  }
}

/// En liten pil som flytter et bibliotek opp eller ned (som i «Dine kategorier» på TV-siden); [onPressed] null:
/// øverst eller nederst.
Widget plexMoveButton({required Key key, required bool up, required VoidCallback? onPressed}) => IconButton(
      key: key,
      tooltip: up ? tr('Flytt opp') : tr('Flytt ned'),
      onPressed: onPressed,
      icon: Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 18),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    );
