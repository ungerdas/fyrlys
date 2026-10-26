import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'build_info.dart';
import 'core/app_log.dart';
import 'core/cache.dart';
import 'core/session.dart';
import 'core/single_instance.dart';
import 'core/updater.dart';
import 'l10n/tr.dart';
import 'ui/playback.dart';
import 'ui/window_memory.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _keepLog();
  // En oppdatering som ble lastet ned, men ikke lagt inn da appen ble lukket, legges inn før appen vises;
  // den nye utgaven starter av seg selv.
  final updater = Updater();
  if (await updater.beforeStart()) exit(0);
  // Bare én Fyrlys: starter du den en gang til, kommer vinduet som er åpent fram (før noe ryddes på disken).
  if (await SingleInstance.isSecond(onShow: () => unawaited(_bringToFront()))) exit(0);
  MediaKit.ensureInitialized();
  await windowManager.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // samme størrelse og plass som sist, før vinduet vises
  await WindowMemory.restore(prefs);
  // kanallista fra sist og bildene på disk, så appen er klar med en gang (uten mapper: hentes hver gang)
  ListCache? lists;
  try {
    lists = FileListCache(Directory('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}lister'));
    final cache = (await getApplicationCacheDirectory()).path;
    final images = ImageStore(Directory('$cache${Platform.pathSeparator}bilder'));
    ImageStore.instance = images;
    unawaited(images.prune());
    // TV-bufferet til avspilleren (pause og spoling): det som ble liggende sist (krasj), ryddes først
    final mpv = Directory('$cache${Platform.pathSeparator}mpv');
    if (mpv.existsSync()) mpv.deleteSync(recursive: true);
    mpv.createSync(recursive: true);
    MpvPlayback.cacheDir = mpv.path;
  } on Object {
    // uten disk
  }
  final session = Session(
    prefs,
    listCache: lists,
    systemLanguage: languageOfLocale(WidgetsBinding.instance.platformDispatcher.locale.languageCode),
  );
  runApp(FyrlysApp(session: session, updater: updater));
  unawaited(session.restore().then((_) => updater.start()));
}

/// Loggen til feilrapporten: alt som skrives med debugPrint, og feil ingen tok seg av.
void _keepLog() {
  final log = AppLog.instance..add('$appBuildLabel ${Platform.operatingSystemVersion}');
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
