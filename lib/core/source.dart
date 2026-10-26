import 'models.dart';
import 'vod.dart';

class SourceException implements Exception {
  const SourceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Alle tilkoblingene hos leverandøren er i bruk (med navnene på kanalene som går, når kilden vet dem).
class BusyException extends SourceException {
  const BusyException(super.message, this.busy);

  final List<String> busy;
}

/// Hvor strømmen hentes fra. Adressene prøves i rekkefølge (f.eks. HLS først, så MPEG-TS).
class PlayTarget {
  const PlayTarget(this.urls, {this.localShift = false});

  final List<String> urls;

  /// en direktesending: avspilleren tar vare på det siste selv, så du kan pause og spole tilbake i det
  final bool localShift;
}

/// En kilde til TV: IPTV-leverandøren med Xtream Codes, eller en M3U-liste.
abstract class TvSource {
  /// 'xtream' eller 'm3u'
  String get kind;

  /// vises i menyen, f.eks. «bob på iptv.example»
  String get label;

  /// sendes med til strømmene (User-Agent hos leverandøren)
  Map<String, String> get httpHeaders;

  /// favorittene ligger hos kilden og deles med andre enheter, ikke bare i appen (ingen av kildene nå)
  bool get sharedFavorites;

  /// kilden har filmer og serier (fanene skjules ellers)
  bool get hasVod;

  /// sjekkes når appen starter
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

  /// Tekst som skal vises eller logges (f.eks. en feil fra mpv med hele adressen): uten brukernavn og passord.
  String redact(String text);

  /// det som lagres for å koble til igjen neste gang
  Map<String, String> toPrefs();

  void dispose();
}
