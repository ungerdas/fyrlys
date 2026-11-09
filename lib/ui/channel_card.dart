import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/names.dart';
import '../core/session.dart';
import '../l10n/tr.dart';
import '../theme.dart';
import 'motion.dart';
import 'net_image.dart';

/// Kanalkort: logo, navn (eventkanaler med klokkeslett), programmet som går nå med fremdrift, og stjerne.
class ChannelCard extends StatefulWidget {
  const ChannelCard({
    super.key,
    required this.session,
    required this.channel,
    required this.onTap,
    this.showNext = false,
  });

  final Session session;
  final Channel channel;
  final VoidCallback onTap;

  /// også programmet som kommer etterpå (startsiden; kortet trenger da litt mer høyde)
  final bool showNext;

  @override
  State<ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<ChannelCard> {
  Future<List<EpgEntry>>? _epg;
  Timer? _wait;
  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ChannelCard old) {
    super.didUpdateWidget(old);
    if (old.channel.id != widget.channel.id) _load();
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  void _load() {
    _wait?.cancel();
    final ch = widget.channel;
    // eventkanaler har kampen i navnet, og ofte ingen EPG
    if (!ch.hasEpg || nameParts(ch.name).sub.isNotEmpty) {
      _epg = null;
      return;
    }
    final s = widget.session;
    if (s.epgCached(ch.id) != null) {
      _epg = s.epg(ch.id);
      return;
    }
    // hentes først når kortet har vært framme litt, så rask rulling ikke fyller køen med det du rullet forbi
    _epg = null;
    _wait = Timer(const Duration(milliseconds: 150), () {
      if (mounted) setState(() { _epg = s.epg(ch.id); });
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final ch = widget.channel;
    final scheme = Theme.of(context).colorScheme;
    final parts = nameParts(ch.name);
    final fav = s.isFavorite(ch.id);
    final dim = TextStyle(color: scheme.onSurfaceVariant, fontSize: 13);
    final up = _focused || _hovered;
    // Navnet får to linjer når det ikke står et program under (eventkanalene har kampen i navnet, og ofte ingen
    // programinfo). Med programmet under er det én linje, ellers blir kortet for høyt.
    Widget title(int lines) => Text.rich(
          TextSpan(children: [
            if (parts.time.isNotEmpty)
              TextSpan(
                text: '${parts.time}  ',
                style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
              ),
            TextSpan(text: parts.main),
            if (ch.quality != null) qualitySpan(ch.quality!),
          ]),
          maxLines: lines,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15, height: 1.2),
        );
    final Widget details;
    if (parts.sub.isNotEmpty) {
      details = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          title(2),
          const SizedBox(height: 3),
          Text(parts.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: dim),
        ],
      );
    } else if (ch.hasEpg) {
      details = FutureBuilder<List<EpgEntry>>(
        future: _epg,
        builder: (context, snap) {
          final epg = snap.data ?? const <EpgEntry>[];
          // til programinfoen er hentet: én linje (som regel kommer det et program); ingen program nå: to
          final none = snap.connectionState == ConnectionState.done && nowAndNext(epg, DateTime.now()).now == null;
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title(none ? 2 : 1),
              if (!none) ...[const SizedBox(height: 3), _program(epg, dim)],
            ],
          );
        },
      );
    } else {
      details = Align(alignment: Alignment.centerLeft, child: title(2));
    }
    return Lift(
      up: up,
      child: Material(
        color: scheme.surface,
        clipBehavior: Clip.antiAlias,
        elevation: up ? 6 : 0,
        shadowColor: Colors.black54,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _focused ? scheme.tertiary : scheme.outline, width: _focused ? 2 : 1),
        ),
        child: InkWell(
          onTap: widget.onTap,
          onFocusChange: (f) => setState(() => _focused = f),
          onHover: (h) => setState(() => _hovered = h),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
            child: Row(
              children: [
                ChannelLogo(url: s.source?.logoUrl(ch.icon), name: ch.name),
                const SizedBox(width: 12),
                // hele navnet når musa står over (også det som ikke fikk plass)
                Expanded(
                  child: Tooltip(
                    message: ch.name,
                    waitDuration: const Duration(milliseconds: 800),
                    child: details,
                  ),
                ),
                // nummeret over stjerna, så navnet får bredden
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (ch.number != null) Text(ch.number!, style: dim.copyWith(fontSize: 12)),
                    IconButton(
                      tooltip: fav ? tr('Fjern fra favoritter') : tr('Legg til i favoritter'),
                      visualDensity: VisualDensity.compact,
                      icon: Icon(fav ? Icons.star : Icons.star_border,
                          color: fav ? scheme.primary : scheme.onSurfaceVariant),
                      onPressed: () => unawaited(s.toggleFavorite(ch)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Programmet som går nå med fremdrift (og det som kommer etterpå), tonet inn når det kommer.
  Widget _program(List<EpgEntry> epg, TextStyle dim) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final nn = nowAndNext(epg, now);
    final cur = nn.now;
    final next = widget.showNext ? nn.next : null;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, if (current != null) current],
      ),
      child: cur == null
          ? const SizedBox.shrink(key: ValueKey('ingen'))
          : Column(
              key: ValueKey('${cur.title}@${cur.start}'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cur.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: dim),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: cur.progressAt(now),
                    minHeight: 3,
                    backgroundColor: scheme.outline,
                  ),
                ),
                if (next != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      '${hhmm(next.start)}  ${next.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: dim.copyWith(fontSize: 12),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Kvaliteten etter navnet («720p», «H265», «4K»), når den ikke er den vanlige (se tidyChannelName).
InlineSpan qualitySpan(String quality) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(padding: const EdgeInsets.only(left: 6), child: QualityBadge(quality)),
    );

/// Et lite merke med kvaliteten.
class QualityBadge extends StatelessWidget {
  const QualityBadge(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: ValueKey('kvalitet:$text'),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, height: 1.2, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// Logoen fra leverandøren, eller forkortelsen av navnet hvis den mangler eller ikke lastes.
class ChannelLogo extends StatelessWidget {
  const ChannelLogo({super.key, required this.url, required this.name, this.width = 64, this.height = 48});

  final String? url;
  final String name;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final main = nameParts(name).main;
    // hele tegn, så et flagg eller en emoji foran navnet ikke deles i to
    final short = main.isEmpty ? '?' : main.characters.take(3).toString();
    final initials = Text(short, style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700));
    final logo = url;
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(5),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: FyrlysColors.logoBg, borderRadius: BorderRadius.circular(8)),
      child: logo == null ? initials : NetImage(logo, fit: BoxFit.contain, decodeWidth: width, fallback: initials),
    );
  }
}
