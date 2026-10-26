// Filmer og serier fra leverandøren (Xtream Codes): det appen vet om dem.

enum VodKind {
  movies('vod', 'Filmer'),
  series('series', 'Serier');

  const VodKind(this.api, this.title);

  /// navnet i Xtream-API-et (vod / series)
  final String api;
  final String title;
}

/// Rekkefølgen i lista.
enum VodSort {
  provider('', 'Leverandørens rekkefølge'),
  newest('added', 'Nyeste først'),
  name('name', 'A–Å');

  const VodSort(this.api, this.title);

  final String api;
  final String title;
}

class VodCategory {
  const VodCategory({required this.id, required this.name, this.count = 0});

  final String id;
  final String name;
  final int count;
}

class VodCatalog {
  const VodCatalog({required this.categories, required this.total});

  /// bare kategorier med noe i
  final List<VodCategory> categories;
  final int total;
}

/// En film eller en serie i lista.
class VodItem {
  const VodItem({
    required this.id,
    required this.name,
    this.categoryId = '',
    this.icon,
    this.ext = 'mp4',
    this.rating,
    this.year,
    this.plot = '',
    this.added = 0,
  });

  final String id;
  final String name;
  final String categoryId;

  /// plakaten hos leverandøren (kilden lager adressen som hentes, se TvSource.logoUrl)
  final String? icon;

  /// filtypen hos leverandøren (filmer)
  final String ext;
  final double? rating;
  final String? year;
  final String plot;

  /// når den ble lagt til (sekunder), for «nyeste først»
  final int added;
}

class VodPage {
  const VodPage({required this.items, required this.total});

  final List<VodItem> items;

  /// hvor mange det er i alt med dette filteret
  final int total;
}

class MovieInfo {
  const MovieInfo({
    this.plot = '',
    this.genre = '',
    this.year = '',
    this.duration = '',
    this.cast = '',
    this.director = '',
    this.name = '',
    this.backdrop,
    this.seconds = 0,
    this.age = '',
    this.country = '',
    this.trailer = '',
    this.tech = const MediaTech(),
  });

  final String plot;
  final String genre;
  final String year;

  /// «02:06:07» slik leverandøren skriver den; [seconds] når den er oppgitt
  final String duration;
  final int seconds;
  final String cast;
  final String director;

  /// navnet hos leverandørens filmdatabase, ofte uten merker som «[PRE]»
  final String name;

  /// stort bakgrunnsbilde (liggende)
  final String? backdrop;

  /// aldersgrense («12», «PG-13»)
  final String age;
  final String country;

  /// YouTube-id
  final String trailer;
  final MediaTech tech;
}

/// Kvaliteten leverandøren oppgir for en fil (tomt når den ikke sier noe).
class MediaTech {
  const MediaTech({this.height = 0, this.videoCodec = '', this.hdr = false, this.audioCodec = '', this.channels = 0});

  final int height;
  final String videoCodec;
  final bool hdr;
  final String audioCodec;
  final int channels;

  /// «4K», «HDR», «H.265», «5.1» …
  List<String> get badges => [
        if (height >= 2000)
          '4K'
        else if (height >= 1000)
          '1080p'
        else if (height >= 700)
          '720p'
        else if (height > 0)
          'SD',
        if (hdr) 'HDR',
        if (videoCodec.isNotEmpty) codecLabel(videoCodec),
        if (channels >= 8)
          '7.1'
        else if (channels >= 6)
          '5.1'
        else if (channels == 2)
          'Stereo',
        if (audioCodec.isNotEmpty && audioCodec.toLowerCase() != 'aac') codecLabel(audioCodec),
      ];
}

/// Kodeknavn slik folk kjenner dem.
String codecLabel(String codec) => switch (codec.trim().toLowerCase()) {
      'h264' || 'avc' => 'H.264',
      'hevc' || 'h265' => 'H.265',
      'av1' => 'AV1',
      'vp9' => 'VP9',
      'mpeg2video' => 'MPEG-2',
      'ac3' => 'Dolby Digital',
      'eac3' => 'Dolby Digital+',
      'truehd' => 'Dolby TrueHD',
      'dts' => 'DTS',
      'aac' => 'AAC',
      'mp3' => 'MP3',
      'flac' => 'FLAC',
      'opus' => 'Opus',
      final other => other.toUpperCase(),
    };

