import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/session.dart';
import 'core/updater.dart';
import 'platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // En oppdatering som ble lastet ned, men ikke lagt inn da appen ble lukket, legges inn før appen vises;
  // den nye utgaven starter av seg selv.
  final updater = Updater();
  if (await updater.beforeStart()) exit(0);
  MediaKit.ensureInitialized();
  if (isDesktop) await windowManager.ensureInitialized();
  final session = Session(await SharedPreferences.getInstance());
  runApp(FyrlysApp(session: session, updater: updater));
  unawaited(session.restore());
  updater.start();
}
