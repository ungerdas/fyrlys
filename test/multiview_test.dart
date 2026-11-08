import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/app.dart';
import 'package:fyrlys/core/models.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/theme.dart';
import 'package:fyrlys/ui/channel_picker.dart';
import 'package:fyrlys/ui/multiview_page.dart';
import 'package:fyrlys/ui/playback.dart';
import 'package:fyrlys/ui/player_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Ikke pumpAndSettle mens spillerne er åpne: spinnerne går så lenge kanalene laster.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// En ny falsk avspiller for hvert bilde.
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

/// Innloggingen fra før («Test») og [others] i tillegg; kildene som lages, samles i [made].
Future<Session> _session(List<FakeSource> made, {List<String> others = const [], int connections = 0}) async {
  SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
  final s = Session(await SharedPreferences.getInstance(), sourceFactory: (saved) async {
    final src = FakeSource(name: saved['name'] ?? 'Test', connections: connections);
    made.add(src);
    return src;
  });
  await s.restore();
  await s.load();
  final active = s.activeLogin!;
  for (final name in others) {
    await s.useSource(FakeSource(name: name, connections: connections));
  }
  if (others.isNotEmpty) await s.switchLogin(active);
  await s.load();
  return s;
}

/// Kanalvalget alene, åpnet fra en knapp; det du velger, havner i [picked].
Future<void> _showPicker(
  WidgetTester tester,
  List<Category> cats,
  List<Channel> all, {
  List<Channel> favorites = const [],
  List<String> pinned = const [],
  List<Channel?>? picked,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: fyrlysTheme(Brightness.dark),
    home: Builder(
      builder: (context) => Center(
        child: FilledButton(
          onPressed: () async {
            final c = await showDialog<Channel>(
              context: context,
              builder: (_) => ChannelPicker(
                title: 'Velg kanal',
                lists: Future.value((categories: cats, channels: all)),
                favorites: favorites,
                recent: const [],
                pinned: pinned,
                logoUrl: (_) => null,
              ),
            );
            picked?.add(c);
          },
          child: const Text('Åpne'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Åpne'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('kanalvalget: mappene som i kanallista, og søket i alle kanalene (høyst 300 treff)', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cats = [for (var i = 0; i < 40; i++) Category(id: 'k$i', name: 'Kategori $i')];
    final all = [for (var i = 0; i < 25000; i++) Channel(id: '$i', name: 'Kanal $i', categoryId: 'k${i % 40}')];
    final picked = <Channel?>[];
    await _showPicker(tester, cats, all, favorites: [all[7]], pinned: const ['k3'], picked: picked);

    // favorittene først, og kategoriene du har lagt øverst
    expect(find.byKey(const ValueKey('kanal:7')), findsOneWidget);
    expect(find.text('DINE KATEGORIER'), findsOneWidget);
    expect(find.byKey(const ValueKey('mappe:recent')), findsNothing);
    // en mappe: bare kanalene i den kategorien
    await tester.tap(find.byKey(const ValueKey('mappe:k3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('kanal:3')), findsOneWidget);
    expect(find.byKey(const ValueKey('kanal:43')), findsOneWidget);
    expect(find.byKey(const ValueKey('kanal:4')), findsNothing);
    expect(find.byKey(const ValueKey('kanal:7')), findsNothing);

    // søket gjelder alle kanalene, men viser høyst 300
    await tester.enterText(find.byType(TextField), 'kanal');
    await tester.pumpAndSettle();
    expect(find.text('Viser de 300 første treffene. Skriv mer for å finne færre.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'kanal 1234');
    await tester.pumpAndSettle();
    expect(find.textContaining('Viser de'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('kanal:1234')));
    await tester.pumpAndSettle();
    expect(picked.single?.id, '1234');
  });

  testWidgets('kanalvalget i et smalt vindu: mappene først, så kanalene i den du åpner', (tester) async {
    tester.view.physicalSize = const Size(480, 860);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cats = [for (var i = 0; i < 3; i++) Category(id: 'k$i', name: 'Kategori $i')];
    final all = [for (var i = 0; i < 30; i++) Channel(id: '$i', name: 'Kanal $i', categoryId: 'k${i % 3}')];
    await _showPicker(tester, cats, all);

    expect(find.byKey(const ValueKey('mappe:all')), findsOneWidget);
    expect(find.byKey(const ValueKey('kanal:1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('mappe:k1')));
    await tester.pumpAndSettle();
    expect(find.text('Kategori 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('kanal:1')), findsOneWidget);
    expect(find.byKey(const ValueKey('kanal:2')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('til-mappene')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mappe:all')), findsOneWidget);
  });

  test('flere bilder: med to abonnementer, eller ett med to tilkoblinger', () async {
    final made = <FakeSource>[];
    final one = await _session(made, connections: 1);
    await pumpEventQueue();
    expect(one.canMultiview, isFalse);

    final two = await _session(made, others: ['Sport'], connections: 1);
    expect(two.canMultiview, isTrue);

    final twoConnections = await _session(made, connections: 2);
    await pumpEventQueue();
    expect(twoConnections.canMultiview, isTrue);
  });

  testWidgets('to abonnementer: to bilder, kanal i hvert, lyden i det valgte', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final made = <FakeSource>[];
    final s = await _session(made, others: ['Sport']);
    final players = _players();
    await tester.pumpWidget(MaterialApp(
      theme: fyrlysTheme(Brightness.dark),
      home: MultiviewPage(session: s, first: s.channels.first),
    ));
    await _settle(tester);

    expect(players, hasLength(2));
    expect(players[0].urls, ['http://example/101.ts']);
    expect(players[1].urls, isEmpty);
    expect(find.text('NRK 1 HD'), findsOneWidget);
    expect(find.text('Velg kanal'), findsOneWidget);
    // lyden i det første
    expect(players[0].volume, 100);
    expect(players[1].volume, 0);

    // det andre bildet: kanalene i det andre abonnementet
    await tester.tap(find.text('Velg kanal'));
    await _settle(tester);
    expect(find.text('Velg kanal · Sport'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'tv 2');
    await _settle(tester);
    await tester.tap(find.text('TV 2 HD'));
    await _settle(tester);
    expect(players[1].urls, ['http://example/102.ts']);
    final sport = made.singleWhere((m) => m.name == 'Sport' && !m.disposed);
    expect(sport.opened, ['102']);

    // klikk i det andre: lyden flytter seg dit
    await tester.tap(find.text('TV 2 HD'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(players[0].volume, 0);
    expect(players[1].volume, 100);

    // tastene: ← tilbake til det første, Enter gir stort bilde, Esc alle igjen
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(players[0].volume, 100);
    expect(players[1].volume, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(find.text('TV 2 HD'), findsNothing);
    expect(find.text('NRK 1 HD'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('TV 2 HD'), findsOneWidget);

    // M: lyd av
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(players[0].volume, 0);

    // lukket: avspillerne og det andre abonnementet lukkes, ikke det i bruk
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(players.every((p) => p.disposed), isTrue);
    expect(sport.disposed, isTrue);
    expect(s.source, isA<FakeSource>());
    expect((s.source! as FakeSource).disposed, isFalse);
  });

  testWidgets('spilleren: «Multiview» stopper direktesendingen og tar kanalen med', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final made = <FakeSource>[];
    final s = await _session(made, others: ['Sport']);
    final players = _players();
    final live = FakePlayback();
    await tester.pumpWidget(MaterialApp(
      theme: fyrlysTheme(Brightness.light),
      home: PlayerPage(session: s, channels: s.channels, index: 1, playback: () => live),
    ));
    await _settle(tester);
    expect(live.urls, ['http://example/102.ts']);

    await tester.tap(find.text('Multiview'));
    await _settle(tester);
    expect(find.byType(MultiviewPage), findsOneWidget);
    expect(live.playing, isFalse);
    expect(players.first.urls, ['http://example/102.ts']);

    // ut: multiview stopper med en gang (ikke først når siden er borte), så tilkoblingen er ledig
    Navigator.of(tester.element(find.byType(MultiviewPage))).pop();
    expect(players.first.playing, isFalse);
    await _settle(tester);
    expect(live.urls, ['http://example/102.ts', 'http://example/102.ts']);
    expect(live.playing, isTrue);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('TV-siden: knappen bare når det går', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final made = <FakeSource>[];
    final s = await _session(made, connections: 1);
    await tester.pumpWidget(FyrlysApp(session: s));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Multiview'), findsNothing);

    await s.useSource(FakeSource(name: 'Sport'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Multiview'), findsOneWidget);
  });
}
