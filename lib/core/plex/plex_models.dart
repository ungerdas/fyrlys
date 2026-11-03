// Plex: serverne, bibliotekene og det som ligger i dem, slik plex.tv og Plex-serveren beskriver dem (JSON).

import 'dart:io' show InternetAddress, InternetAddressType;

import '../../l10n/tr.dart';
import '../vod.dart' show MediaTech, episodeCode;

// ── tall og tekst fra JSON: Plex sender det samme som tall, tekst eller sant/usant ──

int? plexInt(Object? v) {
  if (v is int) return v;
  final d = v is num ? v.toDouble() : (v is String ? double.tryParse(v.trim()) : null);
  return d != null && d.isFinite ? d.round() : null;
}

double? plexDouble(Object? v) {
  final d = v is num ? v.toDouble() : (v is String ? double.tryParse(v.trim()) : null);
  return d != null && d.isFinite ? d : null;
}

bool plexBool(Object? v) => switch (v) {
      final bool b => b,
      final num n => n != 0,
      final String s => s == '1' || s.toLowerCase() == 'true',
      _ => false,
    };

/// tekst (tom når den mangler)
String plexText(Object? v) => switch (v) {
      final String s => s,
      final num n => '$n',
      final bool b => '$b',
      _ => '',
    };

/// tekst, eller null når den mangler eller er tom (stier til bilder og filer)
String? plexPath(Object? v) {
  final s = plexText(v).trim();
  return s.isEmpty ? null : s;
}

Map<String, Object?> plexMap(Object? v) =>
    v is Map ? {for (final e in v.entries) '${e.key}': e.value} : <String, Object?>{};

List<Map<String, Object?>> plexList(Object? v) => [
      if (v is List)
        for (final e in v)
          if (e is Map) plexMap(e),
    ];

List<String> _tags(Object? v) => [
      for (final t in plexList(v))
        if (plexText(t['tag']).trim().isNotEmpty) plexText(t['tag']).trim(),
    ];

/// Hvor du slapp, når det er verdt å fortsette: mer enn ti sekunder inn og ikke nesten ferdig.
Duration? resumeFrom(Duration at, Duration length) {
  if (at < const Duration(seconds: 10)) return null;
  if (length > Duration.zero && at.inMilliseconds > length.inMilliseconds * 0.95) return null;
  return at;
}

bool _privateAddress(String address) {
  final a = InternetAddress.tryParse(address);
  if (a == null || a.type != InternetAddressType.IPv4) return false;
  final b = a.rawAddress;
  return b[0] == 10 ||
      b[0] == 127 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168) ||
      (b[0] == 169 && b[1] == 254);
}

// ── serveren ──

/// En adresse Plex-serveren kan nås på.
class PlexConnection {
  const PlexConnection({
    required this.uri,
    this.protocol = 'https',
    this.address = '',
    this.port = 32400,
    this.local = false,
    this.relay = false,
  });

  factory PlexConnection.fromJson(Map<String, Object?> j) {
    final uri = plexText(j['uri']).trim();
    return PlexConnection(
      uri: uri.endsWith('/') ? uri.substring(0, uri.length - 1) : uri,
      protocol: plexText(j['protocol']).isEmpty ? 'https' : plexText(j['protocol']).toLowerCase(),
      address: plexText(j['address']),
      port: plexInt(j['port']) ?? 32400,
      local: plexBool(j['local']),
      relay: plexBool(j['relay']),
    );
  }

  final String uri;
  final String protocol;
  final String address;
  final int port;

  /// i samme nett som serveren (ifølge plex.tv)
  final bool local;

  /// via Plex sine egne servere (når fjerntilgang ikke virker; begrenset fart)
  final bool relay;

  /// 0: i hjemmenettet, 1: over nettet, 2: via Plex (relay)
  int get tier => relay ? 2 : (local ? 0 : 1);

  bool get secure => protocol == 'https';

  /// http rett til adressen i hjemmenettet: reserven når https-navnet (…plex.direct) ikke virker der, f.eks. fordi
  /// ruteren stopper navn som peker til hjemmenettet. Bare i hjemmenettet, så innloggingen aldri går ukryptert ut.
  PlexConnection? get lanHttp {
    if (!local || relay || !secure || !_privateAddress(address)) return null;
    return PlexConnection(uri: 'http://$address:$port', protocol: 'http', address: address, port: port, local: true);
  }

