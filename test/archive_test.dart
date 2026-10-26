import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/app.dart';
import 'package:fyrlys/core/models.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/theme.dart';
import 'package:fyrlys/ui/archive_page.dart';
import 'package:fyrlys/ui/playback.dart';
import 'package:fyrlys/ui/player_page.dart';
import 'package:fyrlys/ui/vod_player_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Ikke pumpAndSettle mens en spiller er åpen: spinneren går så lenge den laster.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// En ny falsk avspiller hver gang en spiller åpnes.
List<FakePlayback> _players() {
  final players = <FakePlayback>[];
  playbackFactory = () {
    final p = FakePlayback();
    players.add(p);
    return p;
  };
  addTearDown(() => playbackFactory = MpvPlayback.new);
  return players;
}

Future<(Session, FakeSource)> _session() async {
  SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
  final source = FakeSource(withArchive: true);
  final session = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => source);
  await session.restore();
  await session.load();
  return (session, source);
}

int _epoch(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

void main() {
  test('dagene i arkivet', () {
    final now = DateTime(2026, 10, 26, 21);
    expect(archiveDay(DateTime(2026, 10, 26, 8), now), 'I dag');
    expect(archiveDay(DateTime(2026, 10, 25, 23), now), 'I går');
    expect(archiveDay(DateTime(2026, 10, 24, 20), now), 'Lørdag 24. oktober');
    final e = EpgEntry(title: 'Debatten', start: DateTime(2026, 10, 25, 20), stop: DateTime(2026, 10, 25, 21));
    expect(archiveWhen(e, now), 'i går 20:00–21:00');
  });

  testWidgets('TV-guiden: arkivet for en kanal, programmene og spilleren', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final (session, source) = await _session();
    final players = _players();
    await tester.pumpWidget(FyrlysApp(session: session));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TV-guide'));
    await tester.pumpAndSettle();

    // bare NRK 1 har arkiv
    expect(find.byTooltip('TV-arkiv'), findsOneWidget);
    await tester.tap(find.byTooltip('TV-arkiv'));
    await tester.pumpAndSettle();
    expect(find.byType(ArchivePage), findsOneWidget);
    expect(source.archiveRequests, ['101']);
    expect(find.text('TV-arkiv · 7 dager tilbake'), findsOneWidget);
    expect(find.text('I GÅR'), findsOneWidget);
    expect(find.text('Går nå'), findsOneWidget);
    expect(find.text('Ikke i arkivet'), findsOneWidget);
    expect(find.text('20:00–21:00'), findsOneWidget);

    // et program det ikke går an å se
    await tester.tap(find.text('Ikke lagret'));
    await tester.pump();
    expect(find.byType(VodPlayerPage), findsNothing);

    await tester.tap(find.text('Debatten'));
    await _settle(tester);
    expect(find.byType(VodPlayerPage), findsOneWidget);
    final p = players.last;
    expect(p.live, isTrue);
    final debatt = 'http://example/arkiv/101/${_epoch(FakeSource.evening(1))}';
    expect(p.urls, ['$debatt/0.m3u8']);
    expect(find.text('Debatten'), findsOneWidget);
    expect(find.text('NRK 1 HD · i går 20:00–21:00'), findsOneWidget);
    expect(find.text('1:00:00'), findsOneWidget);

    // HLS virket ikke: MPEG-TS
    p.fail('HTTP 404');
    await _settle(tester);
    expect(p.urls, ['$debatt/0.m3u8', '$debatt/0.ts']);
    p.moveTo(const Duration(seconds: 30));
    await _settle(tester);
    expect(find.text('0:30'), findsOneWidget);

    // → i det avspilleren har hentet
    p.cache = (back: const Duration(seconds: 30), ahead: const Duration(minutes: 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 600));
    expect(p.relativeSeeks, [const Duration(seconds: 10)]);
    expect(p.urls, hasLength(2));

    // lenger enn det: åpnes på nytt fra minuttet (MPEG-TS, som virket), og hopper fram når det er hentet
    p.cache = null;
    p.moveTo(const Duration(seconds: 40));
    for (var i = 0; i < 3; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    await tester.pump(const Duration(milliseconds: 600));
    expect(p.urls.last, '$debatt/1.ts');
    expect(find.text('1:10'), findsOneWidget);
    p.moveTo(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('1:01'), findsOneWidget);
    p.cache = (back: const Duration(seconds: 1), ahead: const Duration(seconds: 30));
    await tester.pump(const Duration(milliseconds: 600));
    expect(p.relativeSeeks.last, const Duration(seconds: 9));

    // ferdig: husket som sett, og videre til neste program (det som går nå, fra start)
    p.moveTo(const Duration(minutes: 59));
    await tester.pump();
    p.finish();
    await tester.pump();
    expect(find.text('Neste: Dagsrevyen'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(p.urls.last, endsWith('/0.ts'));
    expect(p.urls.last, isNot(startsWith(debatt)));
    expect(session.watched('arkiv:101:${_epoch(FakeSource.evening(1))}'), 1.0);

    Navigator.of(tester.element(find.byType(VodPlayerPage))).pop();
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ArchivePage), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsWidgets);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('spilleren: «Se fra start» og TV-arkivet stopper direktesendingen imens', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final (session, source) = await _session();
    final players = _players();
    final live = FakePlayback();
    await tester.pumpWidget(MaterialApp(
      theme: fyrlysTheme(Brightness.light),
      home: PlayerPage(session: session, channels: session.channels, index: 0, playback: () => live),
    ));
    await _settle(tester);
    expect(live.urls, ['http://example/101.ts']);
    live.moveTo(const Duration(seconds: 1));
    await _settle(tester);

    // Dagsrevyen begynte for ti minutter siden
    expect(find.text('Se fra start'), findsOneWidget);
    await tester.tap(find.text('Se fra start'));
    await _settle(tester);
    expect(find.byType(VodPlayerPage), findsOneWidget);
    expect(live.playing, isFalse);
    expect(players.single.urls.single, startsWith('http://example/arkiv/101/'));
    expect(players.single.urls.single, endsWith('/0.m3u8'));

    // tilbake: direkte igjen
    Navigator.of(tester.element(find.byType(VodPlayerPage))).pop();
    await _settle(tester);
    expect(live.urls, ['http://example/101.ts', 'http://example/101.ts']);
    expect(live.playing, isTrue);

    // arkivet (A), og tilbake
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ArchivePage), findsOneWidget);
    expect(live.playing, isFalse);
    Navigator.of(tester.element(find.byType(ArchivePage))).pop();
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 400));
    expect(live.urls, hasLength(3));

    // TV 2 har ikke arkiv
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(milliseconds: 700));
    await _settle(tester);
    expect(live.urls.last, 'http://example/102.ts');
    expect(find.text('Se fra start'), findsNothing);
    expect(find.byTooltip('TV-arkiv (A)'), findsNothing);
    expect(source.opened.last, '102');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
