import 'models.dart';
import 'vod.dart';

class SourceException implements Exception {
  const SourceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Hvor strømmen hentes fra. Adressene prøves i rekkefølge (f.eks. HLS først, så MPEG-TS).
class PlayTarget {
  const PlayTarget(this.urls, {this.localShift = false});

  final List<String> urls;

  /// en direktesending: avspilleren tar vare på det siste selv, så du kan pause og spole tilbake i det
  final bool localShift;
}

/// Adressene til et program i TV-arkivet fra et punkt i programmet (de neste prøves hvis den første ikke virker),
/// og hvor strømmen faktisk begynner: leverandøren lager den fra et helt minutt, så litt før.
typedef ArchiveUrls = ({List<String> urls, Duration from});

/// Et program i TV-arkivet. Strømmen begynner der du ber om (på minuttet), så avspilleren åpner den på nytt når du
/// spoler lenger enn det den har hentet.
class ArchiveClip {
  const ArchiveClip({required this.start, required this.stop, required this.urlsAt});

  final DateTime start;
  final DateTime stop;
  final ArchiveUrls Function(Duration from) urlsAt;

  Duration get length => stop.difference(start);
}

/// En kilde til TV: IPTV-leverandøren med Xtream Codes, eller en M3U-liste.
abstract class TvSource {
  /// 'xtream' eller 'm3u'
  String get kind;

  /// navnet en ny innlogging får, f.eks. «bob på iptv.example»
  String get label;

  /// sendes med til strømmene (User-Agent hos leverandøren)
  Map<String, String> get httpHeaders;

  /// kilden har filmer og serier (fanene skjules ellers)
  bool get hasVod;

  /// abonnementet; [fresh]: spør leverandøren på nytt (hvor mange tilkoblinger som er i bruk nå)
  Future<Account> account({bool fresh = false});

  Future<List<Category>> categories({bool force = false});

  Future<List<Channel>> channels({bool force = false});

  /// programmene som går nå og senere; [limit] er hvor mange (TV-guiden vil ha flere enn kortene)
  Future<List<EpgEntry>> epg(String channelId, {int limit = 6});

  String? logoUrl(String? icon);

  /// adressene til kanalen (kaster SourceException når det ikke går)
  Future<PlayTarget> open(Channel channel);

  // ── TV-arkivet (kanaler med Channel.hasArchive) ──

  /// programmene som har gått de siste dagene (og det som går nå), eldst først
  Future<List<EpgEntry>> archive(Channel channel);

  /// strømmen for et program i arkivet (kaster SourceException når kanalen ikke har arkiv)
  Future<ArchiveClip> archiveClip(Channel channel, EpgEntry program);

  // ── filmer og serier ──

  /// kategoriene (med antall) og hvor mange det er i alt
  Future<VodCatalog> vodCatalog(VodKind kind, {bool force = false});

  /// en side (vodPageSize) med filmer eller serier, filtrert på kategori og søk
  Future<VodPage> vodPage(VodKind kind, {String category = '', String query = '', VodSort sort = VodSort.provider, int start = 0});

  Future<MovieInfo> movieInfo(String id);

  Future<SeriesInfo> seriesInfo(String id);

  /// filen avspilleren henter (spoling med Range); plakater og bilder går via logoUrl
  String movieUrl(VodItem movie);

  String episodeUrl(Episode episode);

  /// Tekst som skal vises eller logges (f.eks. en feil fra mpv med hele adressen): uten brukernavn og passord.
  String redact(String text);

  /// det som lagres for å koble til igjen neste gang
  Map<String, String> toPrefs();

  void dispose();
}
