import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';

import 'core/session.dart';
import 'core/updater.dart';
import 'l10n/tr.dart';
import 'theme.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';

class FyrlysApp extends StatefulWidget {
  const FyrlysApp({super.key, required this.session, this.updater});

  final Session session;
  final Updater? updater;

  @override
  State<FyrlysApp> createState() => _FyrlysAppState();
}

class _FyrlysAppState extends State<FyrlysApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    // en nedlastet oppdatering legges inn når du lukker appen (skriptet venter til den er lukket)
    final updater = widget.updater;
    if (updater != null) await updater.apply(restart: false);
    return AppExitResponse.exit;
  }

  /// språket sidene sist ble bygget på
  String _language = appLanguage;

  /// Nytt språk: alt bygges på nytt (tekstene hentes med tr() når de bygges), uten at noe lukkes.
  void _rebuildAll() {
    void mark(Element e) {
      e.markNeedsBuild();
      e.visitChildren(mark);
    }

    if (mounted) (context as Element).visitChildren(mark);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        if (_language != appLanguage) {
          _language = appLanguage;
          WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildAll());
        }
        return _app(session);
      },
    );
  }

  Widget _app(Session session) => MaterialApp(
        title: 'Fyrlys',
        debugShowCheckedModeBanner: false,
        theme: fyrlysTheme(Brightness.light),
        darkTheme: fyrlysTheme(Brightness.dark),
        themeMode: session.themeMode,
        home: session.restoring
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : session.source == null
                ? LoginPage(session: session)
                // en ny side for hver innlogging (kategorier og filmer er ulike hos ulike leverandører)
                : HomePage(key: ValueKey('innlogging:${session.activeLogin}'), session: session, updater: widget.updater),
      );
}
