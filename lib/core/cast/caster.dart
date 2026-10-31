import 'package:flutter/foundation.dart';

import 'chromecast.dart';
import 'mdns.dart';

export 'mdns.dart' show CastDevice;

/// Hvor Chromecasten er.
enum CastState {
  /// ikke koblet til
  off,

  /// kobler til og starter avspilleren på TV-en
  connecting,

  /// koblet til, ingenting spilles
  ready,

  /// henter det som skal spilles
  loading,
  playing,
  paused,
  buffering,

  /// ferdig (en film), eller sendingen tok slutt
  ended,

  /// Chromecasten kunne ikke spille det (se [Caster.error])
  failed,
}

/// Noe som skal spilles på TV-en.
class CastItem {
  const CastItem({
    required this.urls,
    required this.title,
    this.subtitle = '',
    this.image,
    this.live = false,
    this.headers = const {},
    this.start = Duration.zero,
  });

  /// adressene hos leverandøren (HLS foretrekkes, det spiller Chromecasten best)
  final List<String> urls;
  final String title;
  final String subtitle;

  /// logo eller plakat
  final String? image;

  /// en direktesending (ellers en fil eller et program med kjent lengde)
  final bool live;

  /// hodene leverandøren vil ha (User-Agent)
  final Map<String, String> headers;

  /// hvor i filmen det skal begynne
  final Duration start;

  /// Adressen som castes: HLS først, ellers den første.
  String get url => urls.firstWhere(isHlsUrl, orElse: () => urls.first);

  bool get isHls => isHlsUrl(url);

  /// Det Chromecasten får vite om innholdet.
  String get contentType {
    final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    if (isHls) return 'application/x-mpegurl';
    if (path.endsWith('.ts')) return 'video/mp2t';
    if (path.endsWith('.mkv')) return 'video/x-matroska';
    if (path.endsWith('.webm')) return 'video/webm';
    if (path.endsWith('.mp3')) return 'audio/mpeg';
    return 'video/mp4';
  }
}

bool isHlsUrl(String url) {
  final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  return path.endsWith('.m3u8') || url.toLowerCase().contains('.m3u8');
}

/// Casting til en Chromecast: finn den, koble til, spill, og styr den. Det finnes én for hele appen ([appCaster]),
/// så castingen fortsetter når du går ut av spilleren.
abstract class Caster extends ChangeNotifier {
  /// Chromecasten det castes til (null: det castes ikke)
  CastDevice? get device;

  bool get active => device != null;

  CastState get state;

  /// det som gikk galt sist (vises for brukeren)
  String? get error;

  /// det som spilles nå
  CastItem? get item;

  /// hvor langt den har kommet, og lengden (null: ukjent, f.eks. en direktesending)
  Duration get position;
  Duration? get duration;

  /// volumet på Chromecasten, 0–1
  double get volume;
  bool get muted;

  /// Chromecastene på nettverket, etter hvert som de svarer.
  Stream<CastDevice> discover();

  /// Kobler til og starter Googles avspiller på TV-en.
  Future<void> connect(CastDevice device);

  /// Spiller [item] på TV-en (det som gikk, byttes ut).
  Future<void> load(CastItem item);

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setVolume(double level);
  Future<void> setMuted(bool muted);

  /// Stopper avspillingen på TV-en og kobler fra.
  Future<void> stop();
}

/// Den appen bruker (testene bytter den ut med en falsk).
Caster appCaster = ChromecastCaster();
