import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/models.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/theme.dart';
import 'package:fyrlys/ui/player_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// [n] segmenter à 2 sekunder (300: ti minutter)
LiveWindow _window([int n = 300]) => LiveWindow(List.filled(n, const Duration(seconds: 2)));

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
  test('spillelista: hvor langt tilbake, og hvor mange segmenter fra slutten', () {
    final w = parseLiveWindow(
      '#EXTM3U\n#EXT-X-TARGETDURATION:3\n#EXT-X-MEDIA-SEQUENCE:7\n'
      '#EXTINF:2.000,\na-000007.ts\n#EXTINF:2.5,\na-000008.ts\n#EXTINF:1.5,\na-000009.ts\n'
      '#EXTINF:2.0,\na-000010.ts\n#EXTINF:2.0,\na-000011.ts\n',
    );
    expect(w.segments.length, 5);
    // de tre siste er «direkte»: det går an å spole 2 + 2,5 sekunder tilbake
    expect(w.length, const Duration(milliseconds: 4500));
    expect(w.at(Duration.zero), (fromEnd: 3, behind: Duration.zero));
    expect(w.at(const Duration(seconds: 2)), (fromEnd: 4, behind: const Duration(milliseconds: 2500)));
    expect(w.at(const Duration(minutes: 5)), (fromEnd: 5, behind: const Duration(milliseconds: 4500)));
    expect(parseLiveWindow('').length, Duration.zero);
  });

  testWidgets('direktesending via serveren: tilbake, direkte, pause og tatt over', (tester) async {
    final (source, fake) = await _open(tester, FakeSource(timeshift: const Duration(minutes: 30), window: _window()));
    expect(fake.urls, ['http://example/101.ts']);
    expect(fake.liveFromEnds, [null]);

    // bildet har startet; vakta henter spillelista, og tidslinja kommer
    fake.moveTo(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(source.windowRequests, isNotEmpty);
    expect(find.byKey(const ValueKey('live-timeline')), findsOneWidget);
    expect(find.text('−9:54'), findsOneWidget);
    expect(find.text('DIREKTE'), findsOneWidget);

    // ←: ti sekunder tilbake, fem segmenter lenger fra slutten enn direkte
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(find.text('−0:10'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(fake.liveFromEnds.last, 8);
    // to trykk til, tett etter hverandre: 30 sekunder bak
    fake.moveTo(const Duration(seconds: 2));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(fake.liveFromEnds.last, 18);
    expect(find.text('−0:30'), findsWidgets);

    // L: direkte igjen
    fake.moveTo(const Duration(seconds: 3));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
    await tester.pump();
    await tester.pump();
    expect(fake.liveFromEnds.last, 3);

    // pause i et minutt: serveren får høre fra oss hele tiden, og vi er et minutt bak
    fake.moveTo(const Duration(seconds: 4));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(fake.playing, isFalse);
    final before = source.windowRequests.length;
    await tester.pump(const Duration(seconds: 61));
    await tester.pump();
    expect(source.windowRequests.length, greaterThan(before + 3));
    expect(find.textContaining('−1:0'), findsOneWidget);
    // spill av: åpnes på nytt der du var (et minutt = 31 segmenter tilbake)
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump();
    expect(fake.liveFromEnds.last, inInclusiveRange(33, 35));

    // noen tar over tilkoblingen mens du har pauset
    fake.moveTo(const Duration(seconds: 5));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    source.takenOver = true;
    await tester.pump(const Duration(seconds: 12));
    await tester.pump();
    expect(find.textContaining('Alle tilkoblingene er i bruk.'), findsOneWidget);
    expect(find.text('Stopp Stua og se her'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('uten tilbakespoling: ingen tidslinje, og ← gjør ingenting', (tester) async {
    final (source, fake) = await _open(tester, FakeSource());
    fake.moveTo(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('live-timeline')), findsNothing);
    expect(fake.urls.length, 1);
    expect(source.windowRequests, isEmpty);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
