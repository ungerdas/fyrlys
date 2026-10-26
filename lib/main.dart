import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/cache.dart';
import 'core/fyrlys_source.dart';
import 'core/session.dart';
import 'core/updater.dart';
import 'platform.dart';
import 'ui/playback.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // En oppdatering som ble lastet ned, men ikke lagt inn da appen ble lukket, legges inn før appen vises;
  // den nye utgaven starter av seg selv.
  final updater = Updater();
  if (await updater.beforeStart()) exit(0);
  MediaKit.ensureInitialized();
  if (isDesktop) await windowManager.ensureInitialized();
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
  final session = Session(await SharedPreferences.getInstance(), listCache: lists);
  // Repoet er privat: byggene hentes via Fyrlys-serveren, som har en lesenøkkel til GitHub.
  updater.serverBase = () {
    final source = session.source;
    return source is FyrlysSource ? source.base : null;
  };
  runApp(FyrlysApp(session: session, updater: updater));
  unawaited(session.restore().then((_) => updater.start()));
}
