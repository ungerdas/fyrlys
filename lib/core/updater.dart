import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../build_info.dart';

class UpdateException implements Exception {
  const UpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// En nyere utgave av appen: testbygget fra main på GitHub.
class UpdateInfo {
  const UpdateInfo({required this.build, required this.title, required this.url, required this.size, this.notes = ''});

  final int build;

  /// «Fyrlys 0.1.0 · bygg 7 (abc1234)»
  final String title;
  final String url;
  final int size;

  /// siste endringer, fra releasen
  final String notes;
}

/// Leser releasen (fra GitHub eller Fyrlys-serveren, samme form): byggnummeret står i navnet, og fila for denne
/// plattformen blant vedleggene. Relative adresser (serveren svarer «download/<fil>») løses mot [base].
UpdateInfo? parseRelease(Object? json, String suffix, {Uri? base}) {
  if (json is! Map) return null;
  final title = '${json['name'] ?? ''}';
  final build = int.tryParse(RegExp(r'bygg (\d+)').firstMatch(title)?.group(1) ?? '');
  final assets = json['assets'];
  if (build == null || assets is! List) return null;
  for (final a in assets) {
    if (a is! Map) continue;
    final name = '${a['name'] ?? ''}';
    final url = a['browser_download_url'];
    final size = a['size'];
    if (name.endsWith(suffix) && url is String) {
      return UpdateInfo(
        build: build,
        title: title,
        url: base == null ? url : base.resolve(url).toString(),
        size: size is int ? size : 0,
        notes: '${json['body'] ?? ''}'.trim(),
      );
    }
  }
  return null;
}

enum UpdateState { idle, checking, available, downloading, ready, failed }

/// Oppdaterer appen fra testbyggene (releasen «testbygg», som CI lager ved hver endring på main). Repoet er
/// privat, så byggene hentes via Fyrlys-serveren når appen er logget inn der (serveren har en lesenøkkel til
/// GitHub); ellers spørres GitHub direkte, som bare virker om repoet er offentlig.
/// Ser etter nye bygg ved oppstart og hver 6. time, laster ned i bakgrunnen og legger inn når appen lukkes
/// (eller med «Start på nytt nå»). Ble appen ikke lukket som vanlig, legges oppdateringen inn neste gang den
/// starter. Bare på Windows, og bare for bygg fra GitHub Actions (egne bygg har ikke byggnummer).
class Updater extends ChangeNotifier {
  Updater({
    http.Client? client,
    int? currentBuild,
    String? assetSuffix,
    String? workDir,
    bool? canInstall,
    String? repo,
  })  : _client = client ?? http.Client(),
        currentBuild = currentBuild ?? int.tryParse(appBuild),
        assetSuffix = assetSuffix ?? (Platform.isWindows ? '-windows.zip' : null),
        canInstall = canInstall ?? Platform.isWindows,
        repo = repo ?? appRepo,
        workDir = workDir ?? _defaultWorkDir();

  final http.Client _client;

  /// bygget som kjører (null for egne bygg, som ikke oppdateres)
  final int? currentBuild;

  /// slutten på filnavnet for denne plattformen, f.eks. «-windows.zip» (null: ingen oppdatering her)
  final String? assetSuffix;

  /// kan legge inn oppdateringen selv (Windows)
  final bool canInstall;
  final String repo;

  /// nedlastinger og skriptet, i %LOCALAPPDATA%\Fyrlys\oppdatering
  final String workDir;

  UpdateState state = UpdateState.idle;
  UpdateInfo? available;
  double progress = 0;
  String? error;

  /// en kort beskjed i banneret, f.eks. at appen nettopp ble oppdatert
  String? notice;

  /// adressen til Fyrlys-serveren appen er logget inn på (null: spør GitHub direkte)
  String? Function()? serverBase;

  /// hvem vi spør, til feilmeldingene
  String _via = 'GitHub';
  Timer? _first;
  Timer? _timer;

  bool get enabled => currentBuild != null && assetSuffix != null;

  static String _defaultWorkDir() {
    final sep = Platform.pathSeparator;
    final base = Platform.environment['LOCALAPPDATA'];
    if (base != null && base.isNotEmpty) return '$base${sep}Fyrlys${sep}oppdatering';
    return '${Directory.systemTemp.path}${sep}fyrlys-oppdatering';
  }