  Map<String, Object?> toJson() =>
      {'uri': uri, 'protocol': protocol, 'address': address, 'port': port, 'local': local, 'relay': relay};
}

/// En Plex-server kontoen har tilgang til (egen eller delt med deg).
class PlexServer {
  const PlexServer({
    required this.id,
    required this.name,
    required this.token,
    this.owned = false,
    this.connections = const [],
    this.version = '',
    this.lastSeen,
  });

  /// fra plex.tv (resources); null når det ikke er en server
  static PlexServer? fromJson(Map<String, Object?> j) {
    if (!plexText(j['provides']).split(',').contains('server')) return null;
    final id = plexText(j['clientIdentifier']);
    final token = plexText(j['accessToken']);
    if (id.isEmpty || token.isEmpty) return null;
    final connections = [
      for (final c in plexList(j['connections']))
        if (!plexBool(c['IPv6']) && plexText(c['uri']).startsWith('http')) PlexConnection.fromJson(c),
    ];
    if (connections.isEmpty) return null;
    return PlexServer(
      id: id,
      name: plexText(j['name']).isEmpty ? 'Plex' : plexText(j['name']),
      token: token,
      owned: plexBool(j['owned']),
      connections: connections,
      version: plexText(j['productVersion']),
      lastSeen: DateTime.tryParse(plexText(j['lastSeenAt'])),
    );
  }

  /// lagret i appen (samme form som fra plex.tv)
  static PlexServer? fromSaved(Object? raw) {
    final j = plexMap(raw);
    final id = plexText(j['id']);
    final token = plexText(j['token']);
    final connections = [for (final c in plexList(j['connections'])) PlexConnection.fromJson(c)];
    if (id.isEmpty || token.isEmpty || connections.isEmpty) return null;
    return PlexServer(
      id: id,
      name: plexText(j['name']),
      token: token,
      owned: plexBool(j['owned']),
      connections: connections,
      version: plexText(j['version']),
    );
  }

  /// machineIdentifier
  final String id;
  final String name;

  /// innloggingen til akkurat denne serveren (for en delt server ikke den samme som kontoens)
  final String token;
  final bool owned;
  final List<PlexConnection> connections;
  final String version;
  final DateTime? lastSeen;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'token': token,
        'owned': owned,
        'version': version,
        'connections': [for (final c in connections) c.toJson()],
      };
}

/// Egne servere først, så den som sist var på nett.
List<PlexServer> sortServers(List<PlexServer> list) => [...list]..sort((a, b) {
    if (a.owned != b.owned) return a.owned ? -1 : 1;
    final x = a.lastSeen;
    final y = b.lastSeen;
    if (x != null && y != null) return y.compareTo(x);
    return x != null ? -1 : (y != null ? 1 : 0);
  });

// ── bibliotekene ──

/// Et bibliotek med filmer eller serier.
class PlexLibrary {
  const PlexLibrary({required this.key, required this.title, required this.type});

  factory PlexLibrary.fromJson(Map<String, Object?> j) =>
      PlexLibrary(key: plexText(j['key']), title: plexText(j['title']), type: plexText(j['type']));

  final String key;
  final String title;

  /// 'movie' eller 'show'
  final String type;

  bool get shows => type == 'show';

  /// typen i Plex-API-et (1 film, 2 serie)
  int get apiType => shows ? 2 : 1;
}

/// En sjanger (eller annet å filtrere på) i et bibliotek.
class PlexTag {
  const PlexTag({required this.key, required this.title});

  final String key;
  final String title;
}

/// Rekkefølgen i et bibliotek.
enum PlexSort {
  added,
  alpha,
  released,
  rating,
  lastViewed;

  /// sorteringen i Plex-API-et; for serier er «nylig lagt til» når det sist kom en episode
  String api({required bool shows}) => switch (this) {
        PlexSort.added => shows ? 'episode.addedAt:desc' : 'addedAt:desc',
        PlexSort.alpha => 'titleSort',
        PlexSort.released => 'originallyAvailableAt:desc',
        PlexSort.rating => 'audienceRating:desc',
        PlexSort.lastViewed => 'lastViewedAt:desc',
      };

