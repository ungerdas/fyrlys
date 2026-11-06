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

/// Adressen til et nettbilde (i testene et vanlig nettbilde, ofte pakket ut i mindre størrelse).
String _imageUrl(ImageProvider<Object> image) {
  final inner = image is ResizeImage ? image.imageProvider : image;
  return (inner as NetworkImage).url;
}

Future<(Session, FakePlex)> _start(WidgetTester tester,
    {bool linked = true, Map<String, Object> prefs = const {}}) async {
  // høyt nok til at alle radene på Hjem får plass
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final fake = FakePlex();
  SharedPreferences.setMockInitialValues({
    'source': '{"kind":"fake"}',
    if (linked) 'plex_plain': FakePlex.saved(),
    ...prefs,
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
    expect(find.text('Nylig spilt'), findsNothing);

    // begge deler, når du vil det
    session.plex.setReplacesVod(false);
    await tester.pumpAndSettle();
    expect(find.text('Filmer'), findsOneWidget);
    expect(find.text('Serier'), findsOneWidget);
    expect(find.text('Plex'), findsOneWidget);
  });

  testWidgets('en film: detaljsiden, avspilling med Plex sine hoder, og hvor du er til Plex', (tester) async {
    // mørkt utseende: logoen fra Plex vises
    final (_, fake) = await _start(tester, prefs: {'theme': 'dark'});
    final pb = _fakePlayback();
    await _openPlex(tester);
    await tester.tap(find.byKey(const ValueKey('rad:movie.recentlyadded.1:10')));
    await tester.pumpAndSettle();
    expect(find.byType(PlexDetailPage), findsOneWidget);
    expect(find.text('En film om et fyr ved havet.'), findsOneWidget);
    expect(find.text('Lyset blir aldri slukket.'), findsOneWidget);
    expect(find.text('Skuespillere: Kari Nordmann'), findsOneWidget);
    expect(find.text('Regi: Ola Regissør'), findsOneWidget);
    expect(find.text('4K'), findsOneWidget);
    expect(find.text('Mer som dette'), findsOneWidget);
    // logoen fra Plex i stedet for navnet, hentet som den er (navnet står til den er lastet, og her i testene)
    final logo = tester.widget<Image>(find.byKey(const ValueKey('hero-logo')));
    expect(logo.semanticLabel, 'Fyrlyset');
    expect(
      _imageUrl(logo.image),
      '${FakePlex.local}/library/metadata/10/clearLogo/1700000000?X-Plex-Token=${FakePlex.serverToken}',
    );
    expect(find.text('Fyrlyset'), findsWidgets);

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
    // ingenting etter «stoppet» (avspilleren sier «pause» når den stoppes)
    final states = [for (final c in fake.calls('/:/timeline')) c['state']];
    expect(states.sublist(states.indexOf('stopped')), ['stopped']);
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
    expect(pb.addedSubtitles.single.url, contains('/library/streams/900.srt?'));
    expect(pb.addedSubtitles.single.url, contains('encoding=utf-8'));
    await tester.tap(find.byKey(const ValueKey('hopp-over')));
    await _settle(tester);
    expect(pb.seeks.last, const Duration(seconds: 70));

    // en rulletekst midt i: bare hopp over den
    pb.moveTo(const Duration(minutes: 20, seconds: 5));
    await _settle(tester);
    expect(find.text('Hopp over rulleteksten (S)'), findsOneWidget);

    // siste episode i sesong 1: neste sesong er alt hentet; rulleteksten på slutten gir «Neste episode», og denne
    // er sett ferdig
    expect(fake.calls('/library/metadata/22/children'), isNotEmpty);
    pb.moveTo(const Duration(minutes: 41, seconds: 10));
    await _settle(tester);
    expect(find.text('Neste episode (S)'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hopp-over')));
    await _settle(tester);
    expect(pb.urls.last, '${FakePlex.local}/library/parts/330/1700000000/file.mkv');
    final done = [
      for (final c in fake.calls('/:/timeline'))
        if (c['ratingKey'] == '32') '${c['state']} ${c['time']}',
    ];
    expect(done.last, 'stopped 2520000');

    // når en episode er ferdig, spilles den neste
    pb.moveTo(const Duration(minutes: 1));
    await _settle(tester);
    pb.finish();
    await _settle(tester);
    await tester.pump(const Duration(milliseconds: 1600));
    await _settle(tester);
    expect(pb.urls.last, '${FakePlex.local}/library/parts/340/1700000000/file.mkv');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  });

  testWidgets('en serie: sesongene, episodene, «Fortsett S01E02» og sett/ikke sett', (tester) async {
    final (_, fake) = await _start(tester);
    await _openPlex(tester);
    await tester.tap(find.byKey(const ValueKey('rad:tv.recentlyadded.2:20')));
    await tester.pumpAndSettle();
    expect(find.text('En serie om kysten.'), findsOneWidget);
    expect(find.text('Fortsett S01E02'), findsOneWidget);
    // lyst utseende: navnet i stedet for logoen (logoene er laget for mørk bakgrunn)
    expect(find.byKey(const ValueKey('hero-logo')), findsNothing);
    expect(find.text('Kysten'), findsWidgets);
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

  testWidgets('Hjem som på Plex: radene fra serveren i den rekkefølgen, og «Vis alle»', (tester) async {
    final (_, fake) = await _start(tester);
    await _openPlex(tester);
    final q = fake.calls('/hubs/promoted').last;
    expect(q['contentDirectoryID'], '1,2');
    expect(q['pinnedContentDirectoryID'], '1,2');
    expect(q['excludeContinueWatching'], '1');
    // overskriftene Plex lager selv, på norsk
    expect(fake.requests.lastWhere((r) => r.url.path == '/hubs/promoted').headers['X-Plex-Language'], 'nb');
    // «Fortsett å se» én gang, og ikke musikk
    expect(find.text('Fortsett å se'), findsOneWidget);
    expect(find.text('Nylig spilt'), findsNothing);
    // rekkefølgen fra Plex
    final collection = tester.getTopLeft(find.text('Nytt fra Kystkanalen')).dy;
    expect(collection, lessThan(tester.getTopLeft(find.text('Nylig lagt til i Mine filmer')).dy));
    // episodene med navnet på serien
    expect(find.byKey(const ValueKey('rad:custom.collection.2.77:34')), findsOneWidget);
    expect(find.text('S02E02 · Sommeren'), findsOneWidget);
    // «Vis alle» bare der Plex har flere
    expect(find.byKey(const ValueKey('vis-alle:movie.recentlyadded.1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('vis-alle:custom.collection.2.77')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('alle:31')), findsOneWidget);
    expect(find.byKey(const ValueKey('alle:34')), findsOneWidget);
    expect(fake.calls('/library/collections/77/children').first['X-Plex-Container-Start'], '0');

    // en episode åpner serien på den sesongen
    await tester.tap(find.byKey(const ValueKey('alle:33')));
    await tester.pumpAndSettle();
    expect(find.byType(PlexDetailPage), findsOneWidget);
    expect(find.textContaining('Våren'), findsOneWidget);
  });

  testWidgets('en eldre server uten radene: det som sist kom i hvert bibliotek', (tester) async {
    final (_, fake) = await _start(tester);
    fake.oldServer = true;
    await _openPlex(tester);
    expect(fake.calls('/hubs/promoted'), isNotEmpty);
    expect(find.text('Nylig lagt til i Mine filmer'), findsOneWidget);
    expect(find.byKey(const ValueKey('nylig:1:10')), findsOneWidget);

    // «Vis alle» er biblioteket
    await tester.tap(find.byKey(const ValueKey('vis-alle:nylig:1')));
    await tester.pumpAndSettle();
    expect(find.text('Alle sjangre'), findsOneWidget);
    expect(find.text('Fyrlyset'), findsOneWidget);
  });

  testWidgets('skjule et bibliotek: borte fra sidemenyen, Hjem og søket, og tilbake igjen', (tester) async {
    final (session, fake) = await _start(tester);
    await _openPlex(tester);
    expect(find.text('Mine serier'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('velg-biblioteker')));
    await tester.pumpAndSettle();
    expect(find.text('Biblioteker i Plex-fanen'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('vis-bibliotek:2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ferdig'));
    await tester.pumpAndSettle();

    expect(find.text('Mine serier'), findsNothing);
    expect(find.text('Nytt fra Kystkanalen'), findsNothing);
    expect(find.text('Nylig lagt til i Mine serier'), findsNothing);
    expect(find.text('Nylig lagt til i Mine filmer'), findsOneWidget);
    expect(find.byKey(const ValueKey('fortsett:32')), findsNothing);
    expect(find.byKey(const ValueKey('fortsett:11')), findsOneWidget);
    expect(fake.calls('/hubs/promoted').last['contentDirectoryID'], '1');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('plex_hidden_libraries'), ['srv1/2']);

    // i innstillingene: hva som er skjult, og tilbake igjen
    await tester.tap(find.byTooltip('Innstillinger'));
    await tester.pumpAndSettle();
    expect(find.text('Skjult: Mine serier'), findsOneWidget);
    await tester.tap(find.text('Biblioteker i Plex-fanen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('vis-bibliotek:2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ferdig'));
    await tester.pumpAndSettle();
    expect(find.text('Alle vises'), findsOneWidget);
    expect(session.plex.shownSections, {'1', '2'});
  });

  testWidgets('rekkefølgen på bibliotekene: pilene i valget av biblioteker, og sidemenyen og Hjem følger med',
      (tester) async {
    final (_, fake) = await _start(tester);
    // en eldre server: Hjem har det som sist kom i hvert bibliotek, i den rekkefølgen
    fake.oldServer = true;
    await _openPlex(tester);
    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('Mine filmer'), lessThan(y('Mine serier')));
    expect(y('Nylig lagt til i Mine filmer'), lessThan(y('Nylig lagt til i Mine serier')));
    // pilene står ikke i sidemenyen
    expect(find.byTooltip('Flytt opp'), findsNothing);
    expect(find.byTooltip('Flytt ned'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('velg-biblioteker')));
    await tester.pumpAndSettle();
    double inDialog(String text) =>
        tester.getTopLeft(find.descendant(of: find.byType(AlertDialog), matching: find.text(text))).dy;
    expect(inDialog('Mine filmer'), lessThan(inDialog('Mine serier')));
    // øverst kan ikke flyttes opp, nederst ikke ned
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('flytt-opp:1'))).onPressed, isNull);
    expect(tester.widget<IconButton>(find.byKey(const ValueKey('flytt-ned:2'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('flytt-ned:1')));
    await tester.pumpAndSettle();
    expect(inDialog('Mine serier'), lessThan(inDialog('Mine filmer')));
    await tester.tap(find.text('Ferdig'));
    await tester.pumpAndSettle();

    expect(y('Mine serier'), lessThan(y('Mine filmer')));
    expect(y('Nylig lagt til i Mine serier'), lessThan(y('Nylig lagt til i Mine filmer')));
    // radene fra Plex spørres om i samme rekkefølge
    expect(fake.calls('/hubs/promoted').last['contentDirectoryID'], '2,1');
    expect(fake.calls('/hubs/promoted').last['pinnedContentDirectoryID'], '2,1');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('plex_library_order'), ['srv1/2', 'srv1/1']);
    expect(find.byTooltip('Flytt opp'), findsNothing);
  });

  testWidgets('Plex Home: hvem ser på, med PIN-kode, og det den brukeren har sett', (tester) async {
    final (session, fake) = await _start(tester);
    fake.home = true;
    await _openPlex(tester);
    expect(find.byKey(const ValueKey('hvem-ser-pa')), findsOneWidget);
    expect(find.byKey(const ValueKey('fortsett:11')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hvem-ser-pa')));
    await tester.pumpAndSettle();
    expect(find.text('Hvem ser på?'), findsOneWidget);
    expect(find.byKey(const ValueKey('plex-bruker:kari-uuid')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('plex-bruker:ola-uuid')));
    await tester.pumpAndSettle();
    expect(find.text('PIN-kode for Ola'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('plex-pin')), '0000');
    await tester.pumpAndSettle();
    expect(find.text('Feil PIN-kode. Prøv igjen.'), findsOneWidget);
    expect(session.plex.user, 'kari');

    await tester.enterText(find.byKey(const ValueKey('plex-pin')), FakePlex.olaPin);
    await tester.pumpAndSettle();
    expect(find.text('PIN-kode for Ola'), findsNothing);
    expect(find.text('Hvem ser på?'), findsNothing);
    expect(session.plex.user, 'Ola');
    // Hjem for Ola: han har ikke noe å fortsette på, og serveren spørres med hans innlogging
    expect(find.byKey(const ValueKey('fortsett:11')), findsNothing);
    expect(find.text('Fortsett å se'), findsNothing);
    expect(find.text('Nytt fra Kystkanalen'), findsOneWidget);
    expect(fake.requests.lastWhere((r) => r.url.path == '/hubs/promoted').headers['X-Plex-Token'],
        FakePlex.olaServerToken);

    // i innstillingene: hvem som ser på, og om det skal spørres
    await tester.tap(find.byTooltip('Innstillinger'));
    await tester.pumpAndSettle();
    expect(find.text('Bruker i Plex Home'), findsOneWidget);
    expect(find.textContaining('logget inn som Ola'), findsOneWidget);
    expect(find.byKey(const ValueKey('bytt-plex-bruker')), findsOneWidget);
    await tester.tap(find.text('Spør hvem som ser på når Plex-fanen åpnes'));
    await tester.pumpAndSettle();
    expect(session.plex.askUser, isTrue);
  });

  testWidgets('Plex Home: «Hvem ser på?» når fanen åpnes, når det er slått på, og bare første gang', (tester) async {
    final (session, fake) = await _start(tester, prefs: {'plex_ask_user': true});
    fake.home = true;
    await _openPlex(tester);
    expect(find.text('Hvem ser på?'), findsOneWidget);
    // den som ser på nå: bare lukk
    await tester.tap(find.byKey(const ValueKey('plex-bruker:kari-uuid')));
    await tester.pumpAndSettle();
    expect(find.text('Hvem ser på?'), findsNothing);
    expect(session.plex.user, 'kari');
    expect(fake.calls('/api/v2/home/users/kari-uuid/switch'), isEmpty);

    // bytte bruker kobler til på nytt, men spør ikke igjen
    await tester.tap(find.byKey(const ValueKey('hvem-ser-pa')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plex-bruker:ola-uuid')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('plex-pin')), FakePlex.olaPin);
    await tester.pumpAndSettle();
    expect(session.plex.user, 'Ola');
    expect(find.text('Hvem ser på?'), findsNothing);
  });

  testWidgets('uten Plex Home: ingen knapp for å bytte bruker', (tester) async {
    final (_, fake) = await _start(tester);
    await _openPlex(tester);
    expect(fake.calls('/api/v2/home/users'), isNotEmpty);
    expect(find.byKey(const ValueKey('hvem-ser-pa')), findsNothing);
    await tester.tap(find.byTooltip('Innstillinger'));
    await tester.pumpAndSettle();
    expect(find.text('Bruker i Plex Home'), findsNothing);
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
