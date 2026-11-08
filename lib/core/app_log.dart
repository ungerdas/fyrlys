import 'dart:collection';
import 'dart:io';

/// Det appen har skrevet i loggen den siste tida (debugPrint og feil), til feilrapporten. Hver linje vaskes med
/// [scrub] før den tas vare på, så adresser, brukernavn og passord aldri ligger her.
class AppLog {
  AppLog({this.max = 400});

  static final instance = AppLog();

  final int max;
  final _lines = ListQueue<String>();

  List<String> get lines => List.unmodifiable(_lines);

  /// Loggen på disk (null: bare i minnet). Hver linje skrives med en gang, så den står der om appen krasjer.
  File? _file;
  int _written = 0;

  /// Slutten av loggen fra forrige gang appen kjørte, når den ikke ble avsluttet som vanlig (krasjet, eller ble
  /// stoppet utenfra); tom ellers.
  List<String> previousRun = const [];

  /// siste linje når appen avsluttes som vanlig
  static const closedLine = '-- Fyrlys ble avsluttet --';

  /// Fra nå skrives loggen også til [file]. Det som sto der fra forrige gang, leses først: sluttet det uten
  /// [closedLine], ble appen ikke avsluttet som vanlig, og slutten blir med i feilrapporten.
  void attach(File file) {
    try {
      if (file.existsSync()) {
        final old = file.readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();
        if (old.isNotEmpty && !old.last.endsWith(closedLine)) {
          previousRun = old.length > 150 ? old.sublist(old.length - 150) : old;
        }
      }
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(_lines.isEmpty ? '' : '${_lines.join('\n')}\n', flush: true);
      _written = file.lengthSync();
      _file = file;
    } on Object {
      _file = null;
    }
  }

  /// Appen avsluttes som vanlig: neste gang vet den at det ikke var et krasj.
  void closed() => add(closedLine);

  void add(String message, {DateTime? at}) {
    final t = at ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
    for (final line in scrub(message).split('\n')) {
      if (line.trim().isEmpty) continue;
      final entry = '$stamp ${line.trimRight()}';
      _lines.add(entry);
      while (_lines.length > max) {
        _lines.removeFirst();
      }
      _write(entry);
    }
  }

  void _write(String entry) {
    final f = _file;
    if (f == null) return;
    try {
      // blir fila stor (appen har stått lenge), begynner den på nytt med det som er i minnet
      if (_written > 1 << 20) {
        f.writeAsStringSync('${_lines.join('\n')}\n', flush: true);
        _written = f.lengthSync();
        return;
      }
      final text = '$entry\n';
      f.writeAsStringSync(text, mode: FileMode.append, flush: true);
      _written += text.length;
    } on Object {
      // ikke viktig nok til å stoppe noe: videre bare i minnet
      _file = null;
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
