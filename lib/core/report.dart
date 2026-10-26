import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../build_info.dart';
import '../l10n/tr.dart';
import 'app_log.dart';
import 'session.dart';
import 'updater.dart';

/// Feilrapporten: det som trengs for å finne ut av en feil (versjon, Windows, innstillinger, abonnementet og loggen),
/// uten det som er personlig: navnene på innloggingene, leverandøren, brukernavn og passord ([scrub]).
Future<String> buildReport(Session s, {Updater? updater, DateTime? now, String? windows, String? updateLog}) async {
  final t = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  String onOff(bool v) => v ? tr('på') : tr('av');
  final out = StringBuffer()
    ..writeln(tr('Fyrlys – feilrapport'))
    ..writeln('${tr('Laget')}: ${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}')
    ..writeln('${tr('Versjon')}: $appBuildLabel'
        '${appBuild.isEmpty ? '' : ' (${tr('bygg')} $appBuild${appCommit.isEmpty ? '' : ', ${_short(appCommit)}'})'}')
    ..writeln('Windows: ${windows ?? Platform.operatingSystemVersion}')
    ..writeln('${tr('Språk')}: $appLanguage');

  out.writeln();
  final current = s.currentLogin;
  out.writeln('${tr('Innlogginger')}: ${s.logins.length}'
      '${s.logins.isEmpty ? '' : ' (${[for (final l in s.logins) l.kindName].join(', ')})'}'
      '${current == null ? '' : ' · ${tr('i bruk')}: ${current.kindName}'}');
  final src = s.source;
  if (src != null) {
    try {
      final a = await src.account().timeout(const Duration(seconds: 8));
      out.writeln('${tr('Abonnement')}: ${[
        if (a.status.isNotEmpty) a.status,
        if (a.maxConnections == 1) tr('1 tilkobling'),
        if (a.maxConnections > 1) tr('{n} tilkoblinger', {'n': a.maxConnections}),
        tr('{n} i bruk', {'n': a.activeConnections}),
      ].join(' · ')}');
    } on Object catch (e) {
      out.writeln('${tr('Abonnement')}: ${tr('fikk ikke svar')} ($e)');
    }
    final archive = s.channels.where((c) => c.hasArchive).length;
    out.writeln('${tr('Kanaler')}: ${s.channels.length} · ${tr('kategorier')}: ${s.categories.length}'
        ' · ${tr('TV-arkiv')}: $archive · ${tr('filmer og serier')}: ${onOff(src.hasVod)}');
  }
  if (s.error != null) out.writeln('${tr('Feil i listene')}: ${s.error}');

  out.writeln();
  final picture = s.picture;
  final languages = s.languages;
  out
    ..writeln('${tr('Tema')}: ${s.themeMode.name}')
    ..writeln('${tr('Fjern striper (deinterlacing)')}: ${onOff(picture.deinterlace)}'
        ' · ${tr('Jevn bevegelse')}: ${onOff(picture.smooth)}')
    ..writeln('${tr('Språk for lyd og undertekster')}: ${languages.isEmpty ? '–' : languages.summary}');
  if (updater != null) {
    out.writeln('${tr('Oppdatering')}: ${updater.state.name}${updater.error == null ? '' : ' (${updater.error})'}');
  }

  out
    ..writeln()
    ..writeln('## ${tr('Logg')}');
  final lines = AppLog.instance.lines;
  if (lines.isEmpty) out.writeln('–');
  lines.forEach(out.writeln);

  final log = updateLog ?? await _tail(updater);
  if (log != null && log.trim().isNotEmpty) {
    out
      ..writeln()
      ..writeln('## ${tr('Oppdateringsloggen')}')
      ..writeln(log.trimRight());
  }
  // en gang til over alt, også det som ikke kom fra loggen (feilmeldinger fra leverandøren o.l.)
  return scrub(out.toString()).replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
}

String _short(String commit) => commit.length > 7 ? commit.substring(0, 7) : commit;

/// De siste 40 linjene i oppdateringsloggen.
Future<String?> _tail(Updater? updater) async {
  if (updater == null) return null;
  try {
    final file = File('${updater.workDir}${Platform.pathSeparator}oppdatering.log');
    if (!file.existsSync()) return null;
    final lines = await file.readAsLines();
    return lines.skip(lines.length > 40 ? lines.length - 40 : 0).join('\n');
  } on Object {
    return null;
  }
}

/// Mappen rapporten lagres i: Nedlastinger (byttes ut i testene).
Future<Directory> Function() reportDirectory = () async =>
    await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();

/// Viser fila i Utforsker (byttes ut i testene).
Future<void> Function(String path) showInExplorer = (path) async {
  if (!Platform.isWindows) return;
  try {
    // Utforsker svarer 1 også når det går bra
    await Process.start('explorer.exe', ['/select,', path]);
  } on Object {
    // da finner du den selv i Nedlastinger
  }
};

/// Åpner en nettadresse i nettleseren (byttes ut i testene).
Future<void> Function(String url) openUrl = (url) async {
  if (!Platform.isWindows) return;
  try {
    await Process.start('explorer.exe', [url]);
  } on Object {
    // ingen nettleser
  }
};

/// Lagrer rapporten som «Fyrlys-feilrapport-2026-10-26-2114.txt» og gir fila.
Future<File> saveReport(String text, {DateTime? now}) async {
  final t = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final dir = await reportDirectory();
  final name = 'Fyrlys-${tr('feilrapport')}-${t.year}-${two(t.month)}-${two(t.day)}-${two(t.hour)}${two(t.minute)}.txt';
  final file = File('${dir.path}${Platform.pathSeparator}$name');
  await file.writeAsString(text, flush: true);
  return file;
}
