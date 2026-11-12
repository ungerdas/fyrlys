import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/app.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/core/updater.dart';
import 'package:fyrlys/platform.dart';
import 'package:fyrlys/ui/playback.dart';
import 'package:fyrlys/ui/playback_tizen.dart';
import 'package:fyrlys/ui/player_page.dart';
import 'package:fyrlys/ui/vod_player_page.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

// Samsung-TV-greinene (isTizen): testene kjører på Linux, så den settes for hånd. TV-ens avspiller (AVPlay) finnes
// ikke her; det som kan prøves uten den, er undertekstfilene, adressene og spillerne med en falsk avspiller.

Future<Session> _session() async {
  SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
  final source = FakeSource();
  final session = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => source);
  await session.restore();
  await session.load();
  return session;
}

/// En TV: 1920×1080 med pikseltettheten flutter-tizen gir TV-er (72/90 × 2 = 1,6), altså 1200×675.
void _tv(WidgetTester tester) {
  isTizen = true;
  addTearDown(() => isTizen = false);
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1.6;
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

void main() {
  group('undertekstfiler (Plex) på TV-en', () {
    test('SubRip: tidene, flere linjer og uten formatering', () {
      final cues = parseSubtitleCues('1\r\n00:00:01,500 --> 00:00:03,000\r\n<i>Hei</i>\r\nder\r\n\r\n'
          '2\r\n00:01:02,000 --> 00:01:04,250\r\n{\\an8}Neste\r\n');
      expect(cues, hasLength(2));
      expect(cues[0].start, const Duration(milliseconds: 1500));
      expect(cues[0].text, 'Hei\nder');
      expect(cues[1].end, const Duration(minutes: 1, seconds: 4, milliseconds: 250));
      expect(cues[1].text, 'Neste');
      expect(cueAt(cues, const Duration(seconds: 2)), 'Hei\nder');
      expect(cueAt(cues, const Duration(seconds: 10)), isNull);
      expect(cueAt(cues, Duration.zero), isNull);
      expect(cueAt(cues, const Duration(minutes: 1, seconds: 3)), 'Neste');
    });

    test('WebVTT, også uten timer', () {
      final cues = parseSubtitleCues('WEBVTT\n\n00:01.000 --> 00:04.000 align:start\nFørst\n\n'
          '00:00:05.000 --> 00:00:06.000\nSå\n');
      expect([for (final c in cues) c.text], ['Først', 'Så']);
      expect(cues.first.start, const Duration(seconds: 1));
      expect(cues.last.end, const Duration(seconds: 6));
    });
  });

  test('pakken som passer TV-en, og feilen når en annen er installert', () {
    expect(tizenPackageFor('6.0'), 'Fyrlys-tizen-2021.tpk');
    expect(tizenPackageFor('6.5'), 'Fyrlys-tizen-2022-2025.tpk');
    expect(tizenPackageFor('9.0'), 'Fyrlys-tizen-2022-2025.tpk');
    expect(tizenPackageFor('10.0'), 'Fyrlys-tizen-2026.tpk');
    // slik video_player_avplay sier det
    expect(
      avplayError(Exception('The current TizenOS version is 8.0 and the app API version(6.0). The app API version '
          'must be at least 6.5.')),
      'Denne Fyrlys-pakken er for en annen Samsung-TV. TV-en har Tizen 8.0: installer Fyrlys-tizen-2022-2025.tpk.',
    );
    expect(avplayError(PlatformException(code: 'Operation failed', message: 'Failed to create a player.')),
        'Failed to create a player.');
  });

  test('Plex-hodene i adressen (AVPlay sender bare User-Agent og Cookie)', () {
    final url = AvplayPlayback.withHeadersInUrl('http://192.168.1.10:32400/library/parts/1/file.mkv',
        {'X-Plex-Token': 'abc', 'User-Agent': 'Fyrlys', 'X-Plex-Client-Identifier': 'id1'});
    expect(Uri.parse(url).queryParameters, {'X-Plex-Token': 'abc', 'X-Plex-Client-Identifier': 'id1'});
    expect(AvplayPlayback.withHeadersInUrl('http://example/live/1.m3u8', {'User-Agent': 'VLC/3.0.21'}),
        'http://example/live/1.m3u8');
  });

  test('kodekene fra TV-ens avspiller', () {
    expect(AvplayPlayback.mimeCodec('video/x-h265'), 'H.265');
    expect(AvplayPlayback.mimeCodec('video/x-h264'), 'H.264');
    expect(AvplayPlayback.mimeCodec('audio/x-eac3'), 'E-AC3');
    expect(AvplayPlayback.mimeCodec('audio/x-ac3'), 'AC3');
  });

  testWidgets('TV-spilleren på TV-en: ingen Chromecast, volum, minispiller eller multiview; Info gir knappene',
      (tester) async {
    _tv(tester);
    final session = await _session();
    final playback = FakePlayback();
    await tester.pumpWidget(MaterialApp(
      home: PlayerPage(session: session, channels: session.channels, index: 0, playback: () => playback),
    ));
    await _settle(tester);
    expect(playback.urls, ['http://example/101.ts']);
    expect(find.byTooltip('Cast til TV (Chromecast)'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Cast til TV'), findsNothing);
    expect(find.byTooltip('Minispiller (I)'), findsNothing);
    expect(find.byTooltip('Lyd av (M)'), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(session.canMultiview, isFalse);

    // Info (eller grønn): fokus til knappene under bildet, og da bytter ↓ ikke kanal
    // (testene kjenner ikke fjernkontrollens taster, så den fysiske tasten oppgis)
    await tester.sendKeyEvent(LogicalKeyboardKey.info, physicalKey: PhysicalKeyboardKey.info);
    await _settle(tester);
    if (FocusManager.instance.primaryFocus?.debugLabel == 'spiller') debugDumpFocusTree();
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('spiller'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(playback.urls, hasLength(1));
    expect(find.byType(PlayerPage), findsOneWidget);

    // Tilbake (Esc på TV-en) går tilbake til bildet, og ↓ bytter kanal igjen
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'spiller');
    expect(find.byType(PlayerPage), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);
    expect(playback.urls, hasLength(2));
    await _close(tester);
  });

  testWidgets('filmspilleren på TV-en: ↑ går til knappene, alltid hele skjermen, ingen volum eller Chromecast',
      (tester) async {
    _tv(tester);
    final session = await _session();
    final fake = FakePlayback()..length = const Duration(minutes: 100);
    playbackFactory = () => fake;
    addTearDown(() => playbackFactory = MpvPlayback.new);
    await tester.pumpWidget(MaterialApp(
      home: VodPlayerPage(
        session: session,
        items: const [VodPlayItem(key: 'film:201', title: 'Fyrlyset', url: 'http://example/movie/201.mkv')],
      ),
    ));
    await _settle(tester);
    expect(fake.urls, ['http://example/movie/201.mkv']);
    expect(find.byTooltip('Fullskjerm (F)'), findsNothing);
    expect(find.byTooltip('Cast til TV (Chromecast)'), findsNothing);
    expect(find.byTooltip('Lyd av (M)'), findsNothing);

    // → spoler når bildet har fokus
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(fake.seeks, [const Duration(seconds: 10)]);
    expect(fake.volume, 100);

    // ↑: knappene (ikke volumet); da flytter ←/→ mellom dem i stedet for å spole
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await _settle(tester);
    expect(fake.volume, 100);
    if (FocusManager.instance.primaryFocus?.debugLabel == 'filmspiller') debugDumpFocusTree();
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('filmspiller'));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(fake.seeks, hasLength(1));

    // Tilbake fra knappene lukker ikke spilleren, men går tilbake til bildet
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.byType(VodPlayerPage), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'filmspiller');
    await _close(tester);
  });

  testWidgets('ny versjon på TV-en: installeres fra PC-en eller telefonen, ingen nedlasting', (tester) async {
    _tv(tester);
    final dir = Directory.systemTemp.createTempSync('fyrlys-tv');
    addTearDown(() => dir.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
    final session = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => FakeSource());
    await session.restore();
    final u = Updater(
      client: MockClient((r) async => http.Response(
            jsonEncode({
              'name': 'Fyrlys 2.1.48',
              'body': 'Samsung-TV\n\n<!-- bygg 7 -->',
              'assets': [
                {'name': 'Fyrlys-windows.zip', 'browser_download_url': 'https://example/w.zip', 'size': 4},
                {'name': 'Fyrlys-tizen-2022-2025.tpk', 'browser_download_url': 'https://example/t.tpk', 'size': 4},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
      currentBuild: 5,
      workDir: dir.path,
      repo: 'ungerdas/fyrlys',
    );
    expect(u.installElsewhere, isTrue);
    expect(u.assetSuffix, '.tpk');
    await tester.runAsync(() => u.check());
    expect(u.state, UpdateState.available);

    await tester.pumpWidget(FyrlysApp(session: session, updater: u));
    await tester.pumpAndSettle();
    expect(find.textContaining('Installer den på TV-en fra PC-en eller telefonen'), findsOneWidget);
    expect(find.text('Last ned'), findsNothing);
  });
}
