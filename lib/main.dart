import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'core/session.dart';
import 'platform.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  if (isDesktop) await windowManager.ensureInitialized();
  final session = Session(await SharedPreferences.getInstance());
  runApp(FyrlysApp(session: session));
  unawaited(session.restore());
}
