import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/cast/caster.dart';
import 'package:fyrlys/core/cast/chromecast.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/theme.dart';
import 'package:fyrlys/ui/cast_ui.dart';
import 'package:fyrlys/ui/player_page.dart';
import 'package:fyrlys/ui/vod_player_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

Future<Session> _session() async {
  SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
  final source = FakeSource();
  final session = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => source);
  await session.restore();
  await session.load();
  return session;
}

FakeCaster _fakeCaster() {
  final fake = FakeCaster();
  appCaster = fake;
  addTearDown(() => appCaster = ChromecastCaster());
  return fake;
}

void _size(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Ikke pumpAndSettle: spinnerne går så lenge noe laster.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

/// Cast-knappen, og Chromecasten «Stue» i lista.
Future<void> _castToStue(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Cast til TV (Chromecast)'));
  await _settle(tester);
  expect(find.text('Cast til TV'), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('cast-device-stue')));
  await _settle(tester);
}

Finder _inPanel(Finder f) => find.descendant(of: find.byKey(const ValueKey('cast-panel')), matching: f);

void main() {
  testWidgets('TV: kanalen spilles på Chromecasten, PC-en stopper, kanalbytte caster, «Stopp casting» spiller her igjen',
      (tester) async {
    _size(tester);
    final fake = _fakeCaster();
    final session = await _session();
    final playback = FakePlayback();
    await tester.pumpWidget(MaterialApp(
      theme: fyrlysTheme(Brightness.light),
      home: PlayerPage(session: session, channels: session.channels, index: 0, playback: () => playback),
    ));
    await _settle(tester);
    expect(playback.urls, ['http://example/101.ts']);

    await _castToStue(tester);
    expect(fake.calls, ['connect stue']);
    expect(playback.playing, isFalse);
    expect(fake.loads, hasLength(1));
    expect(fake.loads.single.title, 'NRK 1 HD');
    expect(fake.loads.single.live, isTrue);
    expect(fake.loads.single.urls, ['http://example/101.ts']);
    expect(find.byKey(const ValueKey('cast-panel')), findsOneWidget);
    expect(find.text('Spilles på Stue'), findsOneWidget);

    // neste kanal går til TV-en, ikke hit
    await tester.tap(_inPanel(find.byTooltip('Neste kanal (↓)')));
    await tester.pump(const Duration(milliseconds: 700));
    await _settle(tester);
    expect(fake.loads, hasLength(2));
    expect(fake.loads.last.title, 'TV 2 HD');
    expect(playback.urls, hasLength(1));

    // pause og lyd styrer TV-en
    await tester.tap(find.byKey(const ValueKey('cast-play')));
    await tester.pump();
    expect(fake.calls.last, 'pause');

    await tester.tap(find.byKey(const ValueKey('cast-stop')));
    await _settle(tester);
    expect(fake.calls.last, 'stop');
    expect(find.byKey(const ValueKey('cast-panel')), findsNothing);
    expect(playback.urls, ['http://example/101.ts', 'http://example/102.ts']);
    await _close(tester);
  });

  testWidgets('TV: Chromecasten blir borte – kanalen spilles her igjen, og det står hvorfor', (tester) async {
    _size(tester);
    final fake = _fakeCaster();
    final session = await _session();
    final playback = FakePlayback();
    await tester.pumpWidget(MaterialApp(
      home: PlayerPage(session: session, channels: session.channels, index: 0, playback: () => playback),
    ));
    await _settle(tester);
    await _castToStue(tester);
    expect(playback.urls, hasLength(1));
    fake.lose();
    await _settle(tester);
    expect(playback.urls, hasLength(2));
    expect(find.text('Mistet kontakten med Stue.'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('TV: Chromecasten kan ikke spille kanalen – beskjed og «Prøv igjen»', (tester) async {
    _size(tester);
    final fake = _fakeCaster();
    final session = await _session();
    final playback = FakePlayback();
    await tester.pumpWidget(MaterialApp(
      home: PlayerPage(session: session, channels: session.channels, index: 0, playback: () => playback),
    ));
    await _settle(tester);
    await _castToStue(tester);
    fake.fail('Chromecasten kunne ikke spille dette.');
    await _settle(tester);
    expect(find.text('Chromecasten kunne ikke spille dette.'), findsWidgets);
    await tester.tap(find.text('Prøv igjen'));
    await _settle(tester);
    expect(fake.loads, hasLength(2));
    expect(playback.urls, hasLength(1));
    await _close(tester);
  });

  testWidgets('TV: får ikke kontakt med Chromecasten – kanalen spilles her igjen', (tester) async {
    _size(tester);
    final fake = _fakeCaster()..failConnect = true;
    final session = await _session();
    final playback = FakePlayback();
    await tester.pumpWidget(MaterialApp(
      home: PlayerPage(session: session, channels: session.channels, index: 0, playback: () => playback),
    ));
    await _settle(tester);
    await _castToStue(tester);
    expect(fake.calls, ['connect stue']);
    expect(playback.urls, hasLength(2));
    expect(find.text('Fikk ikke kontakt med Stue.'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('film: fortsetter på TV-en der du var, spoler der, og fortsetter her når castingen stopper',
      (tester) async {
    _size(tester);
    final fake = _fakeCaster();
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
    playback.moveTo(const Duration(seconds: 90));
    await _settle(tester);

    await _castToStue(tester);
    expect(fake.loads.single.urls, ['http://example/movie/201.mp4']);
    expect(fake.loads.single.live, isFalse);
    expect(fake.loads.single.start, const Duration(seconds: 90));
    expect(fake.loads.single.contentType, 'video/mp4');
    expect(find.text('Spilles på Stue'), findsOneWidget);
    expect(find.byKey(const ValueKey('cast-timeline')), findsOneWidget);

    // +10 s spoler på TV-en (samlet litt først)
    await tester.tap(_inPanel(find.byTooltip('10 sekunder fram (→)')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(fake.calls.last, 'seek 100');

    // et par sekunder på TV-en, så stopp: fortsetter her der TV-en var
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.byKey(const ValueKey('cast-stop')));
    await _settle(tester);
    expect(fake.calls.last, 'stop');
    expect(playback.urls, hasLength(2));
    expect(playback.starts.last, const Duration(seconds: 100));
    await _close(tester);
  });

  testWidgets('linja på forsiden: vises mens det castes, og stopper', (tester) async {
    final fake = FakeCaster();
    await tester.pumpWidget(MaterialApp(home: Scaffold(bottomNavigationBar: CastBar(caster: fake))));
    expect(find.byKey(const ValueKey('cast-bar')), findsNothing);
    await fake.connect(fake.devices.first);
    await fake.load(const CastItem(urls: ['http://x/1.m3u8'], title: 'NRK 1 HD', live: true));
    await tester.pump();
    expect(find.text('NRK 1 HD · Stue'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(fake.calls.last, 'pause');
    await tester.tap(find.byKey(const ValueKey('cast-bar-stop')));
    await tester.pump();
    expect(fake.calls.last, 'stop');
    expect(find.byKey(const ValueKey('cast-bar')), findsNothing);
  });

  testWidgets('ingen Chromecast på nettverket: forklaring og «Let igjen»', (tester) async {
    final fake = FakeCaster()..devices = [];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => pickCastDevice(context, caster: fake),
          child: const Text('åpne'),
        ),
      ),
    ));
    await tester.tap(find.text('åpne'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fant ingen Chromecast'), findsOneWidget);
    fake.devices = [const CastDevice(id: 'tv', name: 'Soverom', host: '192.168.1.21')];
    await tester.tap(find.text('Let igjen'));
    await tester.pumpAndSettle();
    expect(find.text('Soverom'), findsOneWidget);
    await tester.tap(find.text('Soverom'));
    await tester.pumpAndSettle();
    expect(find.text('Cast til TV'), findsNothing);
  });
}