  String _path(String name) => '$workDir${Platform.pathSeparator}$name';

  void _set(UpdateState s) {
    state = s;
    notifyListeners();
  }

  String _describe(Object e) => switch (e) {
        UpdateException(:final message) => message,
        TimeoutException() => '$_via svarte ikke',
        SocketException() => 'fikk ikke kontakt med $_via',
        FileSystemException(:final message, :final path) => path == null ? message : '$message ($path)',
        _ => '$e',
      };

  /// Ser etter oppdateringer litt etter oppstart, og så hver 6. time.
  void start() {
    if (!enabled) return;
    _first?.cancel();
    _timer?.cancel();
    _first = Timer(const Duration(seconds: 8), () => unawaited(check()));
    _timer = Timer.periodic(const Duration(hours: 6), (_) => unawaited(check()));
  }

  /// Spør Fyrlys-serveren (eller GitHub) etter siste testbygg. Er det nyere, lastes det ned med en gang (Windows).
  /// Med [manual] kastes en [UpdateException] med forklaringen når det ikke går; ellers prøves det igjen senere.
  Future<UpdateInfo?> check({bool manual = false}) async {
    if (!enabled || state == UpdateState.checking || state == UpdateState.downloading) return available;
    final before = state;
    _set(UpdateState.checking);
    final server = serverBase?.call();
    _via = server != null ? 'Fyrlys-serveren' : 'GitHub';
    final url = Uri.parse(
      server != null ? '$server/api/app/release' : 'https://api.github.com/repos/$repo/releases/tags/testbygg',
    );
    try {
      final r = await _client.get(
        url,
        headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'Fyrlys'},
      ).timeout(const Duration(seconds: 20));
      if (r.statusCode == 404) {
        available = null;
        _set(UpdateState.idle);
        return null;
      }
      if (r.statusCode != 200) throw UpdateException(_serverError(r) ?? '$_via svarte ${r.statusCode}');
      final info = parseRelease(jsonDecode(r.body), assetSuffix!, base: url);
      if (info == null || info.build <= currentBuild!) {
        available = null;
        error = null;
        _set(UpdateState.idle);
        return null;
      }
      available = info;
      error = null;
      if (await _isDownloaded(info)) {
        _set(UpdateState.ready);
      } else {
        _set(UpdateState.available);
        if (canInstall) unawaited(download());
      }
      return info;
    } on Object catch (e) {
      _set(before == UpdateState.checking ? UpdateState.idle : before);
      if (manual) throw UpdateException(_describe(e));
      return null;
    }
  }

  /// Fyrlys-serveren forklarer feil som {"error": …}, f.eks. at den mangler GitHub-nøkkelen.
  static String? _serverError(http.Response r) {
    try {
      final j = jsonDecode(r.body);
      if (j is Map && j['error'] is String) return j['error'] as String;
    } on FormatException {
      // ikke JSON
    }
    return null;
  }

  Future<bool> _isDownloaded(UpdateInfo info) async {
    try {
      final j = jsonDecode(await File(_path('klar.json')).readAsString());
      if (j is! Map || j['build'] != info.build) return false;
      final zip = File('${j['zip']}');
      return await zip.exists() && await zip.length() == j['size'];
    } on Object {
      return false;
    }
  }