  String get title => switch (this) {
        PlexSort.added => tr('Nylig lagt til'),
        PlexSort.alpha => tr('A–Å'),
        PlexSort.released => tr('Nyeste utgivelser'),
        PlexSort.rating => tr('Best vurdert'),
        PlexSort.lastViewed => tr('Sist sett'),
      };
}

// ── filmer, serier, sesonger og episoder ──

enum PlexType {
  movie,
  show,
  season,
  episode,
  other;

  static PlexType of(String s) => switch (s) {
        'movie' => PlexType.movie,
        'show' => PlexType.show,
        'season' => PlexType.season,
        'episode' => PlexType.episode,
        _ => PlexType.other,
      };
}

/// Et spor i filen: bilde (1), lyd (2) eller undertekst (3).
class PlexStream {
  const PlexStream({
    required this.type,
    this.codec = '',
    this.language = '',
    this.languageCode = '',
    this.title = '',
    this.key,
    this.channels = 0,
    this.hdr = false,
    this.forced = false,
  });

  factory PlexStream.fromJson(Map<String, Object?> j) {
    final trc = plexText(j['colorTrc']).toLowerCase();
    final display = plexText(j['displayTitle']);
    return PlexStream(
      type: plexInt(j['streamType']) ?? 0,
      codec: plexText(j['codec']).toLowerCase(),
      language: plexText(j['language']),
      languageCode: plexText(j['languageCode']),
      title: display.isNotEmpty ? display : plexText(j['title']),
      key: plexPath(j['key']),
      channels: plexInt(j['channels']) ?? 0,
      hdr: trc == 'smpte2084' || trc == 'arib-std-b67' || plexBool(j['DOVIPresent']),
      forced: plexBool(j['forced']),
    );
  }

  final int type;
  final String codec;
  final String language;
  final String languageCode;
  final String title;

  /// undertekster i en egen fil (ved siden av filmen, eller lastet ned i Plex): adressen på serveren
  final String? key;
  final int channels;
  final bool hdr;
  final bool forced;

  bool get external => type == 3 && key != null;
}

class PlexPart {
  const PlexPart({required this.key, this.id = '', this.container = '', this.size = 0, this.streams = const []});

  factory PlexPart.fromJson(Map<String, Object?> j) => PlexPart(
        key: plexText(j['key']),
        id: plexText(j['id']),
        container: plexText(j['container']).toLowerCase(),
        size: plexInt(j['size']) ?? 0,
        streams: [for (final s in plexList(j['Stream'])) PlexStream.fromJson(s)],
      );

  /// «/library/parts/123/1700000000/file.mkv»
  final String key;
  final String id;
  final String container;
  final int size;
  final List<PlexStream> streams;
}

class PlexMedia {
  const PlexMedia({
    this.videoResolution = '',
    this.videoCodec = '',
    this.audioCodec = '',
    this.audioChannels = 0,
    this.height = 0,
    this.container = '',
    this.parts = const [],
  });

  factory PlexMedia.fromJson(Map<String, Object?> j) => PlexMedia(
        videoResolution: plexText(j['videoResolution']).toLowerCase(),
        videoCodec: plexText(j['videoCodec']).toLowerCase(),
        audioCodec: plexText(j['audioCodec']).toLowerCase(),
        audioChannels: plexInt(j['audioChannels']) ?? 0,
        height: plexInt(j['height']) ?? 0,
        container: plexText(j['container']).toLowerCase(),
        parts: [
          for (final p in plexList(j['Part']))
            if (plexText(p['key']).isNotEmpty) PlexPart.fromJson(p),
        ],
      );

  final String videoResolution;
  final String videoCodec;
  final String audioCodec;
  final int audioChannels;
  final int height;
  final String container;
  final List<PlexPart> parts;

  int get lines => height > 0
      ? height
      : switch (videoResolution) {
          '4k' => 2160,
          '1080' => 1080,
          '720' => 720,
          '576' || '480' || 'sd' => 480,
          _ => 0,
        };
}

