import 'models.dart';

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
  const PlayTarget(this.urls);

  final List<String> urls;
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
  Future<List<EpgEntry>> epg(String channelId);

  String? logoUrl(String? icon);

  /// Kan kaste BusyException. takeOver tar tilkoblingen fra noen andre, bare i denne ene forespørselen.
  Future<PlayTarget> open(Channel channel, {bool takeOver = false});

  /// frigjør tilkoblingen når du går til en annen kanal eller lukker spilleren
  Future<void> close(Channel channel);

  Future<Favorites?> loadFavorites();

  Future<Favorites?> changeFavorites(Map<String, Object?> change);

  /// det som lagres for å koble til igjen neste gang
  Map<String, String> toPrefs();

  void dispose();
}