  /// Laster ned bygget i bakgrunnen. Når det er ferdig, står det i klar.json.
  Future<void> download() async {
    final info = available;
    if (info == null || state == UpdateState.downloading) return;
    progress = 0;
    error = null;
    _set(UpdateState.downloading);
    try {
      await _checkWritable();
      final sep = Platform.pathSeparator;
      final dir = Directory(_path('bygg-${info.build}'));
      await dir.create(recursive: true);
      final part = File('${dir.path}${sep}Fyrlys.zip.part');
      final request = http.Request('GET', Uri.parse(info.url))..headers['User-Agent'] = 'Fyrlys';
      final response = await _client.send(request).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw UpdateException('nedlastingen svarte ${response.statusCode}');
      final total = info.size > 0 ? info.size : (response.contentLength ?? 0);
      final sink = part.openWrite();
      var got = 0;
      var shown = 0.0;
      try {
        await for (final chunk in response.stream.timeout(const Duration(seconds: 60))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0 && got / total - shown >= 0.01) {
            shown = got / total;
            progress = shown;
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      if (info.size > 0 && got != info.size) throw const UpdateException('nedlastingen ble ikke fullført');
      final zip = await part.rename('${dir.path}${sep}Fyrlys.zip');
      await File(_path('klar.json')).writeAsString(
        jsonEncode({'build': info.build, 'title': info.title, 'zip': zip.path, 'size': got}),
      );
      progress = 1;
      _set(UpdateState.ready);
    } on Object catch (e) {
      error = 'Oppdateringen ble ikke lastet ned: ${_describe(e)}';
      _set(UpdateState.failed);
    }
  }

  /// Fyrlys må ligge i en mappe du kan skrive til (ikke Programfiler) for å kunne oppdatere seg selv.
  Future<void> _checkWritable() async {
    if (!canInstall) return;
    final dir = File(Platform.resolvedExecutable).parent;
    final probe = File('${dir.path}${Platform.pathSeparator}.fyrlys-skrivetest');
    try {
      await probe.writeAsString('ok');
      await probe.delete();
    } on FileSystemException {
      throw UpdateException(
        'Fyrlys kan ikke oppdatere seg selv i ${dir.path}. Flytt mappen til et sted du eier, f.eks. Dokumenter.',
      );
    }
  }

  /// Legger inn en nedlastet oppdatering: et lite PowerShell-skript venter til Fyrlys er lukket, pakker ut den
  /// nye utgaven over den gamle og starter den igjen ([restart]) eller ikke (når du lukker appen selv).
  /// klar.json slettes før skriptet startes, så en oppdatering som feiler aldri gir en løkke.
  Future<bool> apply({required bool restart}) async {
    final current = currentBuild;
    if (!canInstall || current == null) return false;
    final ready = File(_path('klar.json'));
    try {
      if (!await ready.exists()) return false;
      final j = jsonDecode(await ready.readAsString());
      await ready.delete();
      if (j is! Map) return false;
      final build = j['build'];
      final zip = File('${j['zip']}');
      if (build is! int || build <= current || !await zip.exists() || await zip.length() != j['size']) return false;
      final exe = File(Platform.resolvedExecutable);
      final script = File(_path('oppdater.ps1'));
      await script.writeAsString(_script);
      await _log('Fyrlys bygg $current (prosess $pid) starter oppdateringen til bygg $build');
      // Vanlig modus, ikke «detached»: Dart starter da prosessen helt uten konsoll (DETACHED_PROCESS), og der
      // kommer ikke Windows PowerShell i gang. I vanlig modus får den en skjult konsoll (CREATE_NO_WINDOW), og
      // den lever videre når Fyrlys avslutter. i-gang.txt skrives av skriptet selv, så et skript som ikke
      // starter aldri hindrer appen i å starte.
      final process = await Process.start(
        'powershell.exe',
        [
          '-NoProfile',
          '-NonInteractive',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          script.path,
          '-ProcessId',
          '$pid',
          '-Zip',
          zip.path,
          '-Target',
          exe.parent.path,
          '-Exe',
          exe.path,
          '-Work',
          workDir,
          if (restart) '-Restart',
        ],
      );
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      return true;
    } on Object catch (e) {
      await _log('Fikk ikke startet oppdateringen: $e');
      error = 'Oppdateringen ble ikke lagt inn: ${_describe(e)}';
      _set(UpdateState.failed);
      return false;
    }
  }

  /// En linje i oppdatering.log, sammen med det skriptet skriver.
  Future<void> _log(String text) async {
    try {
      final now = DateTime.now().toIso8601String().substring(0, 19).replaceFirst('T', ' ');
      await File(_path('oppdatering.log')).writeAsString('$now $text\r\n', mode: FileMode.append);
    } on Object {
      // loggen er bare til hjelp
    }
  }

  /// «Start på nytt nå»: legger inn oppdateringen og avslutter, så starter den nye utgaven av seg selv.
  Future<void> restartNow() async {
    if (await apply(restart: true)) exit(0);
  }

  /// Før appen vises. true betyr at den skal avslutte med en gang: enten legges en oppdatering inn nå (en
  /// nedlastet oppdatering som ikke ble lagt inn da appen ble lukket, og den nye utgaven starter av seg selv),
  /// eller så er en oppdatering i ferd med å bli lagt inn (appen ble startet midt i).
  Future<bool> beforeStart() async {
    final current = currentBuild;
    if (!canInstall || current == null) return false;
    try {
      final busy = File(_path('i-gang.txt'));
      if (await busy.exists()) {
        if (DateTime.now().difference(await busy.lastModified()) < const Duration(seconds: 90)) return true;
        await busy.delete();
      }
      await _readResult(current);
      if (await apply(restart: true)) return true;
      await _cleanUp(current);
    } on Object {
      // oppdateringen skal aldri hindre appen i å starte
    }
    return false;
  }

  /// Svaret fra skriptet sist: vises i banneret.
  Future<void> _readResult(int current) async {
    final f = File(_path('resultat.txt'));
    if (!await f.exists()) return;
    final text = utf8.decode(await f.readAsBytes(), allowMalformed: true).trim();
    await f.delete();
    if (text.startsWith('feil')) {
      error = 'Oppdateringen ble ikke lagt inn: ${text.substring(text.indexOf(':') + 1).trim()}';
      state = UpdateState.failed;
    } else if (text == 'ok') {
      notice = 'Fyrlys er oppdatert til bygg $current${appCommit.isEmpty ? '' : ' ($appCommit)'}.';
    }
  }

  /// Fjerner nedlastinger av bygg som allerede er lagt inn.
  Future<void> _cleanUp(int current) async {
    final dir = Directory(workDir);
    if (!await dir.exists()) return;
    await for (final e in dir.list()) {
      final m = RegExp(r'bygg-(\d+)$').firstMatch(e.path);
      final b = m == null ? null : int.tryParse(m.group(1)!);
      if (b != null && b <= current) await e.delete(recursive: true);
    }
  }

  /// Lukker banneret (beskjed eller feil).
  void dismiss() {
    notice = null;
    if (state == UpdateState.failed) {
      error = null;
      state = UpdateState.idle;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _first?.cancel();
    _timer?.cancel();
    _client.close();
    super.dispose();
  }
}

/// Skriptet som legger inn oppdateringen etter at Fyrlys er lukket. Bare ASCII: Windows PowerShell 5 leser
/// skript uten BOM som ANSI.
const _script = r'''
param(
  [int]$ProcessId,
  [string]$Zip,
  [string]$Target,
  [string]$Exe,
  [string]$Work,
  [switch]$Restart
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$log = Join-Path $Work 'oppdatering.log'
$result = Join-Path $Work 'resultat.txt'
$busy = Join-Path $Work 'i-gang.txt'
Set-Content -LiteralPath $busy -Value (Get-Date -Format o)
function Write-Log([string]$text) {
  Add-Content -LiteralPath $log -Value ((Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + ' ' + $text)
}
try {
  Write-Log "Venter til Fyrlys ($ProcessId) er lukket"
  Wait-Process -Id $ProcessId -Timeout 120 -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 500
  $new = Join-Path $Work 'ny'
  if (Test-Path -LiteralPath $new) { Remove-Item -LiteralPath $new -Recurse -Force }
  Write-Log "Pakker ut $Zip"
  Expand-Archive -LiteralPath $Zip -DestinationPath $new -Force
  Write-Log "Kopierer til $Target"
  & robocopy.exe $new $Target /E /R:5 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "robocopy feilet med kode $LASTEXITCODE" }
  Remove-Item -LiteralPath $new -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath (Split-Path -Parent $Zip) -Recurse -Force -ErrorAction SilentlyContinue
  Set-Content -LiteralPath $result -Value 'ok' -Encoding UTF8
  Write-Log 'Ferdig'
} catch {
  Set-Content -LiteralPath $result -Value ('feil: ' + $_.Exception.Message) -Encoding UTF8
  Write-Log ('Feil: ' + $_.Exception.Message)
} finally {
  Remove-Item -LiteralPath $busy -Force -ErrorAction SilentlyContinue
}
if ($Restart) {
  try {
    Start-Process -FilePath $Exe -WorkingDirectory $Target
    Write-Log 'Startet Fyrlys igjen'
  } catch {
    Write-Log ('Fikk ikke startet Fyrlys: ' + $_.Exception.Message)
  }
}
''';