/// «2 t 6 min», «43 min»: fra sekunder, eller fra «02:06:07» når sekundene mangler.
String runtimeText(int seconds, [String duration = '']) {
  var s = seconds;
  if (s <= 0) {
    final parts = duration.trim().split(':').map(int.tryParse).toList();
    if (parts.isNotEmpty && parts.every((p) => p != null)) {
      for (final p in parts) {
        s = s * 60 + p!;
      }
    }
  }
  if (s <= 0) return duration.trim();
  final minutes = (s / 60).round();
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '$h t' : '$h t $m min';
}

final _endTag = RegExp(r'\s*[\[(]([^\[\]()]{1,24})[\])]\s*$');
final _yearOnly = RegExp(r'^(19|20)\d{2}$');

/// «Matchbox the Movie [PRE] [2026]» → tittel «Matchbox the Movie», merker [«PRE»] og året 2026.
({String title, List<String> tags, String? year}) cleanTitle(String raw) {
  var t = raw.trim();
  final tags = <String>[];
  String? year;
  while (true) {
    final m = _endTag.firstMatch(t);
    if (m == null || m.start == 0) break;
    final v = m.group(1)!.trim();
    if (_yearOnly.hasMatch(v)) {
      year ??= v;
    } else if (v.isNotEmpty) {
      tags.insert(0, v);
    }
    t = t.substring(0, m.start).trim();
  }
  return (title: t.isEmpty ? raw.trim() : t, tags: tags, year: year);
}

const _placeholders = {
  'not yet available',
  'not available',
  'no description',
  'no description available',
  'no plot',
  'no overview',
  'n/a',
  'na',
  'none',
  'null',
  'tba',
  'tbd',
  'coming soon',
  '-',
  '...',
};

/// En beskrivelse som faktisk sier noe (ikke «Not yet available» og lignende fyllord fra leverandøren).
bool hasText(String text) {
  final t = text.trim().toLowerCase().replaceAll(RegExp(r'[.!]+$'), '');
  return t.length >= 3 && !_placeholders.contains(t);
}

final _codeInTitle = RegExp(r'^.*?\bS\d{1,2}\s*E\d{1,3}\b[\s\-–:|.]*', caseSensitive: false);

/// «9-1-1 - S01E01 - Pilot» → «Pilot» (koden står ved siden av); tomt når det bare var koden.
String episodeTitle(String raw, {String series = ''}) {
  final t = raw.trim();
  final m = _codeInTitle.firstMatch(t);
  if (m != null) return t.substring(m.end).trim();
  final name = series.trim();
  if (name.isNotEmpty && t.toLowerCase().startsWith(name.toLowerCase())) {
    final rest = t.substring(name.length).replaceFirst(RegExp(r'^[\s\-–:|.]+'), '').trim();
    if (rest.isNotEmpty) return rest;
  }
  return t;
}

class Episode {
  const Episode({
    required this.id,
    required this.title,
    this.number,
    this.ext = 'mp4',
    this.image,
    this.plot = '',
    this.duration = '',
    this.seconds = 0,
  });

  final String id;
  final String title;
  final int? number;
  final String ext;
  final String? image;
  final String plot;
  final String duration;
  final int seconds;
}

class Season {
  const Season({required this.number, required this.episodes});

  /// slik leverandøren kaller den, oftest «1», «2» …
  final String number;
  final List<Episode> episodes;
}

class SeriesInfo {
  const SeriesInfo({
    required this.name,
    this.cover,
    this.backdrop,
    this.plot = '',
    this.genre = '',
    this.year = '',
    this.rating,
    this.cast = '',
    this.director = '',
    this.trailer = '',
    this.seasons = const [],
  });

  final String name;
  final String? cover;

  /// stort bakgrunnsbilde (liggende)
  final String? backdrop;
  final String plot;
  final String genre;
  final String year;
  final double? rating;
  final String cast;
  final String director;
  final String trailer;
  final List<Season> seasons;
}

