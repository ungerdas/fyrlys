import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/app.dart';
import 'package:fyrlys/core/app_log.dart';
import 'package:fyrlys/core/report.dart';
import 'package:fyrlys/core/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

void main() {
  test('vasket: leverandøren, innloggingen, e-post og brukernavnet i Windows', () {
    expect(scrub('Failed to open http://iptv.example.com:8080/live/kari/hemmelig/123.ts'),
        'Failed to open http://***/live/***/***/123.ts');
    expect(scrub('https://example.org/timeshift/kari/hemmelig/60/2026-10-26:20-00/5.m3u8'),
        'https://***/timeshift/***/***/60/2026-10-26:20-00/5.m3u8');
    expect(scrub('get.php?username=kari&password=hemmelig&type=m3u'), 'get.php?username=***&password=***&type=m3u');
    expect(scrub('ClientException: Connection refused, address = 10.0.0.5, port = 80'),
        'ClientException: Connection refused, address = ***, port = 80');
    expect(scrub('kari.nordmann@example.no'), '***@***');
    expect(scrub(r'C:\Users\Kari Nordmann\AppData\Local\Fyrlys'), r'C:\Users\***\AppData\Local\Fyrlys');
    expect(scrub('Fyrlys 2.1.20 · H.264 · 8,1 Mbit/s'), 'Fyrlys 2.1.20 · H.264 · 8,1 Mbit/s');
  });

  test('loggen: klokkeslett, vasket, og bare de siste linjene', () {
    final log = AppLog(max: 3);
    log.add('mpv: Failed to open http://iptv.example/live/u/p/1.ts', at: DateTime(2026, 10, 26, 9, 5, 7));
    expect(log.lines.single, '09:05:07 mpv: Failed to open http://***/live/***/***/1.ts');
    log.add('a\nb\n\nc\nd', at: DateTime(2026, 10, 26, 9, 5, 8));
    expect(log.lines, ['09:05:08 b', '09:05:08 c', '09:05:08 d']);
  });

  test('feilrapporten: versjon, innstillinger og loggen, uten navn og leverandør', () async {
    SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
    final s = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => FakeSource(connections: 1));
    await s.restore();
    await s.load();
    await s.renameLogin(s.activeLogin!, 'Hjemme hos Kari');
    AppLog.instance
      ..clear()
      ..add('mpv: Failed to open http://iptv.example:8080/live/kari/hemmelig/101.ts');
    addTearDown(AppLog.instance.clear);

    final text = await buildReport(
      s,
      now: DateTime(2026, 10, 26, 21, 14),
      windows: '"Windows 11 Home" 10.0 (Build 26100)',
      updateLog: r'2026-10-26 20:00 Pakker ut C:\Users\Kari\AppData\Local\Fyrlys',
    );
    expect(text, contains('Laget: 2026-10-26 21:14'));
    expect(text, contains('Windows: "Windows 11 Home" 10.0 (Build 26100)'));
    expect(text, contains('Innlogginger: 1'));
    expect(text, contains('1 tilkobling'));
    expect(text, contains('Kanaler: 3'));
    expect(text, contains('Fjern striper (deinterlacing): på'));
    expect(text, contains('mpv: Failed to open http://***/live/***/***/101.ts'));
    expect(text, contains(r'C:\Users\***\AppData'));
    expect(text, isNot(contains('Kari')));
    expect(text, isNot(contains('hemmelig')));
    expect(text, isNot(contains('iptv.example')));
    expect(text, contains('\r\n'));
  });

  test('Windows 11 heter Windows 11 (Windows sier selv «Windows 10» med bygg 22000 og høyere)', () {
    expect(windowsName('"Windows 10 Pro" 10.0 (Build 26100)'), '"Windows 11 Pro" 10.0 (Build 26100)');
    expect(windowsName('"Windows 10 Home" 10.0 (Build 22000)'), '"Windows 11 Home" 10.0 (Build 22000)');
    expect(windowsName('"Windows 10 Pro" 10.0 (Build 19045)'), '"Windows 10 Pro" 10.0 (Build 19045)');
    expect(windowsName('"Windows 11 Home" 10.0 (Build 26100)'), '"Windows 11 Home" 10.0 (Build 26100)');
    expect(windowsName('Linux 6.1'), 'Linux 6.1');
  });

  test('lagres i Nedlastinger med dato i navnet', () async {
    final dir = Directory.systemTemp.createTempSync('fyrlys-rapport');
    addTearDown(() => dir.deleteSync(recursive: true));
    final before = reportDirectory;
    reportDirectory = () async => dir;
    addTearDown(() => reportDirectory = before);
    final file = await saveReport('innhold', now: DateTime(2026, 10, 26, 21, 4));
    expect(file.path, endsWith('Fyrlys-feilrapport-2026-10-26-2104.txt'));
    expect(file.readAsStringSync(), 'innhold');
  });

  testWidgets('innstillingene: «Meld fra om en feil» åpner GitHub', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final opened = <String>[];
    final before = openUrl;
    openUrl = (url) async => opened.add(url);
    addTearDown(() => openUrl = before);
    SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
    final session = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => FakeSource());
    await session.restore();
    await tester.pumpWidget(FyrlysApp(session: session));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Innstillinger'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Meld fra om en feil'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(find.text('HJELP'), findsOneWidget);
    expect(find.text('Lagre feilrapport'), findsOneWidget);
    await tester.tap(find.text('Meld fra om en feil'));
    await tester.pump();
    expect(opened, ['https://github.com/ungerdas/fyrlys/issues/new/choose']);
  });
}
