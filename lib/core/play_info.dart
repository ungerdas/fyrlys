// Det filmspilleren får vite om en fil utover adressen: hvem som skal ha beskjed om hvor du er (Plex), og
// undertekstfiler og intro/rulletekst som hentes når den spilles.

/// Hvor du er i det som spilles, til en tjeneste som husker det (Plex). Spilleren kaller dem; feilene håndteres der
/// (de skal aldri stoppe avspillingen).
abstract class PlayReport {
  /// hvert tiende sekund mens det spilles, og når du setter på pause eller spiller videre
  void progress(Duration position, Duration duration, {required bool playing});

  /// spilleren lukkes, eller går til noe annet
  void stopped(Duration position, Duration duration);

  /// sett ferdig
  void finished(Duration duration);
}

/// En undertekst i en egen fil (adressen hentes av avspilleren selv).
class ExternalSubtitle {
  const ExternalSubtitle({required this.url, required this.title, this.language = ''});

  final String url;
  final String title;
  final String language;
}

/// En del av filen du kan hoppe over: introen, eller rulleteksten på slutten.
class SkipMarker {
  const SkipMarker({required this.credits, required this.start, required this.end});

  /// rulleteksten (ellers introen)
  final bool credits;
  final Duration start;
  final Duration end;

  bool covers(Duration at) => at >= start && at < end;
}

/// Det som hentes når en fil begynner å spille.
class PlayExtras {
  const PlayExtras({this.subtitles = const [], this.markers = const []});

  final List<ExternalSubtitle> subtitles;
  final List<SkipMarker> markers;
}
