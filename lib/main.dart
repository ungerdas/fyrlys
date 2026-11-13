import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'build_info.dart';
import 'core/android_host.dart';
import 'core/app_log.dart';
import 'core/cache.dart';
import 'core/report.dart';
import 'core/session.dart';
import 'core/single_instance.dart';
import 'core/tizen_host.dart';
import 'core/updater.dart';
import 'l10n/tr.dart';
import 'platform.dart';
import 'theme.dart';
import 'ui/playback.dart';
import 'ui/playback_tizen.dart';
import 'ui/window_memory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _keepLog();
  try {
    await _start();
  } on Object catch (e, stack) {
    // Noe stoppet før appen kom opp (f.eks. avspilleren, som ikke kan lastes på denne maskinen): vis hva, i stedet
    // for et tomt vindu.
    AppLog.instance.add('Feil ved oppstart: $e\n${stack.toString().split('\n').take(8).join('\n')}');
    runApp(_StartupError(error: '$e'));
  }
}

Future<void> _start() async {
  // Språket fra Windows (eller telefonen) til Session har lest det du har valgt, så det oppdateringen sier før det, står på det.
  final systemLanguage = languageOfLocale(WidgetsBinding.instance.platformDispatcher.locale.languageCode);
  appLanguage = systemLanguage;
  // En oppdatering som ble lastet ned, men ikke lagt inn da appen ble lukket, legges inn før appen vises;
  // den nye utgaven starter av seg selv.
  // Android: nedlastingene i appens egen mappe (APK-en installeres derfra). TV-en: sier bare fra om nye versjoner.
  final updater = isAndroid
      ? Updater(workDir: '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}oppdatering')
      : Updater();
  if (await updater.beforeStart()) exit(0);
  // Bare én Fyrlys: starter du den en gang til, kommer vinduet som er åpent fram (før noe ryddes på disken).
  if (isPc && await SingleInstance.isSecond(onShow: () => unawaited(_bringToFront()))) exit(0);
  // Loggen også på disk, så slutten av den kommer med i feilrapporten om appen krasjer (ikke på Android: der stoppes
  // appen uten at den får vite det, og hver gang ville sett ut som et krasj; det samme på TV-en).
  if (isPc) {
    try {
      AppLog.instance
          .attach(File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}logg.txt'));
      if (AppLog.instance.previousRun.isNotEmpty) debugPrint('Forrige gang ble ikke Fyrlys avsluttet som vanlig');
    } on Object {
      // bare i minnet
    }
  }
  if (isTizen) {
    // Samsung-TV: TV-ens egen avspiller (mpv finnes ikke der), og ingen vinduer
    playbackFactory = AvplayPlayback.new;
  } else {
    MediaKit.ensureInitialized();
  }
  if (isPc) await windowManager.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // samme størrelse og plass som sist, før vinduet vises
  if (isPc) await WindowMemory.restore(prefs);
  // kanallista fra sist og bildene på disk, så appen er klar med en gang (uten mapper: hentes hver gang)
  ListCache? lists;
  try {
    lists = FileListCache(Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}lister'));
    final cache = (await getApplicationCacheDirectory()).path;
    final images = ImageStore(Directory('$cache${Platform.pathSeparator}bilder'));
    ImageStore.instance = images;
    unawaited(images.prune());
    // TV-bufferet til avspilleren (pause og spoling): det som ble liggende sist (krasj), ryddes først
    if (!isTizen) {
      final mpv = Directory('$cache${Platform.pathSeparator}mpv');
      if (mpv.existsSync()) mpv.deleteSync(recursive: true);
      mpv.createSync(recursive: true);
      MpvPlayback.cacheDir = mpv.path;
    }
  } on Object {
    // uten disk
  }
  final session = Session(
    prefs,
    listCache: lists,
    systemLanguage: systemLanguage,
  );
  runApp(FyrlysApp(session: session, updater: updater));
  unawaited(session.restore().then((_) => updater.start()));
}

/// Loggen til feilrapporten: alt som skrives med debugPrint, og feil ingen tok seg av.
void _keepLog() {
  final log = AppLog.instance;
  if (isAndroid) {
    // arkitekturen appen kjører som (android_arm64, android_arm, android_x64)
    log.add('$appBuildLabel ${Abi.current()}');
    unawaited(AndroidHost.device().then((d) {
      androidDevice = d;
      if (d != null) log.add(d);
    }));
  } else if (isTizen) {
    // Tizen-versjonen og modellen (pakken for TV-en må passe til versjonen)
    log.add('$appBuildLabel Samsung-TV');
    unawaited(tizenDevice().then((d) {
      tvDevice = d;
      if (d != null) log.add(d);
    }));
  } else {
    log.add('$appBuildLabel ${windowsName(Platform.operatingSystemVersion)}');
  }
  final original = debugPrint;
  debugPrint = (message, {wrapWidth}) {
    if (message != null) log.add(message);
    original(message, wrapWidth: wrapWidth);
  };
  final flutterError = FlutterError.onError;
  FlutterError.onError = (details) {
    log.add('Feil: ${details.exceptionAsString()}');
    flutterError?.call(details);
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    log.add('Feil: $error\n${stack.toString().split('\n').take(8).join('\n')}');
    return false;
  };
}

/// Fyrlys kom ikke i gang: hva som stoppet, og loggen (kan markeres og kopieres).
class _StartupError extends StatelessWidget {
  const _StartupError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: fyrlysTheme(Brightness.dark),
        home: Scaffold(
          body: SafeArea(
            child: Builder(
              builder: (context) => ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(tr('Fyrlys kunne ikke starte'), style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 12),
                  SelectableText(error),
                  const SizedBox(height: 24),
                  Text(tr('Send dette når du melder fra om feilen:'), style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  SelectableText(
                    AppLog.instance.lines.join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Vinduet fram, også når det var minimert.
Future<void> _bringToFront() async {
  try {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  } on Object {
    // ikke klart ennå
  }
}
