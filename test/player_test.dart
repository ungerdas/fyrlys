import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/theme.dart';
import 'package:fyrlys/ui/channel_card.dart';
import 'package:fyrlys/ui/player_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

Future<(Session, FakeSource)> _session({Set<String> busy = const {}}) async {
  SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
  final source = FakeSource(busy: busy);
  final session = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => source);
  await session.restore();
  await session.load();
  return (session, source);
}

Future<FakePlayback> _openPlayer(WidgetTester tester, Session session, {Size size = const Size(1400, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final playback = FakePlayback();
  await tester.pumpWidget(MaterialApp(
    theme: fyrlysTheme(Brightness.light),
    home: PlayerPage(
      session: session,
      channels: session.channels,
      index: 0,
      listTitle: 'Alle kanaler',
      playback: () => playback,
    ),
  ));
  await _settle(tester);
  return playback;
}

/// Ikke pumpAndSettle: spinneren går så lenge kanalen laster.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lukker spilleren, så tidtakerne stoppes.
Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('spilleren: bildet, programinfo under og kanallista ved siden av', (tester) async {
    final (session, source) = await _session();
    final playback = await _openPlayer(tester, session);

    expect(playback.urls, ['http://example/101.ts']);
    // programinfo under bildet
    expect(find.text('1  NRK 1 HD'), findsOneWidget);
    expect(find.text('Dagsrevyen'), findsOneWidget);
    expect(find.textContaining('Sportsrevyen'), findsOneWidget);
    expect(find.text('Nyheter fra inn- og utland.'), findsOneWidget);
    expect(find.text('1080p · MPEG-TS rett fra leverandøren'), findsOneWidget);
    // kanallista: fanene, søket og kanalene
    expect(find.text('Alle kanaler'), findsOneWidget);
    expect(find.text('★ Favoritter'), findsOneWidget);
    expect(find.text('Søk i lista'), findsOneWidget);
    expect(find.text('TV 2 HD'), findsOneWidget);
    expect(find.text('15:00  Man United - Bournemouth'), findsOneWidget);

    // kanal fra lista
    await tester.tap(find.text('TV 2 HD'));
    await _settle(tester);
    expect(playback.urls.last, 'http://example/102.ts');
    expect(find.text('2  TV 2 HD'), findsOneWidget);
    expect(source.closed, ['101']);

    // ▼▼ blar to kanaler fram i kanalinfoen, og bare den du stopper på, startes
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('15:00 · Man United - Bournemouth'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(playback.urls.last, 'http://example/102.ts');
    await tester.pump(const Duration(milliseconds: 700));
    await _settle(tester);
    expect(playback.urls, ['http://example/101.ts', 'http://example/102.ts', 'http://example/101.ts']);
    expect(find.byKey(const ValueKey('channel-banner')), findsOneWidget);

    // ▲ og OK: starter med en gang; Esc mens du blar, blir på kanalen
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(playback.urls.last, 'http://example/103.ts');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 700));
    await _settle(tester);
    expect(playback.urls.last, 'http://example/103.ts');
    expect(find.byType(PlayerPage), findsOneWidget);

    // Backspace går tilbake til forrige kanal
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await _settle(tester);
    expect(playback.urls.last, 'http://example/101.ts');

    await _close(tester);
    expect(playback.disposed, isTrue);
  });

  testWidgets('volum: lyd av og på, glidebryteren, og det huskes', (tester) async {
    final (session, _) = await _session();
    final playback = await _openPlayer(tester, session);
    expect(playback.volume, 100);
    expect(find.byType(Slider), findsOneWidget);

    await tester.tap(find.byTooltip('Lyd av (M)'));
    await tester.pump();
    expect(playback.volume, 0);
    expect(session.muted, isTrue);
    expect(find.text('Lyd av'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(playback.volume, 100);
    expect(session.muted, isFalse);

    await tester.drag(find.byType(Slider), const Offset(-30, 0));
    await tester.pump();
    expect(playback.volume, lessThan(100));
    expect(playback.volume, greaterThan(0));
    expect(session.volume, playback.volume);

    await _close(tester);
  });

  testWidgets('søk i kanallista: tastene går til søket, Esc tilbake til bildet', (tester) async {
    final (session, _) = await _session();
    final playback = await _openPlayer(tester, session);

    await tester.enterText(find.byType(TextField), 'tv');
    await tester.pump();
    expect(find.text('TV 2 HD'), findsOneWidget);
    expect(find.text('NRK 1 HD'), findsNothing);

    // M mens du skriver slår ikke av lyden
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(playback.volume, 100);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(playback.volume, 0);

    await _close(tester);
  });

  testWidgets('fullskjerm viser bare bildet, og C legger kanallista over', (tester) async {
    final (session, _) = await _session();
    await _openPlayer(tester, session);
    expect(find.text('Søk i lista'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await _settle(tester);
    expect(find.text('Søk i lista'), findsNothing);
    expect(find.text('Nyheter fra inn- og utland.'), findsNothing);
    // kanal og program ligger over bildet
    expect(find.text('1  NRK 1 HD'), findsOneWidget);
    expect(find.text('Dagsrevyen'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await _settle(tester);
    expect(find.text('Søk i lista'), findsOneWidget);
    expect(find.byTooltip('Lukk kanallista (Esc)'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Søk i lista'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Søk i lista'), findsOneWidget);
    expect(find.text('Nyheter fra inn- og utland.'), findsOneWidget);

    await _close(tester);
  });

  testWidgets('stjerne ved tittelen og favorittfanen', (tester) async {
    final (session, _) = await _session();
    await _openPlayer(tester, session);

    await tester.tap(find.byKey(const ValueKey('player-star')));
    await tester.pump();
    expect(session.favorites.map((c) => c.id), ['101']);
    expect(find.text('Lagt til i favoritter'), findsOneWidget);

    await tester.tap(find.text('★ Favoritter'));
    await _settle(tester);
    expect(find.text('NRK 1 HD'), findsOneWidget);
    expect(find.text('TV 2 HD'), findsNothing);

    await _close(tester);
  });

  testWidgets('alle tilkoblinger i bruk: ta over', (tester) async {
    final (session, _) = await _session(busy: {'101'});
    final playback = await _openPlayer(tester, session);
    expect(playback.urls, isEmpty);
    expect(find.text('Stopp NRK 1 HD og se her'), findsOneWidget);

    await tester.tap(find.text('Stopp NRK 1 HD og se her'));
    await _settle(tester);
    expect(playback.urls, ['http://example/101.ts']);
    expect(find.text('Stopp NRK 1 HD og se her'), findsNothing);

    await _close(tester);
  });

  testWidgets('fjernkontroll: OK på kortet tar over tilkoblingen', (tester) async {
    final (session, _) = await _session(busy: {'101'});
    final playback = await _openPlayer(tester, session);
    expect(find.text('Stopp NRK 1 HD og se her'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _settle(tester);
    expect(playback.urls, ['http://example/101.ts']);

    await _close(tester);
  });

  testWidgets('logoen uten bilde: tre hele tegn, også med flagg foran navnet', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: ChannelLogo(url: null, name: '🇳🇴 NRK1 HD'))));
    expect(find.text('🇳🇴 N'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('smal skjerm: programinfo og kanallista under bildet', (tester) async {
    final (session, _) = await _session();
    await _openPlayer(tester, session, size: const Size(400, 800));
    expect(find.text('1  NRK 1 HD'), findsOneWidget);
    expect(find.text('Dagsrevyen'), findsOneWidget);
    expect(find.text('Søk i lista'), findsOneWidget);
    expect(find.text('TV 2 HD'), findsOneWidget);
    // smalt: ingen glidebryter (lyd av/på finnes)
    expect(find.byType(Slider), findsNothing);
    expect(find.byTooltip('Lyd av (M)'), findsOneWidget);

    await _close(tester);
  });
}
