import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/app.dart';
import 'package:fyrlys/core/names.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/ui/guide_view.dart';
import 'package:fyrlys/ui/playback.dart';
import 'package:fyrlys/ui/player_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Ikke pumpAndSettle mens spilleren er åpen: spinneren går så lenge kanalen laster.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Radene henter programmene når de har vært framme litt.
Future<void> _rows(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump();
}

void main() {
  test('guiden starter halvtimen før den halvtimen vi er i', () {
    expect(guideStart(DateTime(2026, 10, 25, 22, 44)), DateTime(2026, 10, 25, 22));
    expect(guideStart(DateTime(2026, 10, 25, 22, 10)), DateTime(2026, 10, 25, 21, 30));
    expect(guideStart(DateTime(2026, 10, 26, 0, 5)), DateTime(2026, 10, 25, 23, 30));
  });

  testWidgets('TV-guiden: programmer, info, avspilling, søk og kategori', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
    final source = FakeSource();
    final session = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => source);
    await session.restore();
    // en ny avspiller hver gang spilleren åpnes
    final players = <FakePlayback>[];
    playbackFactory = () {
      final p = FakePlayback();
      players.add(p);
      return p;
    };
    addTearDown(() => playbackFactory = MpvPlayback.new);

    await tester.pumpWidget(FyrlysApp(session: session));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TV-guide'));
    await tester.pumpAndSettle();
    await _rows(tester);

    expect(find.text('Alle kanaler (3)'), findsOneWidget);
    expect(find.text('Til nå'), findsOneWidget);
    // tidslinja: halvtimen før denne halvtimen og bortover
    expect(find.text(hhmm(guideStart(DateTime.now()))), findsOneWidget);
    expect(find.text('NRK 1 HD'), findsOneWidget);
    expect(find.text('Dagsrevyen'), findsOneWidget);
    expect(find.text('Sportsrevyen'), findsOneWidget);
    // eventkanalen: det som står i navnet; TV 2: ingen programmer
    expect(find.text('Premier League'), findsOneWidget);
    expect(find.text('Ingen programinformasjon'), findsOneWidget);

    // det som kommer senere: hva det er, og «Se kanalen»
    await tester.tap(find.text('Sportsrevyen'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('NRK 1 HD  ·  '), findsOneWidget);
    await tester.tap(find.text('Se kanalen'));
    await _settle(tester);
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(players.last.urls, ['http://example/101.ts']);
    expect(source.opened, ['101']);

    Navigator.of(tester.element(find.byType(PlayerPage))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(PlayerPage), findsNothing);

    // det som går nå: spilles med en gang
    await tester.tap(find.text('Dagsrevyen'));
    await _settle(tester);
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(players.last.urls, ['http://example/101.ts']);
    Navigator.of(tester.element(find.byType(PlayerPage))).pop();
    await tester.pumpAndSettle();

    // kanalnavnet: også rett til kanalen
    await tester.tap(find.text('TV 2 HD'));
    await _settle(tester);
    expect(players.last.urls, ['http://example/102.ts']);
    Navigator.of(tester.element(find.byType(PlayerPage))).pop();
    await tester.pumpAndSettle();

    // søket øverst gjelder kanalene i guiden
    await tester.enterText(find.byType(TextField), 'nrk');
    await tester.pump();
    await _rows(tester);
    expect(find.text('NRK 1 HD'), findsOneWidget);
    expect(find.text('TV 2 HD'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    await _rows(tester);

    // en kategori, som huskes til neste gang
    await tester.tap(find.text('Alle kanaler (3)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sport (1)').last);
    await tester.pumpAndSettle();
    await _rows(tester);
    expect(find.text('Premier League'), findsOneWidget);
    expect(find.text('Dagsrevyen'), findsNothing);
    expect(session.guideCategory, '2');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('TV-guiden uten favoritter: forklaring', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}', 'guide_cat': 'fav'});
    final session = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => FakeSource());
    await session.restore();
    await tester.pumpWidget(FyrlysApp(session: session));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TV-guide'));
    await tester.pumpAndSettle();
    expect(find.text('★ Favorittkanaler (0)'), findsOneWidget);
    expect(find.textContaining('Ingen favoritter ennå'), findsOneWidget);
  });
}
