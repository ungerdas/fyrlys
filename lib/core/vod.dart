// Filmer og serier: det appen vet om dem, uansett kilde (Fyrlys-serveren eller leverandøren direkte).

enum VodKind {
  movies('vod', 'Filmer'),
  series('series', 'Serier');

  const VodKind(this.api, this.title);

  /// navnet hos Fyrlys-serveren (kind=vod / kind=series)
  final String api;
  final String title;
}

/// Rekkefølgen i lista, som på nettsiden.
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
  });

  final String plot;
  final String genre;
  final String year;
  final String duration;
  final String cast;
  final String director;
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
  });

  final String id;
  final String title;
  final int? number;
  final String ext;
  final String? image;
  final String plot;
  final String duration;
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
    this.plot = '',
    this.genre = '',
    this.year = '',
    this.rating,
    this.seasons = const [],
  });

  final String name;
  final String? cover;
  final String plot;
  final String genre;
  final String year;
  final double? rating;
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

  /// «film:<id>» (samme som for «fortsett der du slapp») eller «serie:<id>»
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

/// «S01E02», som på nettsiden; tomt når noe mangler.
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

/// Siden lister filtreres og sorteres likt hos begge kildene: Fyrlys-serveren gjør det selv, og for
/// leverandøren direkte gjør appen det med hele lista.
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
