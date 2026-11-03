import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/app.dart';
import 'package:fyrlys/core/report.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/ui/playback.dart';
import 'package:fyrlys/ui/plex/plex_detail_page.dart';
import 'package:fyrlys/ui/vod_player_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';
import 'plex_fake.dart';

Future<(Session, FakePlex)> _start(WidgetTester tester, {bool linked = true}) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final fake = FakePlex();
  SharedPreferences.setMockInitialValues({
    'source': '{"kind":"fake"}',
    if (linked) 'plex_plain': FakePlex.saved(),
  });
  final session = Session(
    await SharedPreferences.getInstance(),
    sourceFactory: (_) async => FakeSource(),
    plexClient: fake.client,
  );
  await session.restore();
  await tester.pumpWidget(FyrlysApp(session: session));
  await tester.pumpAndSettle();
  return (session, fake);
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

Future<void> _openPlex(WidgetTester tester) async {
  await tester.tap(find.text('Plex'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Plex erstatter Filmer og Serier, og Hjem viser Fortsett å se og det som sist kom', (tester) async {
    final (session, fake) = await _start(tester);
    expect(find.text('Plex'), findsOneWidget);
    expect(find.text('Filmer'), findsNothing);
    expect(find.text('Serier'), findsNothing);
    // ingenting hentes fra Plex før fanen åpnes
    expect(fake.requests, isEmpty);

    await _openPlex(tester);
    expect(find.text('Fortsett å se'), findsOneWidget);
    expect(find.text('Nylig lagt til i Mine filmer'), findsOneWidget);
    expect(find.text('Nylig lagt til i Mine serier'), findsOneWidget);
    expect(find.byKey(const ValueKey('fortsett:11')), findsOneWidget);
    expect(find.byKey(const ValueKey('fortsett:32')), findsOneWidget);
    expect(find.text('Mine filmer'), findsOneWidget);
    // musikk er ikke med
    expect(find.text('Musikk'), findsNothing);

    // begge deler, når du vil det
    session.plex.setReplacesVod(false);
    await tester.pumpAndSettle();
    expect(find.text('Filmer'), findsOneWidget);
    expect(find.text('Serier'), findsOneWidget);
    expect(find.text('Plex'), findsOneWidget);
  });

  testWidgets('en film: detaljsiden, avspilling med Plex sine hoder, og hvor du er til Plex', (tester) async {
    final (_, fake) = await _start(tester);
    final pb = _fakePlayback();
    await _openPlex(tester);
    await tester.tap(find.byKey(const ValueKey('nylig:1:10')));
    await tester.pumpAndSettle();
    expect(find.byType(PlexDetailPage), findsOneWidget);
    expect(find.text('En film om et fyr ved havet.'), findsOneWidget);
    expect(find.text('Lyset blir aldri slukket.'), findsOneWidget);
    expect(find.text('Skuespillere: Kari Nordmann'), findsOneWidget);
    expect(find.text('Regi: Ola Regissør'), findsOneWidget);
    expect(find.text('4K'), findsOneWidget);
    expect(find.text('Mer som dette'), findsOneWidget);

    await tester.tap(find.text('Spill av'));
    await _settle(tester);
    expect(find.byType(VodPlayerPage), findsOneWidget);
    expect(pb.urls.last, '${FakePlex.local}/library/parts/100/1700000000/file.mkv');
    expect(pb.headers.last['X-Plex-Token'], FakePlex.serverToken);
    expect(pb.headers.last['X-Plex-Client-Identifier'], isNotEmpty);
    expect(pb.starts.last, isNull);

    pb.moveTo(const Duration(minutes: 5));
    await tester.pump(const Duration(seconds: 10));
    await _settle(tester);
    final playing = fake.calls('/:/timeline').last;
    expect(playing['state'], 'playing');
    expect(playing['time'], '300000');
    expect(playing['ratingKey'], '10');

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.byType(VodPlayerPage), findsNothing);
    final stopped = fake.calls('/:/timeline').last;
    expect(stopped['state'], 'stopped');
    expect(stopped['time'], '300000');
    // detaljsiden henter filmen på nytt (hvor du slapp)
    expect(fake.calls('/library/metadata/10').length, greaterThanOrEqualTo(3));
  });

  testWidgets('en episode fra Fortsett å se: der du slapp, introen, undertekstfilen og neste sesong', (tester) async {
    final (_, fake) = await _start(tester);
    final pb = _fakePlayback(length: const Duration(minutes: 42));
    await _openPlex(tester);
    await tester.tap(find.byKey(const ValueKey('fortsett:32')));
    await _settle(tester);
    expect(find.byType(VodPlayerPage), findsOneWidget);
    expect(pb.urls.last, '${FakePlex.local}/library/parts/320/1700000000/file.mkv');
    expect(pb.starts.last, const Duration(minutes: 5));
    expect(find.text('S01E02 Etter stormen'), findsOneWidget);

    pb.moveTo(const Duration(seconds: 20));
    await _settle(tester);
    expect(find.text('Hopp over introen (S)'), findsOneWidget);
    expect(pb.addedSubtitles, hasLength(1));
    expect(pb.addedSubtitles.single.language, 'nor');
    expect(pb.addedSubtitles.single.url, contains('/library/streams/900'));
    await tester.tap(find.byKey(const ValueKey('hopp-over')));
    await _settle(tester);
    expect(pb.seeks.last, const Duration(seconds: 70));

    // siste episode i sesong 1: neste sesong er alt hentet, og den første episoden der spilles når denne er ferdig
    expect(fake.calls('/library/metadata/22/children'), isNotEmpty);
    pb.finish();
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 1600));
    await _settle(tester);
    expect(pb.urls.last, '${FakePlex.local}/library/parts/330/1700000000/file.mkv');
    expect(
      fake.calls('/:/timeline').where((c) => c['ratingKey'] == '32' && c['state'] == 'stopped'),
      isNotEmpty,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('en serie: sesongene, episodene, «Fortsett S01E02» og sett/ikke sett', (tester) async {
    final (_, fake) = await _start(tester);
    await _openPlex(tester);
    await tester.tap(find.byKey(const ValueKey('nylig:2:20')));
    await tester.pumpAndSettle();
    expect(find.text('En serie om kysten.'), findsOneWidget);
    expect(find.text('Fortsett S01E02'), findsOneWidget);
    // sesongene i rekkefølge, med den du er på, valgt
    expect(find.text('Sesong 1'), findsOneWidget);
    expect(find.text('Sesong 2'), findsOneWidget);
    expect(find.textContaining('Etter stormen'), findsWidgets);
    expect(find.textContaining('Våren'), findsNothing);

    await tester.tap(find.text('Sesong 2'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Våren'), findsOneWidget);

    await tester.tap(find.byTooltip('Mer').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Merk som sett').last);
    await tester.pumpAndSettle();
    expect(fake.calls('/:/scrobble').last['key'], '33');
  });

  testWidgets('et bibliotek: plakatene, sjanger, sortering og søk', (tester) async {
    final (_, fake) = await _start(tester);
    await _openPlex(tester);
    await tester.tap(find.text('Mine filmer'));
    await tester.pumpAndSettle();
    expect(find.text('Fyrlyset'), findsOneWidget);
    expect(find.text('Nordlys'), findsOneWidget);
    expect(fake.calls('/library/sections/1/all').last['sort'], 'addedAt:desc');

    await tester.tap(find.text('Alle sjangre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drama').last);
    await tester.pumpAndSettle();
    expect(fake.calls('/library/sections/1/all').last['genre'], '5');
    expect(find.text('Nordlys'), findsNothing);

    await tester.tap(find.text('Nylig lagt til'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('A–Å').last);
    await tester.pumpAndSettle();
    expect(fake.calls('/library/sections/1/all').last['sort'], 'titleSort');

    await tester.enterText(find.byType(TextField), 'nord');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(fake.calls('/hubs/search').last['query'], 'nord');
    expect(fake.calls('/hubs/search').last['sectionId'], '1');
    expect(find.text('Nordlys'), findsOneWidget);
    expect(find.text('Fyrlyset'), findsNothing);
  });

  testWidgets('koble til Plex fra innstillingene: PIN i nettleseren, og så kommer Plex-fanen', (tester) async {
    final (session, fake) = await _start(tester, linked: false);
    fake.approveAt = 2;
    final opened = <String>[];
    final before = openUrl;
    openUrl = (url) async => opened.add(url);
    addTearDown(() => openUrl = before);
    expect(find.text('Plex'), findsNothing);

    await tester.tap(find.byTooltip('Innstillinger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Koble til Plex'));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(opened.single, startsWith('https://app.plex.tv/auth#?clientID='));
    expect(opened.single, contains('code=abcd1234'));
    expect(find.text('Venter på Plex …'), findsOneWidget);

    // første sjekk: ikke ennå; andre: ja
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(session.plex.linked, isTrue);
    expect(find.text('Hjemme'), findsOneWidget);
    expect(find.textContaining('logget inn som kari'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Plex'), findsOneWidget);

    // koble fra
    await tester.tap(find.byTooltip('Innstillinger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Koble fra Plex'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Koble fra'));
    await tester.pumpAndSettle();
    expect(session.plex.linked, isFalse);
    expect(find.text('Koble til Plex'), findsOneWidget);
  });
}
