import 'package:flutter/material.dart';

import 'core/session.dart';
import 'theme.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';

class FyrlysApp extends StatefulWidget {
  const FyrlysApp({super.key, required this.session});

  final Session session;

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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // tilbake i appen: favorittene kan være endret på en annen enhet imens
    if (state == AppLifecycleState.resumed) widget.session.refreshFavorites();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => MaterialApp(
        title: 'Fyrlys',
        debugShowCheckedModeBanner: false,
        theme: fyrlysTheme(Brightness.light),
        darkTheme: fyrlysTheme(Brightness.dark),
        themeMode: session.themeMode,
        home: session.restoring
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : session.source == null
                ? LoginPage(session: session)
                : HomePage(session: session),
      ),
    );
  }
}
