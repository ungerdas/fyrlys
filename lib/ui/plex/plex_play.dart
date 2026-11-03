// Avspilling fra Plex: filmen eller episoden blir noe filmspilleren kan spille (med Plex sine hoder, der du slapp, og
// beskjed til Plex om hvor du er), og spilleren går videre til neste sesong når en er ferdig.

import 'package:flutter/material.dart';

import '../../core/failure.dart' show httpStatus;
import '../../core/play_info.dart';
import '../../core/plex/plex_account.dart';
import '../../core/plex/plex_api.dart';
import '../../core/plex/plex_models.dart';
import '../../core/session.dart';
import '../../core/vod.dart' show ratingText;
import '../../l10n/tr.dart';
import '../motion.dart';
import '../vod_player_page.dart';

/// [item] som noe å spille (null når den ikke har noen fil, eller serveren ikke har svart).
VodPlayItem? plexPlayItem(PlexAccount plex, PlexItem item) {
  final api = plex.api;
  final part = item.part;
  if (api == null || part == null) return null;
  final episode = item.type == PlexType.episode;
  return VodPlayItem(
    key: 'plex:${plex.server?.id ?? ''}:${item.ratingKey}',
    title: episode && item.grandparentTitle.isNotEmpty ? item.grandparentTitle : item.title,
    subtitle: episode
        ? [item.code, item.title].where((t) => t.isNotEmpty).join(' ')
        : [if (item.year != null) '${item.year}', ratingText(item.rating)].where((t) => t.isNotEmpty).join('  '),
    url: api.file(part),
    tech: item.tech,
    headers: api.headers,
    startAt: item.resumeAt,
    report: PlexReporter(plex, item.ratingKey),
    extras: () => plexExtras(plex, item.ratingKey),
    explain: (url) => plexExplain(plex, url),
  );
}

/// Undertekstfilene og intro/rulletekst (hentes når den begynner å spille).
Future<PlayExtras> plexExtras(PlexAccount plex, String ratingKey) async {
  final full = await plex.run((api) => api.metadata(ratingKey, markers: true));
  final api = plex.api;
  return PlayExtras(
    subtitles: [
      if (api != null)
        for (final s in full.externalSubtitles)
          // VobSub er to filer (.idx og .sub): avspilleren kan ikke hente den fra en adresse
          if (s.codec != 'vobsub')
            ExternalSubtitle(
              url: api.stream(s.key!),
              title: s.title.isNotEmpty ? s.title : (s.language.isNotEmpty ? s.language : tr('Undertekst')),
              language: s.languageCode,
            ),
    ],
    markers: [
      for (final m in full.markers)
        if ((m.type == 'intro' || m.type == 'credits') && m.end > m.start)
          SkipMarker(credits: m.type == 'credits', start: m.start, end: m.end),
    ],
  );
}

/// Hvorfor filen ikke kunne spilles, ut fra hva serveren svarer på den (null: serveren gir filen, så det var noe i
/// selve filen; da står det avspilleren sa).
Future<String?> plexExplain(PlexAccount plex, String url) async {
  final api = plex.api;
  if (api == null) return null;
  final code = await httpStatus(plex.client, url, api.headers);
  debugPrint('Plex: filen svarer ${code ?? 'ikke'}');
  if (code == null) {
    return tr('Fikk ikke kontakt med Plex-serveren. Er den på, og er du på nett?');
  }
  if (code == 401 || code == 403) {
    return tr('Plex-serveren godtar ikke innloggingen (HTTP {code}). Koble til Plex på nytt i innstillingene.',
        {'code': code});
  }
  if (code == 404) {
    return tr('Filen finnes ikke på Plex-serveren (HTTP 404). Er disken den ligger på, koblet til?');
  }
  if (code >= 400) return tr('Plex-serveren svarte med en feil (HTTP {code}).', {'code': code});
  return null;
}

/// Episodene i sesongene etter sesong [season] i serien [show] (ekstramateriale i sesong 0 hoppes over), en sesong
/// om gangen: filmspilleren spør når den kommer til den siste episoden.
Future<List<VodPlayItem>> Function(VodPlayItem last) plexNextSeasons(PlexAccount plex, String show, int season) {
  List<PlexItem>? seasons;
  var current = season;
  return (last) async {
    final list = seasons ??= ([...await plex.run((api) => api.children(show))]
      ..sort((a, b) => (a.index ?? 0).compareTo(b.index ?? 0)));
    for (final s in list) {
      final n = s.index ?? 0;
      if (n <= current || n == 0) continue;
      current = n;
      final episodes = await plex.run((api) => api.children(s.ratingKey));
      final items = [
        for (final e in episodes)
          if (plexPlayItem(plex, e) case final p?) p,
      ];
      if (items.isNotEmpty) return items;
    }
    return const <VodPlayItem>[];
  };
}

void _snack(BuildContext context, String text) => ScaffoldMessenger.maybeOf(context)
  ?..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 4)));

/// Åpner filmspilleren på [items][index] (resten av lista kan spilles etterpå). [more]: det som kommer etter (neste
/// sesong). Fullføres når spilleren lukkes.
Future<void> openPlexPlayer(
  BuildContext context,
  Session s,
  List<PlexItem> items,
  int index, {
  bool resume = true,
  Future<List<VodPlayItem>> Function(VodPlayItem last)? more,
}) async {
  final plex = s.plex;
  final nav = Navigator.of(context);
  var wanted = items[index];
  // kort uten filinfo (f.eks. fra en rad på startsiden): hentes først
  if (wanted.part == null) {
    try {
      wanted = await plex.run((api) => api.metadata(wanted.ratingKey));
    } on PlexException catch (e) {
      if (context.mounted) _snack(context, e.message);
      return;
    }
  }
  final first = plexPlayItem(plex, wanted);
  if (first == null) {
    if (context.mounted) _snack(context, tr('Fant ikke filen på Plex-serveren.'));
    return;
  }
  final list = <VodPlayItem>[];
  var at = 0;
  for (var i = 0; i < items.length; i++) {
    if (i == index) {
      at = list.length;
      list.add(first);
    } else if (plexPlayItem(plex, items[i]) case final p?) {
      list.add(p);
    }
  }
  await nav.push(fadeRoute<void>(
    (_) => VodPlayerPage(session: s, items: list, index: at, resume: resume, more: more),
  ));
}

/// Spiller [item] fra en rad eller fra søket: filmen, eller episoden med resten av sesongen etter (og neste sesong
/// når den er ferdig). Fullføres når spilleren lukkes.
Future<void> playPlexItem(BuildContext context, Session s, PlexItem item, {bool resume = true}) async {
  final plex = s.plex;
  if (item.type != PlexType.episode) {
    await openPlexPlayer(context, s, [item], 0, resume: resume);
    return;
  }
  var episodes = [item];
  var index = 0;
  final season = item.parentRatingKey;
  if (season != null) {
    try {
      final list = await plex.run((api) => api.children(season));
      final i = list.indexWhere((e) => e.ratingKey == item.ratingKey);
      if (i >= 0) {
        episodes = list;
        index = i;
      }
    } on PlexException catch (e) {
      // bare denne episoden
      debugPrint('Plex: fant ikke resten av sesongen ($e)');
    }
  }
  if (!context.mounted) return;
  final show = item.grandparentRatingKey;
  final number = item.parentIndex;
  await openPlexPlayer(
    context,
    s,
    episodes,
    index,
    resume: resume,
    more: show == null || number == null ? null : plexNextSeasons(plex, show, number),
  );
}
