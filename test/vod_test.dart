import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/app.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/ui/playback.dart';
import 'package:fyrlys/ui/vod_player_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

Future<(Session, FakeSource)> _start(WidgetTester tester, {Map<String, Object> prefs = const {}}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}', ...prefs});
  final source = FakeSource();
  final session = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => source);
  await session.restore();
  await tester.pumpWidget(FyrlysApp(session: session));
  await tester.pumpAndSettle();
  return (session, source);
}

/// Ikke pumpAndSettle mens spilleren er åpen: spinneren går så lenge filmen laster.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

FakePlayback _fakePlayback({Duration length = const Duration(minutes: 100)}) {
  final fake = FakePlayback()..length = length;
  playbackFactory = () => fake;
  addTearDown(() => playbackFactory = MpvPlayback.new);
  return fake;
}

void main() {
  testWidgets('filmer: plakater, søk, kategori og avspilling fra detaljsiden', (tester) async {
    final (_, source) = await _start(tester);
    final fake = _fakePlayback();

    await tester.tap(find.text('Filmer'));
    await tester.pumpAndSettle();
    expect(find.text('Fyrlyset'), findsOneWidget);
    expect(find.text('Nordlys'), findsOneWidget);
    expect(find.text('2024  ★ 7,5'), findsOneWidget);
    expect(find.text('Alle kategorier (3)'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nord');
    await tester.pump(); // søket når lista, og pausen på 350 ms begynner
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Nordlys'), findsOneWidget);
    expect(find.text('Fyrlyset'), findsNothing);
    expect(source.pageRequests.last, 'vod::nord::0');

    await tester.enterText(find.byType(TextField), '');
    await tester.pump(); // søket når lista, og pausen på 350 ms begynner
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fyrlyset'));
    await tester.pumpAndSettle();
    expect(find.text('En film om et fyr.'), findsOneWidget);
    expect(find.text('Skuespillere: Kari Nordmann'), findsOneWidget);
    expect(find.textContaining('01:45:00'), findsOneWidget);

    await tester.tap(find.text('Spill av'));
    await _settle(tester);
    expect(fake.urls, ['http://example/movie/201.mkv']);
    expect(find.byType(VodPlayerPage), findsOneWidget);
    expect(find.text('Fyrlyset'), findsWidgets);

    // → spoler ti sekunder fram
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(fake.seeks, [const Duration(seconds: 10)]);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('fortsett der du slapp, eller fra begynnelsen', (tester) async {
    final (session, _) = await _start(tester);
    final fake = _fakePlayback();
    session.saveResume('film:201', const Duration(minutes: 12, seconds: 5), const Duration(minutes: 100));

    await tester.tap(find.text('Filmer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fyrlyset'));
    await tester.pumpAndSettle();
    expect(find.text('Fortsett fra 12:05'), findsOneWidget);
    expect(find.text('Fra begynnelsen'), findsOneWidget);

    await tester.tap(find.text('Fortsett fra 12:05'));
    await _settle(tester);
    expect(fake.starts, [const Duration(minutes: 12, seconds: 5)]);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('serier: sesonger, episoder, og neste episode når en er ferdig', (tester) async {
    await _start(tester);
    final fake = _fakePlayback();

    await tester.tap(find.text('Serier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kystvakten'));
    await tester.pumpAndSettle();
    expect(find.text('Livet langs kysten.'), findsOneWidget);
    expect(find.text('Sesong 1'), findsOneWidget);
    expect(find.text('Sesong 2'), findsOneWidget);
    expect(find.text('S01E01  Første'), findsOneWidget);
    expect(find.text('S01E02  Andre'), findsOneWidget);

    await tester.tap(find.text('Sesong 2'));
    await tester.pumpAndSettle();
    expect(find.text('S02E01  Tredje'), findsOneWidget);
    await tester.tap(find.text('Sesong 1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('S01E01  Første'));
    await _settle(tester);
    expect(fake.urls, ['http://example/series/401.mkv']);
    expect(find.text('S01E01 Første'), findsOneWidget);

    // spilt ferdig: neste episode starter av seg selv
    fake.moveTo(const Duration(seconds: 30));
    await tester.pump();
    fake.finish();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await _settle(tester);
    expect(fake.urls.last, 'http://example/series/402.mp4');
    expect(find.text('S01E02 Andre'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  test('tidsformat', () {
    expect(formatDuration(const Duration(minutes: 12, seconds: 5)), '12:05');
    expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    expect(formatDuration(Duration.zero), '0:00');
  });
}
