import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/app.dart';
import 'package:fyrlys/core/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  testWidgets('innloggingen har begge måtene å koble til på', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = Session(await SharedPreferences.getInstance());
    await session.restore();
    await tester.pumpWidget(FyrlysApp(session: session));
    await tester.pump();

    expect(find.text('Fyrlys-server'), findsOneWidget);
    expect(find.text('Adresse'), findsOneWidget);
    await tester.tap(find.text('IPTV-leverandør'));
    await tester.pump();
    expect(find.text('Brukernavn'), findsOneWidget);
    expect(find.text('Passord'), findsOneWidget);
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

    expect(find.text('NRK 1 HD'), findsOneWidget);
    expect(find.text('TV 2 HD'), findsOneWidget);
    // eventkanalen: klokkeslett og kamp på første linje, liga under
    expect(find.text('15:00  Man United - Bournemouth'), findsOneWidget);
    expect(find.text('Premier League'), findsOneWidget);

    await tester.tap(find.byTooltip('Legg til i favoritter').first);
    await tester.pump();
    expect(session.favorites.map((c) => c.id), ['101']);

    await tester.tap(find.text('★ Favoritter'));
    await tester.pump();
    expect(find.text('NRK 1 HD'), findsOneWidget);
    expect(find.text('TV 2 HD'), findsNothing);

    await tester.tap(find.text('Alle kanaler').first);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'tv 2');
    await tester.pump();
    expect(find.text('TV 2 HD'), findsOneWidget);
    expect(find.text('NRK 1 HD'), findsNothing);
  });
}
