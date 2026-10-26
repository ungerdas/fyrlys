import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/names.dart';
import '../core/session.dart';
import '../theme.dart';

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
    return Material(
      color: scheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _focused ? scheme.tertiary : scheme.outline, width: _focused ? 2 : 1),
      ),
      child: InkWell(
        onTap: widget.onTap,
        onFocusChange: (f) => setState(() => _focused = f),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          child: Row(
            children: [
              ChannelLogo(url: s.source?.logoUrl(ch.icon), name: ch.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        if (parts.time.isNotEmpty)
                          TextSpan(
                            text: '${parts.time}  ',
                            style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700),
                          ),
                        TextSpan(text: parts.main),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    if (parts.sub.isNotEmpty)
                      Text(parts.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: dim)
                    else if (_epg != null)
                      FutureBuilder<List<EpgEntry>>(
                        future: _epg,
                        builder: (context, snap) {
                          final now = DateTime.now();
                          final nn = nowAndNext(snap.data ?? const [], now);
                          final cur = nn.now;
                          final next = widget.showNext ? nn.next : null;
                          if (cur == null) return const SizedBox.shrink();
                          return Column(
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
                          );
                        },
                      ),
                  ],
                ),
              ),
              if (ch.number != null) Padding(padding: const EdgeInsets.only(left: 8), child: Text(ch.number!, style: dim)),
              IconButton(
                tooltip: fav ? 'Fjern fra favoritter' : 'Legg til i favoritter',
                icon: Icon(fav ? Icons.star : Icons.star_border, color: fav ? scheme.primary : scheme.onSurfaceVariant),
                onPressed: () => unawaited(s.toggleFavorite(ch)),
              ),
            ],
          ),
        ),
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
      child: logo == null
          ? initials
          : Image.network(
              logo,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (context, error, stackTrace) => initials,
            ),
    );
  }
}
