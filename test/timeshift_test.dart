import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/theme.dart';
import 'package:fyrlys/ui/player_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<(FakeSource, FakePlayback)> _open(WidgetTester tester, FakeSource source) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
  final session = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => source);
  await session.restore();
  await session.load();
  final fake = FakePlayback();
  await tester.pumpWidget(MaterialApp(
    theme: fyrlysTheme(Brightness.light),
    home: PlayerPage(
      session: session,
      channels: session.channels,
      index: 0,
      listTitle: 'Alle kanaler',
      playback: () => fake,
    ),
  ));
  await _settle(tester);
  return (source, fake);
}

void main() {
  testWidgets('direkte fra leverandøren: avspilleren spoler i det den har tatt vare på', (tester) async {
    final (_, fake) = await _open(tester, FakeSource(localShift: true));
    expect(fake.live, isTrue);
    // ingen tidslinje før avspilleren har sagt hva den har
    expect(find.byKey(const ValueKey('live-timeline')), findsNothing);

    // bildet har startet: ti minutter bak, tolv sekunder foran (det er direkte, for strømmen kommer i biter)
    fake.cache = (back: const Duration(minutes: 10), ahead: const Duration(seconds: 12));
    fake.moveTo(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.byKey(const ValueKey('live-timeline')), findsOneWidget);
    expect(find.text('−10:00'), findsOneWidget);
    expect(find.text('DIREKTE'), findsOneWidget);

    // ← to ganger: tjue sekunder tilbake i det avspilleren har, uten at strømmen åpnes på nytt
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(fake.relativeSeeks, [const Duration(seconds: -20)]);
    expect(fake.urls, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump();
    expect(find.text('−0:20'), findsOneWidget);

    // L: tilbake til direkte
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    expect(fake.relativeSeeks.last, const Duration(seconds: 20));

    // pause: avspilleren henter videre (her tretti sekunder), og så langt bak er du når du fortsetter, uten at
    // strømmen åpnes på nytt
    await tester.pump(const Duration(seconds: 3));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    fake.cache = (back: const Duration(minutes: 10), ahead: const Duration(seconds: 42));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.textContaining('−0:3'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(fake.urls, hasLength(1));

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('uten tilbakespoling: ingen tidslinje, og ← gjør ingenting', (tester) async {
    final (_, fake) = await _open(tester, FakeSource());
    fake.moveTo(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('live-timeline')), findsNothing);
    expect(fake.urls.length, 1);
    expect(fake.relativeSeeks, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
