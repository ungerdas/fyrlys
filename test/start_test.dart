import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/app.dart';
import 'package:fyrlys/core/languages.dart';
import 'package:fyrlys/core/models.dart';
import 'package:fyrlys/core/names.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/ui/channel_number.dart';
import 'package:fyrlys/ui/player_page.dart';
import 'package:fyrlys/ui/playback.dart';
import 'package:fyrlys/ui/start_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const _nrk = Channel(id: '101', name: 'NRK 1 HD', categoryId: '1', number: '1');
const _tv2 = Channel(id: '102', name: 'TV 2 HD', categoryId: '1', number: '2');

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

/// Ikke pumpAndSettle mens spilleren er åpen: spinneren går så lenge kanalen laster.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

String _list(List<Channel> list) => jsonEncode([for (final c in list) c.toJson()]);

void main() {
  test('hilsen og dato', () {
    expect(greetingAt(DateTime(2026, 10, 26, 7)), 'God morgen');
    expect(greetingAt(DateTime(2026, 10, 26, 12)), 'God dag');
    expect(greetingAt(DateTime(2026, 10, 26, 20)), 'God kveld');
    expect(greetingAt(DateTime(2026, 10, 26, 2)), 'God natt');
    expect(dateLine(DateTime(2026, 10, 26)), 'Mandag 26. oktober');
    expect(dateLine(DateTime(2026, 5, 17)), 'Søndag 17. mai');
  });

  test('kanalnummer', () {
    const list = [_nrk, _tv2, Channel(id: '9', name: 'Uten nummer')];
    expect(channelByNumber(list, '2'), 1);
    expect(channelByNumber(list, '002'), 1);
    expect(channelByNumber(list, '3'), -1);
  });

  test('språkene: koder til avspilleren og teksten i menyen', () {
    const prefs = LanguagePrefs(audio: ['no', 'en'], subtitles: ['no']);
    expect(prefs.audioCodes, 'nor,nob,nno,no,nb,nn,eng,en');
    expect(prefs.subtitleCodes, 'nor,nob,nno,no,nb,nn');
    expect(prefs.summary, 'Lyd: norsk, så engelsk · Undertekster: norsk');
    const off = LanguagePrefs(subtitles: [LanguagePrefs.off]);
    expect(off.subtitlesOff, isTrue);
    expect(off.subtitleCodes, '');
    expect(off.summary, 'Undertekster: av');
    expect(const LanguagePrefs().isEmpty, isTrue);
    expect(LanguagePrefs.describe(['sv', 'da', 'en']), 'svensk, dansk, så engelsk');
  });

  testWidgets('startsiden: sist sett, favoritter med nå og etterpå, og kategorier', (tester) async {
    final (_, source) = await _start(tester, prefs: {'recent': _list([_nrk, _tv2]), 'favorites': _list([_nrk, _tv2])});
    final players = _players();
    // programinfoen på kortene hentes når de har vært framme litt
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text(greetingAt(DateTime.now())), findsOneWidget);
    // kanalen du så sist, stort, med programmet nå og etterpå
    expect(find.text('SIST SETT'), findsOneWidget);
    expect(find.text('Se videre'), findsOneWidget);
    expect(find.textContaining('min igjen'), findsOneWidget);
    expect(find.textContaining(': Sportsrevyen'), findsOneWidget);
    // favorittene: det som går nå, og det som kommer etterpå
    expect(find.text('Dagsrevyen'), findsNWidgets(2));
    expect(find.textContaining('  Sportsrevyen'), findsOneWidget);
    expect(find.text('TV 2 HD'), findsNWidgets(2));
    // kategoriene (ingen valgt øverst ennå)
    expect(find.text('Kategorier'), findsOneWidget);
    expect(find.text('Sport  1'), findsOneWidget);

    await tester.tap(find.text('Se videre'));
    await _settle(tester);
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(players.single.urls, ['http://example/101.ts']);
    expect(source.opened, ['101']);
    Navigator.of(tester.element(find.byType(PlayerPage))).pop();
    await _settle(tester);
    await tester.pumpAndSettle();

    // en kategori fra startsiden
    await tester.tap(find.text('Sport  1'));
    await tester.pumpAndSettle();
    expect(find.text('15:00  Man United - Bournemouth'), findsOneWidget);
    expect(find.text('NRK 1 HD'), findsNothing);
    // og tilbake
    await tester.tap(find.text('Hjem'));
    await tester.pumpAndSettle();
    expect(find.text('SIST SETT'), findsOneWidget);

    // søket på startsiden gjelder alle kanalene
    await tester.enterText(find.byType(TextField), 'tv');
    await tester.pumpAndSettle();
    expect(find.text('Treff i alle kanaler'), findsOneWidget);
    expect(find.text('TV 2 HD'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('tall går rett til kanalen, fra TV-siden og i spilleren', (tester) async {
    final (_, source) = await _start(tester);
    final players = _players();

    // «2» på startsiden: nummeret vises, og etter litt starter kanal 2
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    expect(find.widgetWithText(NumberBadge, '2'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    await _settle(tester);
    expect(find.byType(PlayerPage), findsOneWidget);
    expect(source.opened, ['102']);

    // i spilleren: «0» og «1» blir kanal 1
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await tester.sendKeyEvent(LogicalKeyboardKey.numpad1);
    await tester.pump();
    expect(find.widgetWithText(NumberBadge, '01'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1500));
    await _settle(tester);
    expect(source.opened, ['102', '101']);
    expect(players.single.urls.last, 'http://example/101.ts');

    // OK går dit med en gang; et nummer som ikke finnes, sier fra
    await tester.sendKeyEvent(LogicalKeyboardKey.digit9);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('Fant ikke kanal 9'), findsOneWidget);
    expect(source.opened, ['102', '101']);

    // Backspace: tilbake til kanalen du så før
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await _settle(tester);
    expect(source.opened, ['102', '101', '102']);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('tall mens du skriver i søket, er bare søk', (tester) async {
    final (_, source) = await _start(tester);
    _players();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    expect(find.byType(NumberBadge), findsNothing);
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pump();
    expect(find.byType(PlayerPage), findsNothing);
    expect(source.opened, isEmpty);
  });

  testWidgets('språk for lyd og undertekster: fra innstillingene og i spilleren', (tester) async {
    final (session, _) = await _start(tester);
    final players = _players();

    await tester.tap(find.byTooltip('Innstillinger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Språk for lyd og undertekster'));
    await tester.pumpAndSettle();
    // lyd: norsk, så engelsk; undertekster: norsk
    await tester.tap(find.text('Norsk').first);
    await tester.pump();
    await tester.tap(find.text('Engelsk').first);
    await tester.pump();
    expect(find.text('1. Norsk'), findsOneWidget);
    expect(find.text('2. Engelsk'), findsOneWidget);
    await tester.tap(find.text('Norsk'));
    await tester.pump();
    expect(find.text('1. Norsk'), findsNWidgets(2));
    await tester.tap(find.text('Lagre'));
    await tester.pumpAndSettle();
    expect(session.languages.audio, ['no', 'en']);
    expect(session.languages.subtitles, ['no']);

    // innstillingene viser hva du har valgt
    expect(find.text('Lyd: norsk, så engelsk · Undertekster: norsk'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();

    // spilleren får språkene før kanalen åpnes
    await tester.tap(find.text('Alle kanaler').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('NRK 1 HD'));
    await _settle(tester);
    final player = players.single;
    expect(player.languages.single.$1.audio, ['no', 'en']);
    expect(player.languages.single.$2, isFalse);

    // i spilleren: sporene, og undertekster av herfra (gjelder med en gang)
    player.audio = const [
      TrackChoice('Norsk · nor', selected: true, value: 1),
      TrackChoice('Engelsk · eng', selected: false, value: 2),
    ];
    await tester.tap(find.byTooltip('Lydspor og undertekster'));
    await tester.pumpAndSettle();
    expect(find.text('Norsk · nor'), findsOneWidget);
    await tester.tap(find.text('Engelsk · eng'));
    await tester.pumpAndSettle();
    expect(player.selected.single.label, 'Engelsk · eng');

    await tester.tap(find.byTooltip('Lydspor og undertekster'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Foretrukne språk …'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Av'));
    await tester.pump();
    await tester.tap(find.text('Lagre'));
    await tester.pumpAndSettle();
    expect(session.languages.subtitlesOff, isTrue);
    expect(session.languages.audio, ['no', 'en']);
    expect(player.languages.last.$1.subtitlesOff, isTrue);
    expect(player.languages.last.$2, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  test('klokka under hilsenen', () {
    expect(hhmm(DateTime(2026, 10, 26, 9, 5)), '09:05');
  });
}
