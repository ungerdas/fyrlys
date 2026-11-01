import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import '../platform.dart';

/// Det Fyrlys trenger fra Android selv (MainActivity.kt): multicast-lås mens Chromecaster letes etter, en tjeneste
/// som holder appen og wifi i gang mens telefonen sender strømmen videre til en Chromecast, installering av
/// oppdateringer, nettleseren og deling. Utenfor Android (og i testene) gjør den ingenting.
class AndroidHost {
  AndroidHost._();

  static const _channel = MethodChannel('fyrlys/android');

  static Future<T?> _call<T>(String method, [Object? arguments]) async {
    if (!isAndroid) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on Object catch (e) {
      debugPrint('Android: $method feilet ($e)');
      return null;
    }
  }

  /// «Android 15 (API 35) · Google Pixel 8», til feilrapporten.
  static Future<String?> device() => _call<String>('device');

  /// Slipper gjennom multicast på wifi (svarene fra Chromecastene) så lenge det letes.
  static Future<void> multicast(bool on) => _call<void>('multicast', on);

  /// Varselet og tjenesten mens det castes, med [text] i varselet; null stopper dem.
  static Future<void> casting(String? text) => _call<void>('casting', text);

  /// Åpner installeringen av APK-en på [path] (Android spør deg). false: Fyrlys har ikke lov til å installere apper
  /// ennå (innstillingen for det er åpnet), eller fila finnes ikke.
  static Future<bool> install(String path) async => await _call<bool>('install', path) ?? false;

  /// Åpner [url] i nettleseren.
  static Future<void> openUrl(String url) => _call<void>('openUrl', url);

  /// Deler [text] (f.eks. feilrapporten) med en app du velger.
  static Future<void> share(String text, {String subject = 'Fyrlys'}) =>
      _call<void>('share', {'text': text, 'subject': subject});
}
