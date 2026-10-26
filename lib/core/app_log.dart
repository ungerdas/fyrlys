import 'dart:collection';

/// Det appen har skrevet i loggen den siste tida (debugPrint og feil), til feilrapporten. Hver linje vaskes med
/// [scrub] før den tas vare på, så adresser, brukernavn og passord aldri ligger her.
class AppLog {
  AppLog({this.max = 400});

  static final instance = AppLog();

  final int max;
  final _lines = ListQueue<String>();

  List<String> get lines => List.unmodifiable(_lines);

  void add(String message, {DateTime? at}) {
    final t = at ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    for (final line in scrub(message).split('\n')) {
      if (line.trim().isEmpty) continue;
      _lines.add('$stamp ${line.trimRight()}');
      while (_lines.length > max) {
        _lines.removeFirst();
      }
    }
  }

  void clear() => _lines.clear();
}

final _url = RegExp(r'([a-z][a-z0-9+.-]*://)[^/\s"<>]+', caseSensitive: false);
final _streamPath = RegExp(r'/(live|movie|series|timeshift)/[^/\s"]+/[^/\s"]+', caseSensitive: false);
final _query = RegExp(r'\b(username|password|user|pass|passwd|token|key|auth)=[^&\s"]+', caseSensitive: false);
final _email = RegExp(r'[\w.+-]+@[\w-]+(\.[\w-]+)+');
final _ip = RegExp(r'\b\d{1,3}(\.\d{1,3}){3}\b');
final _home = RegExp(r'([\\/]Users[\\/])[^\\/"\r\n]+', caseSensitive: false);

/// Uten det som er personlig: leverandøren (vertsnavnet og IP-adresser), brukernavn og passord i strømadressene og i
/// spørringer, e-postadresser og brukernavnet i Windows-stier (C:\Users\…).
String scrub(String text) => text
    .replaceAllMapped(_url, (m) => '${m[1]}***')
    .replaceAllMapped(_streamPath, (m) => '/${m[1]}/***/***')
    .replaceAllMapped(_query, (m) => '${m[1]}=***')
    .replaceAll(_email, '***@***')
    .replaceAll(_ip, '***')
    .replaceAllMapped(_home, (m) => '${m[1]}***');
