import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/cast/caster.dart';
import 'package:fyrlys/core/cast/chromecast.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/platform.dart';
import 'package:fyrlys/ui/player_page.dart';
import 'package:fyrlys/ui/vod_player_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

// Telefon-greinene (isAndroid): testene kjører på Linux, så de settes for hånd. Kanalene til Android selv (varsel,
// installering, multicast) svarer ikke her; AndroidHost tåler det.

Future<Session> _session() async {
  SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
  final source = FakeSource();
  final session = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => source);
  await session.restore();
  await session.load();
  return session;
}

/// En telefon på høykant (eller på tvers).
void _phone(WidgetTester tester, {bool sideways = false}) {
  isAndroid = true;
  addTearDown(() => isAndroid = false);
  tester.view.physicalSize = sideways ? const Size(860, 400) : const Size(400, 860);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

FakeCaster _fakeCaster() {
  final fake = FakeCaster();
  appCaster = fake;
  addTearDown(() => appCaster = ChromecastCaster());
  return fake;
}

/// Ikke pumpAndSettle: spinnerne går så lenge noe laster.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Som når Android sier at appen er lagt bort eller kommer fram igjen.
Future<void> _lifecycle(WidgetTester tester, AppLifecycleState state) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    SystemChannels.lifecycle.name,
    const StringCodec().encodeMessage(state.toString()),
    (_) {},
  );
  await tester.pump();
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  testWidgets('TV-spilleren på høykant: «Cast til TV» under bildet, ingen minispiller eller volumglidebryter',
      (tester) async {
    _phone(tester);
    final fake = _fakeCaster();
    final session = await _session();
    final playback = FakePlayback();
    await tester.pumpWidget(MaterialApp(
      home: PlayerPage(session: session, channels: session.channels, index: 0, playback: () => playback),
    ));
    await _settle(tester);
    expect(playback.urls, ['http://example/101.ts']);
    expect(find.byTooltip('Minispiller (I)'), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.byTooltip('Fullskjerm (F)'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Cast til TV'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('cast-device-stue')));
    await _settle(tester);
    expect(fake.calls, ['connect stue']);
    expect(fake.loads.single.title, 'NRK 1 HD');
    expect(playback.playing, isFalse);
    // mens det castes, står ikke knappen der
    expect(find.widgetWithText(OutlinedButton, 'Cast til TV'), findsNothing);
    await _close(tester);
  });

  testWidgets('TV-spilleren på tvers: bare bildet, og ingen knapp for å gå ut av fullskjerm (snu telefonen)',
      (tester) async {
    _phone(tester, sideways: true);
    _fakeCaster();
    final session = await _session();
    final playback = FakePlayback();
    await tester.pumpWidget(MaterialApp(
      home: PlayerPage(session: session, channels: session.channels, index: 0, playback: () => playback),
    ));
    await _settle(tester);
    expect(find.byTooltip('Kanaler (C)'), findsOneWidget);
    expect(find.byTooltip('Fullskjerm (F)'), findsNothing);
    expect(find.byTooltip('Avslutt fullskjerm (F)'), findsNothing);
    // på tvers er det plass til cast-knappen i bildet
    expect(find.byTooltip('Cast til TV (Chromecast)'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('TV-spilleren: appen lagt bort stopper kanalen (tilkoblingen blir ledig), og den startes igjen etterpå',
      (tester) async {
    _phone(tester);
    _fakeCaster();
    final session = await _session();
    final playback = FakePlayback();
    await tester.pumpWidget(MaterialApp(
      home: PlayerPage(session: session, channels: session.channels, index: 0, playback: () => playback),
    ));
    await _settle(tester);
    expect(playback.urls, hasLength(1));
    await _lifecycle(tester, AppLifecycleState.paused);
    expect(playback.playing, isFalse);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await _settle(tester);
    expect(playback.urls, hasLength(2));
    expect(playback.playing, isTrue);
    await _close(tester);
  });

  testWidgets('TV-spilleren: lagt bort mens det castes, fortsetter castingen (telefonen sender videre)',
      (tester) async {
    _phone(tester);
    final fake = _fakeCaster();
    final session = await _session();
    final playback = FakePlayback();
    await tester.pumpWidget(MaterialApp(
      home: PlayerPage(session: session, channels: session.channels, index: 0, playback: () => playback),
    ));
    await _settle(tester);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cast til TV'));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('cast-device-stue')));
    await _settle(tester);
    await _lifecycle(tester, AppLifecycleState.paused);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await _settle(tester);
    expect(fake.calls, isNot(contains('stop')));
    expect(fake.loads, hasLength(1));
    expect(playback.urls, hasLength(1));
    await _close(tester);
  });

  testWidgets('filmspilleren på telefonen: hele skjermen, cast-knappen også i et smalt bilde, og pause når appen '
      'legges bort', (tester) async {
    _phone(tester);
    _fakeCaster();
    final session = await _session();
    final playback = FakePlayback()..length = const Duration(minutes: 100);
    await tester.pumpWidget(MaterialApp(
      home: VodPlayerPage(
        session: session,
        items: const [VodPlayItem(key: 'film:201', title: 'Fyrlyset', url: 'http://example/movie/201.mp4')],
        playback: () => playback,
      ),
    ));
    await _settle(tester);
    expect(find.byTooltip('Cast til TV (Chromecast)'), findsOneWidget);
    expect(find.byTooltip('Fullskjerm (F)'), findsNothing);
    expect(find.byTooltip('Minispiller (I)'), findsNothing);
    expect(playback.playing, isTrue);
    await _lifecycle(tester, AppLifecycleState.paused);
    expect(playback.playing, isFalse);
    await _lifecycle(tester, AppLifecycleState.resumed);
    await _settle(tester);
    await _close(tester);
  });
}
