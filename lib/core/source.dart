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

/// En kilde til TV: IPTV-leverandøren med Xtream Codes, eller en M3U-liste.
abstract class TvSource {
  /// 'xtream' eller 'm3u'
  String get kind;

  /// vises i menyen, f.eks. «bob på iptv.example»
  String get label;

  /// sendes med til strømmene (User-Agent hos leverandøren)
  Map<String, String> get httpHeaders;

  /// kilden har filmer og serier (fanene skjules ellers)
  bool get hasVod;

  Future<Account> account();

  Future<List<Category>> categories({bool force = false});

  Future<List<Channel>> channels({bool force = false});

  /// programmene som går nå og senere; [limit] er hvor mange (TV-guiden vil ha flere enn kortene)
  Future<List<EpgEntry>> epg(String channelId, {int limit = 6});

  String? logoUrl(String? icon);

  /// adressene til kanalen (kaster SourceException når det ikke går)
  Future<PlayTarget> open(Channel channel);

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
