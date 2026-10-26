import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/names.dart';
import '../core/session.dart';
import '../core/source.dart';
import '../l10n/dates.dart';
import '../l10n/tr.dart';
import '../theme.dart';
import 'channel_card.dart';
import 'motion.dart';
import 'vod_player_page.dart';

/// hvor mange dager før [now] [t] er (0 = i dag)
int _daysAgo(DateTime t, DateTime now) {
  final day = DateTime(t.year, t.month, t.day);
  final today = DateTime(now.year, now.month, now.day);
  // timer og avrunding: et døgn med sommertid eller vintertid er 23 eller 25 timer
  return (today.difference(day).inHours / 24).round();
}

/// «I dag», «I går» eller «Lørdag 24. oktober»
String archiveDay(DateTime t, DateTime now) => switch (_daysAgo(t, now)) {
      0 => tr('I dag'),
      1 => tr('I går'),
      _ => longDate(t),
    };

/// «i går 20:00–21:00», «lørdag 24. oktober 20:00–21:00» (engelsk: «Saturday 24 October 20:00–21:00»)
String archiveWhen(EpgEntry e, DateTime now) {
  final time = '${hhmm(e.start)}–${hhmm(e.stop)}';
  switch (_daysAgo(e.start, now)) {
    case 0:
      return tr('i dag {time}', {'time': time});
    case 1:
      return tr('i går {time}', {'time': time});
  }
  // ukedagen med liten bokstav midt i en setning på norsk, men ikke på engelsk
  final date = longDate(e.start);
  final day = appLanguage == 'en' ? date : '${date[0].toLowerCase()}${date.substring(1)}';
  return '$day $time';
}

/// for «fortsett der du slapp»: kanalen og når programmet begynte
String archiveKey(Channel ch, EpgEntry e) => 'arkiv:${ch.id}:${e.start.millisecondsSinceEpoch ~/ 1000}';

/// Et program fra arkivet, klart for spilleren.
VodPlayItem archivePlayItem(Channel ch, EpgEntry e, ArchiveClip clip, {DateTime? now}) {
  final name = nameParts(ch.name).main;
  return VodPlayItem(
    key: archiveKey(ch, e),
    title: e.title.isEmpty ? name : e.title,
    subtitle: '$name · ${archiveWhen(e, now ?? DateTime.now())}',
    archive: clip,
  );
}

/// Programmene, i rekkefølge, så spilleren kan gå videre til det neste.
Future<List<VodPlayItem>> archiveItems(Session s, Channel ch, List<EpgEntry> programs) async {
  final now = DateTime.now();
  return [for (final e in programs) archivePlayItem(ch, e, await s.archiveClip(ch, e), now: now)];
}

/// TV-arkivet for en kanal: det som har gått de siste dagene, nyeste øverst og dag for dag. Trykk på et program for å
/// se det; det som går nå, ses fra start.
class ArchivePage extends StatefulWidget {
  const ArchivePage({super.key, required this.session, required this.channel});

  final Session session;
  final Channel channel;

  @override
  State<ArchivePage> createState() => _ArchivePageState();
}

class _ArchivePageState extends State<ArchivePage> {
  late Future<List<EpgEntry>> _programs = widget.session.archive(widget.channel);
  bool _opening = false;

  Session get s => widget.session;
  Channel get ch => widget.channel;

  void _reload() => setState(() => _programs = s.archive(ch));

  Future<void> _play(List<EpgEntry> all, EpgEntry chosen) async {
    if (_opening) return;
    final playable = [for (final e in all) if (e.inArchive) e];
    final index = playable.indexOf(chosen);
    if (index < 0) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _opening = true);
    try {
      final items = await archiveItems(s, ch, playable);
      if (!mounted) return;
      await nav.push(fadeRoute<void>((_) => VodPlayerPage(session: s, items: items, index: index)));
    } on SourceException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      // tilbake fra spilleren: streken for det du har sett, tegnes på nytt
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = ch.archiveDays;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            ChannelLogo(url: s.source?.logoUrl(ch.icon), name: ch.name, width: 52, height: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(nameParts(ch.name).main,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    days == 1 ? tr('TV-arkiv · 1 dag tilbake') : tr('TV-arkiv · {n} dager tilbake', {'n': days}),
                    style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(tooltip: tr('Hent på nytt'), icon: const Icon(Icons.refresh), onPressed: _reload),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<List<EpgEntry>>(
        future: _programs,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          final error = snap.error;
          if (error != null) {
            return _message(
              error is SourceException ? error.message : tr('Fikk ikke hentet arkivet.'),
              isError: true,
              retry: true,
            );
          }
          final list = snap.data ?? const <EpgEntry>[];
          if (list.isEmpty) return _message(tr('Ingen programmer i arkivet ennå.'));
          return _list(list);
        },
      ),
    );
  }

  Widget _message(String text, {bool isError = false, bool retry = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                textAlign: TextAlign.center, style: TextStyle(color: isError ? scheme.error : scheme.onSurfaceVariant)),
            if (retry) ...[
              const SizedBox(height: 12),
              FilledButton(onPressed: _reload, child: Text(tr('Prøv igjen'))),
            ],
          ],
        ),
      ),
    );
  }

  Widget _list(List<EpgEntry> all) {
    final now = DateTime.now();
    final rows = <Widget>[];
    String? day;
    var first = true;
    for (final e in all.reversed) {
      final d = archiveDay(e.start, now);
      if (d != day) {
        day = d;
        rows.add(_head(d));
      }
      rows.add(_row(all, e, now, autofocus: first && e.inArchive));
      if (e.inArchive) first = false;
    }
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 4, 12, 24), children: rows),
      ),
    );
  }

  Widget _head(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 18, 12, 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _row(List<EpgEntry> all, EpgEntry e, DateTime now, {bool autofocus = false}) {
    final scheme = Theme.of(context).colorScheme;
    final live = e.isOnAt(now);
    final ok = e.inArchive;
    final seen = s.watched(archiveKey(ch, e));
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 108,
            child: Text(
              '${hhmm(e.start)}–${hhmm(e.stop)}',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(e.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                    if (live)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: FyrlysColors.live, borderRadius: BorderRadius.circular(10)),
                        child: Text(tr('Går nå'),
                            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
                      ),
                  ],
                ),
                if (e.description.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(e.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.35)),
                  ),
                if (!ok)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(tr('Ikke i arkivet'), style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                  ),
                if (ok && seen > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: SizedBox(
                      width: 160,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(value: seen, minHeight: 3),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (ok)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Icon(live ? Icons.restart_alt : Icons.play_arrow, color: scheme.primary),
            ),
        ],
      ),
    );
    final tile = Material(
      color: Colors.transparent,
      child: InkWell(
        autofocus: autofocus,
        borderRadius: BorderRadius.circular(12),
        onTap: ok ? () => unawaited(_play(all, e)) : null,
        child: body,
      ),
    );
    if (!ok) return Opacity(opacity: 0.45, child: tile);
    return Tooltip(
      message: live ? tr('Se fra start') : tr('Se programmet'),
      waitDuration: const Duration(milliseconds: 800),
      child: tile,
    );
  }
}