/// Intro eller rulletekst (for «Hopp over»).
class PlexMarker {
  const PlexMarker({required this.type, required this.start, required this.end});

  factory PlexMarker.fromJson(Map<String, Object?> j) => PlexMarker(
        type: plexText(j['type']),
        start: Duration(milliseconds: plexInt(j['startTimeOffset']) ?? 0),
        end: Duration(milliseconds: plexInt(j['endTimeOffset']) ?? 0),
      );

  /// 'intro' eller 'credits'
  final String type;
  final Duration start;
  final Duration end;
}

/// En film, serie, sesong eller episode.
class PlexItem {
  const PlexItem({
    required this.ratingKey,
    required this.type,
    required this.title,
    this.summary = '',
    this.tagline = '',
    this.year,
    this.thumb,
    this.art,
    this.parentThumb,
    this.grandparentThumb,
    this.grandparentArt,
    this.parentTitle = '',
    this.grandparentTitle = '',
    this.parentRatingKey,
    this.grandparentRatingKey,
    this.index,
    this.parentIndex,
    this.duration = Duration.zero,
    this.viewOffset = Duration.zero,
    this.viewCount = 0,
    this.leafCount = 0,
    this.viewedLeafCount = 0,
    this.childCount = 0,
    this.rating,
    this.contentRating = '',
    this.studio = '',
    this.addedAt = 0,
    this.sectionId,
    this.genres = const [],
    this.directors = const [],
    this.countries = const [],
    this.cast = const [],
    this.media = const [],
    this.markers = const [],
    this.onDeck,
  });

  factory PlexItem.fromJson(Map<String, Object?> j) {
    final deck = plexList(plexMap(j['OnDeck'])['Metadata']);
    return PlexItem(
      ratingKey: plexText(j['ratingKey']),
      type: PlexType.of(plexText(j['type'])),
      title: plexText(j['title']),
      summary: plexText(j['summary']).trim(),
      tagline: plexText(j['tagline']).trim(),
      year: plexInt(j['year']),
      thumb: plexPath(j['thumb']),
      art: plexPath(j['art']),
      parentThumb: plexPath(j['parentThumb']),
      grandparentThumb: plexPath(j['grandparentThumb']),
      grandparentArt: plexPath(j['grandparentArt']),
      parentTitle: plexText(j['parentTitle']),
      grandparentTitle: plexText(j['grandparentTitle']),
      parentRatingKey: plexPath(j['parentRatingKey']),
      grandparentRatingKey: plexPath(j['grandparentRatingKey']),
      index: plexInt(j['index']),
      parentIndex: plexInt(j['parentIndex']),
      duration: Duration(milliseconds: plexInt(j['duration']) ?? 0),
      viewOffset: Duration(milliseconds: plexInt(j['viewOffset']) ?? 0),
      viewCount: plexInt(j['viewCount']) ?? 0,
      leafCount: plexInt(j['leafCount']) ?? 0,
      viewedLeafCount: plexInt(j['viewedLeafCount']) ?? 0,
      childCount: plexInt(j['childCount']) ?? 0,
      rating: plexDouble(j['audienceRating']) ?? plexDouble(j['rating']),
      contentRating: plexText(j['contentRating']),
      studio: plexText(j['studio']),
      addedAt: plexInt(j['addedAt']) ?? 0,
      sectionId: plexPath(j['librarySectionID']),
      genres: _tags(j['Genre']),
      directors: _tags(j['Director']),
      countries: _tags(j['Country']),
      cast: _tags(j['Role']),
      media: [for (final m in plexList(j['Media'])) PlexMedia.fromJson(m)],
      markers: [for (final m in plexList(j['Marker'])) PlexMarker.fromJson(m)],
      onDeck: deck.isEmpty ? null : PlexItem.fromJson(deck.first),
    );
  }

  final String ratingKey;
  final PlexType type;
  final String title;
  final String summary;
  final String tagline;
  final int? year;

  /// bildene (stier på serveren): plakat/stillbilde, bakgrunn, sesongens og seriens plakat
  final String? thumb;
  final String? art;
  final String? parentThumb;
  final String? grandparentThumb;
  final String? grandparentArt;

