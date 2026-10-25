import 'models.dart';
import 'vod.dart';

class SourceException implements Exception {
  const SourceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Alle tilkoblingene hos leverandøren er i bruk. Fyrlys-serveren sier hvilke kanaler som går.
class BusyException extends SourceException {
  const BusyException(super.message, this.busy);

  final List<String> busy;
}

/// Hvor strømmen hentes fra. Adressene prøves i rekkefølge (f.eks. HLS først, så MPEG-TS).
class PlayTarget {
  const PlayTarget(this.urls, {this.timeshift = Duration.zero});

  final List<String> urls;

  /// hvor langt tilbake det går an å spole i direktesendingen (Fyrlys-serveren med ffmpeg); 0 = ikke mulig
  final Duration timeshift;
}

/// En kilde til TV: rett mot IPTV-leverandøren (Xtream Codes) eller via Fyrlys-serveren (Docker-versjonen).
abstract class TvSource {
  /// 'xtream' eller 'fyrlys'
  String get kind;

  /// vises i menyen, f.eks. «bob på iptv.example»
  String get label;

  /// sendes med til strømmene (User-Agent hos leverandøren)
  Map<String, String> get httpHeaders;

  /// favorittene ligger hos kilden (Fyrlys-serveren) og deles med nettsiden, ikke bare i appen
  bool get sharedFavorites;

  /// sjekkes når appen starter, f.eks. om serveren har ffmpeg
  Future<void> prepare();

  Future<Account> account();

  Future<List<Category>> categories({bool force = false});

  Future<List<Channel>> channels({bool force = false});

  /// programmene som går nå og senere
  /// programmene som går nå og senere; [limit] er hvor mange (TV-guiden vil ha flere enn kortene)
  Future<List<EpgEntry>> epg(String channelId, {int limit = 6});

  String? logoUrl(String? icon);

  /// Kan kaste BusyException. takeOver tar tilkoblingen fra noen andre, bare i denne ene forespørselen.
  Future<PlayTarget> open(Channel channel, {bool takeOver = false});

  /// frigjør tilkoblingen når du går til en annen kanal eller lukker spilleren
  Future<void> close(Channel channel);

  Future<Favorites?> loadFavorites();

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

  Future<Favorites?> changeFavorites(Map<String, Object?> change);

  /// Spillelista til en direktesending slik den er nå, for å spole i den (bare når [PlayTarget.timeshift] er
  /// over 0). Hentes også mens du har pauset, så serveren vet at du fortsatt ser på.
  Future<LiveWindow?> liveWindow(String url);

  /// det som lagres for å koble til igjen neste gang
  Map<String, String> toPrefs();

  void dispose();
}