/// En film eller serie i «Fortsett å se»: nok til å spille den igjen uten å lete. For en serie er det episoden
/// du er på (eller den neste, når du så en ferdig).
class ContinueItem {
  const ContinueItem({
    required this.key,
    required this.kind,
    required this.id,
    required this.title,
    this.icon,
    this.subtitle = '',
    this.ext = 'mp4',
    this.episodeId,
    this.season,
    this.at = 0,
  });

  factory ContinueItem.fromJson(Map<Object?, Object?> j) => ContinueItem(
        key: '${j['key']}',
        kind: j['kind'] == VodKind.series.api ? VodKind.series : VodKind.movies,
        id: '${j['id']}',
        title: '${j['title'] ?? ''}',
        icon: j['icon'] is String ? j['icon'] as String : null,
        subtitle: '${j['sub'] ?? ''}',
        ext: j['ext'] is String ? j['ext'] as String : 'mp4',
        episodeId: j['ep'] is String ? j['ep'] as String : null,
        season: j['season'] is String ? j['season'] as String : null,
        at: j['at'] is int ? j['at'] as int : 0,
      );

  /// `film:123` (samme som for «fortsett der du slapp») eller `serie:456`
  final String key;
  final VodKind kind;

  /// filmen eller serien
  final String id;
  final String title;
  final String? icon;

  /// for en serie: «S01E02 Tittel»
  final String subtitle;
  final String ext;
  final String? episodeId;
  final String? season;

  /// sist sett (sekunder)
  final int at;

  /// nøkkelen for hvor du slapp i det som skal spilles
  String get resumeKey => episodeId == null ? key : 'episode:$episodeId';

  ContinueItem seenNow(int seconds) => ContinueItem(
        key: key,
        kind: kind,
        id: id,
        title: title,
        icon: icon,
        subtitle: subtitle,
        ext: ext,
        episodeId: episodeId,
        season: season,
        at: seconds,
      );

  Map<String, Object?> toJson() => {
        'key': key,
        'kind': kind.api,
        'id': id,
        'title': title,
        'icon': icon,
        'sub': subtitle,
        'ext': ext,
        'ep': episodeId,
        'season': season,
        'at': at,
      };
}

/// «S01E02»; tomt når noe mangler.
String episodeCode(String season, int? episode) {
  final s = int.tryParse(season);
  if (s == null || episode == null) return '';
  return 'S${s.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
}

/// «★ 7,5»
String ratingText(double? rating) {
  if (rating == null || rating <= 0) return '';
  final text = rating == rating.roundToDouble() ? rating.toStringAsFixed(0) : rating.toStringAsFixed(1);
  return '★ ${text.replaceAll('.', ',')}';
}

/// Lister filtreres og sorteres i appen (leverandøren gir hele lista), i sider à [vodPageSize].
const vodPageSize = 120;

VodPage pageOf(List<VodItem> items, {String category = '', String query = '', VodSort sort = VodSort.provider, int start = 0}) {
  var list = items;
  if (category.isNotEmpty) list = [for (final i in list) if (i.categoryId == category) i];
  final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isNotEmpty) list = [for (final i in list) if (words.every(i.name.toLowerCase().contains)) i];
  if (sort == VodSort.name) {
    list = [...list]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  } else if (sort == VodSort.newest) {
    list = [...list]..sort((a, b) => b.added.compareTo(a.added));
  }
  final from = start.clamp(0, list.length);
  final to = (from + vodPageSize).clamp(0, list.length);
  return VodPage(items: list.sublist(from, to), total: list.length);
}

/// Kategoriene med antall, bare de som har noe i.
VodCatalog catalogOf(List<VodCategory> categories, List<VodItem> items) {
  final counts = <String, int>{};
  for (final i in items) {
    counts[i.categoryId] = (counts[i.categoryId] ?? 0) + 1;
  }
  return VodCatalog(
    categories: [
      for (final c in categories)
        if ((counts[c.id] ?? 0) > 0) VodCategory(id: c.id, name: c.name, count: counts[c.id]!),
    ],
    total: items.length,
  );
}
