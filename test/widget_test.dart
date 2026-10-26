import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/app.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/core/updater.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  testWidgets('innloggingen: M3U-lenke eller Xtream Codes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = Session(await SharedPreferences.getInstance());
    await session.restore();
    await tester.pumpWidget(FyrlysApp(session: session));
    await tester.pump();

    // M3U-lenke først: lenken og en valgfri EPG-lenke
    expect(find.text('M3U-lenke'), findsNWidgets(2));
    expect(find.text('EPG-lenke (valgfri)'), findsOneWidget);
    expect(find.text('Brukernavn'), findsNothing);
    expect(find.textContaining('Fyrlys-server'), findsNothing);
    await tester.tap(find.text('Xtream Codes'));
    await tester.pump();
    expect(find.text('Brukernavn'), findsOneWidget);
    expect(find.text('Passord'), findsOneWidget);
    expect(find.text('EPG-lenke (valgfri)'), findsNothing);
  });

  testWidgets('en M3U-liste har ikke filmer og serier: bare TV og TV-guide', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
    final session =
        Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => FakeSource(hasVod: false));
    await session.restore();
    await tester.pumpWidget(FyrlysApp(session: session));
    await tester.pumpAndSettle();
    expect(find.text('TV-guide'), findsOneWidget);
    expect(find.text('Filmer'), findsNothing);
    expect(find.text('Serier'), findsNothing);

    // smalt vindu: fanene nederst
    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(2));
  });

  testWidgets('«Se etter oppdateringer» i menyen spør GitHub', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('fyrlys-meny');
    addTearDown(() => dir.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}', 'update_server': 'http://192.168.1.10:8766'});
    final session = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => FakeSource());
    await session.restore();
    final asked = <String>[];
    final u = Updater(
      client: MockClient((r) async {
        asked.add('${r.url}');
        // samme bygg som appen: ingenting nytt
        return http.Response(
          jsonEncode({
            'name': 'Fyrlys 2.1.10',
            'body': 'Nytt\n\n<!-- bygg 5 -->',
            'assets': [
              {'name': 'Fyrlys-windows.zip', 'browser_download_url': 'https://example/w.zip', 'size': 4},
            ],
          }),
          200,
        );
      }),
      currentBuild: 5,
      assetSuffix: '-windows.zip',
      workDir: dir.path,
      canInstall: false,
      repo: 'ungerdas/fyrlys',
    );
    await tester.pumpWidget(FyrlysApp(session: session, updater: u));
    await tester.pumpAndSettle();
    // en oppdateringsserver fra før (2.1.6–2.1.10) er ryddet bort
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('update_server'), isNull);

    await tester.tap(find.byTooltip('Meny'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Oppdateringsserver'), findsNothing);
    await tester.tap(find.text('Se etter oppdateringer'));
    await tester.pumpAndSettle();
    expect(asked, ['https://api.github.com/repos/ungerdas/fyrlys/releases/latest']);
    expect(find.textContaining('Du har siste versjon'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('TV-siden: kanaler, eventkanaler, favoritter og søk', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
    final session = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => FakeSource());
    await session.restore();
    await tester.pumpWidget(FyrlysApp(session: session));
    await tester.pumpAndSettle();

    // startsiden første gang, så alle kanalene fra sidemenyen
    expect(find.text('Velkommen til Fyrlys'), findsOneWidget);
    await tester.tap(find.text('Alle kanaler').first);
    await tester.pumpAndSettle();
    expect(find.text('NRK 1 HD'), findsOneWidget);
    expect(find.text('TV 2 HD'), findsOneWidget);
    // eventkanalen: klokkeslett og kamp på første linje, liga under
    expect(find.text('15:00  Man United - Bournemouth'), findsOneWidget);
    expect(find.text('Premier League'), findsOneWidget);

    await tester.tap(find.byTooltip('Legg til i favoritter').first);
    await tester.pump();
    expect(session.favorites.map((c) => c.id), ['101']);

    await tester.tap(find.text('Favoritter'));
    await tester.pumpAndSettle();
    expect(find.text('NRK 1 HD'), findsOneWidget);
    expect(find.text('TV 2 HD'), findsNothing);

    await tester.tap(find.text('Alle kanaler').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'tv 2');
    await tester.pumpAndSettle();
    expect(find.text('TV 2 HD'), findsOneWidget);
    expect(find.text('NRK 1 HD'), findsNothing);
  });
}