  /// en episode: sesongen og serien
  final String parentTitle;
  final String grandparentTitle;
  final String? parentRatingKey;
  final String? grandparentRatingKey;

  /// episoden eller sesongen (nummeret), og sesongen til en episode
  final int? index;
  final int? parentIndex;
  final Duration duration;

  /// hvor du slapp (0: ikke begynt, eller sett ferdig)
  final Duration viewOffset;
  final int viewCount;

  /// serier og sesonger: episoder i alt, og hvor mange som er sett
  final int leafCount;
  final int viewedLeafCount;

  /// serier: sesonger
  final int childCount;
  final double? rating;

  /// aldersgrense («12», «PG-13»)
  final String contentRating;
  final String studio;

  /// når den kom på serveren (sekunder)
  final int addedAt;
  final String? sectionId;
  final List<String> genres;
  final List<String> directors;
  final List<String> countries;
  final List<String> cast;
  final List<PlexMedia> media;
  final List<PlexMarker> markers;

  /// en serie (med includeOnDeck): episoden du skal se nå
  final PlexItem? onDeck;

  bool get isShowLike => type == PlexType.show || type == PlexType.season;

  /// plakaten (for en episode: seriens)
  String? get poster => switch (type) {
        PlexType.episode => grandparentThumb ?? parentThumb ?? thumb,
        PlexType.season => thumb ?? parentThumb,
        _ => thumb,
      };

  /// det store bakgrunnsbildet
  String? get backdrop => art ?? grandparentArt;

  /// sett ferdig (serier og sesonger: alle episodene)
  bool get watched =>
      isShowLike ? leafCount > 0 && viewedLeafCount >= leafCount : viewCount > 0 && viewOffset == Duration.zero;

  /// episoder igjen å se (serier og sesonger)
  int get unwatched => leafCount > viewedLeafCount ? leafCount - viewedLeafCount : 0;

  /// hvor langt du har kommet (0–1), når du har begynt
  double? get progress {
    if (viewOffset <= Duration.zero || duration <= Duration.zero) return null;
    return (viewOffset.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0).toDouble();
  }

  /// hvor du slapp, når det er verdt å fortsette
  Duration? get resumeAt => resumeFrom(viewOffset, duration);

  /// «S01E02» for en episode
  String get code => type == PlexType.episode && parentIndex != null ? episodeCode('$parentIndex', index) : '';

  /// navnet på kortet: serien for en episode
  String get cardTitle => switch (type) {
        PlexType.episode => grandparentTitle.isNotEmpty ? grandparentTitle : title,
        PlexType.season => parentTitle.isNotEmpty ? parentTitle : title,
        _ => title,
      };

  /// linja under navnet på et kort
  String get cardLine => switch (type) {
        PlexType.episode => [code, title].where((t) => t.isNotEmpty).join(' · '),
        PlexType.season => title,
        PlexType.show when childCount > 1 => tr('{n} sesonger', {'n': childCount}),
        _ => year == null ? '' : '$year',
      };

  /// filen som spilles (den første versjonen og delen)
  PlexPart? get part {
    for (final m in media) {
      if (m.parts.isNotEmpty) return m.parts.first;
    }
    return null;
  }

  /// bildet og lyden, til merkene på detaljsiden og til Chromecasten
  MediaTech get tech {
    if (media.isEmpty) return const MediaTech();
    final m = media.first;
    var hdr = false;
    for (final s in part?.streams ?? const <PlexStream>[]) {
      if (s.type == 1) {
        hdr = s.hdr;
        break;
      }
    }
    return MediaTech(
      height: m.lines,
      videoCodec: m.videoCodec,
      hdr: hdr,
      audioCodec: m.audioCodec == 'dca' ? 'dts' : m.audioCodec,
      channels: m.audioChannels,
    );
  }

  /// undertekstene i egne filer
  List<PlexStream> get externalSubtitles => [
        for (final s in part?.streams ?? const <PlexStream>[])
          if (s.external) s,
      ];
}

/// En side fra et bibliotek, og hvor mange det er i alt.
class PlexPage {
  const PlexPage({required this.items, required this.total});

  final List<PlexItem> items;
  final int total;
}
