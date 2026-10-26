import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/app.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/core/updater.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const _json = {'content-type': 'application/json; charset=utf-8'};

Map<String, Object?> _release(int build, {int size = 4}) => {
      'name': 'Fyrlys 0.1.0',
      // byggnummeret står skjult (vises ikke på GitHub)
      'body': 'Siste endringer:\n- volum\n\n<!-- bygg $build -->',
      'assets': [
        {'name': 'Fyrlys-android-arm64-v8a.apk', 'browser_download_url': 'https://example/a.apk', 'size': 10},
        {'name': 'Fyrlys-windows.zip', 'browser_download_url': 'https://example/w.zip', 'size': size},
      ],
    };

void main() {
  test('leser byggnummeret og fila for plattformen fra releasen', () {
    final info = parseRelease(_release(7), '-windows.zip')!;
    expect(info.build, 7);
    expect(info.title, 'Fyrlys 0.1.0');
    expect(info.label, 'Fyrlys 0.1.0');
    expect(info.url, 'https://example/w.zip');
    expect(info.size, 4);
    expect(info.notes, 'Siste endringer:\n- volum');
    // releaser fra før 2.1.10 hadde byggnummeret i navnet
    final old = parseRelease({
      'name': 'Fyrlys 2.1.8 · bygg 31 (abc1234)',
      'assets': [
        {'name': 'Fyrlys-testbygg-windows.zip', 'browser_download_url': 'https://example/w.zip', 'size': 4},
      ],
    }, '-windows.zip')!;
    expect(old.build, 31);
    expect(old.label, 'Fyrlys 2.1.8');
    expect(parseRelease({'name': 'Fyrlys v0.1.0', 'assets': <Object>[]}, '-windows.zip'), isNull);
    expect(parseRelease(_release(7), '-macos.zip'), isNull);
  });

  group('Updater', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('fyrlys-oppdatering'));
    tearDown(() => dir.deleteSync(recursive: true));

    Updater updater(int? current, http.Client client) => Updater(
          client: client,
          currentBuild: current,
          assetSuffix: '-windows.zip',
          workDir: dir.path,
          canInstall: false,
          repo: 'ungerdas/fyrlys',
        );

    test('nytt bygg lastes ned, og står klart neste gang uten ny nedlasting', () async {
      var downloads = 0;
      final client = MockClient((r) async {
        if (r.url.host == 'api.github.com') {
          expect(r.url.path, '/repos/ungerdas/fyrlys/releases/latest');
          return http.Response(jsonEncode(_release(7)), 200, headers: _json);
        }
        downloads++;
        return http.Response.bytes([1, 2, 3, 4], 200);
      });
      final u = updater(5, client);
      final info = await u.check();
      expect(info?.build, 7);
      expect(u.state, UpdateState.available);

      await u.download();
      expect(u.state, UpdateState.ready);
      expect(downloads, 1);
      final ready = jsonDecode(File('${dir.path}/klar.json').readAsStringSync()) as Map;
      expect(ready['build'], 7);
      expect(File('${ready['zip']}').lengthSync(), 4);

      final again = updater(5, client);
      await again.check();
      expect(again.state, UpdateState.ready);
      expect(downloads, 1);
    });

    test('siste release uten byggnummer (før 2.1.10): releasen «testbygg» er reserven', () async {
      final paths = <String>[];
      final client = MockClient((r) async {
        paths.add(r.url.path);
        if (r.url.path.endsWith('/latest')) {
          return http.Response(
            jsonEncode({
              'name': 'Fyrlys v2.0.0',
              'assets': [
                {'name': 'Fyrlys-v2.0.0-windows.zip', 'browser_download_url': 'https://example/old.zip', 'size': 4},
              ],
            }),
            200,
            headers: _json,
          );
        }
        return http.Response(
          jsonEncode({
            'name': 'Fyrlys 2.1.9 · bygg 9',
            'assets': [
              {'name': 'Fyrlys-windows.zip', 'browser_download_url': 'https://example/w.zip', 'size': 4},
            ],
          }),
          200,
          headers: _json,
        );
      });
      final info = await updater(5, client).check();
      expect(info?.build, 9);
      expect(info?.label, 'Fyrlys 2.1.9');
      expect(paths, ['/repos/ungerdas/fyrlys/releases/latest', '/repos/ungerdas/fyrlys/releases/tags/testbygg']);
    });

    test('samme eller eldre bygg: ingenting å gjøre', () async {
      final client = MockClient((r) async => http.Response(jsonEncode(_release(7)), 200, headers: _json));
      expect(await updater(7, client).check(), isNull);
      expect(await updater(9, client).check(), isNull);
    });

    test('testbyggene er ikke synlige (privat repo): ikke «siste versjon», men en forklaring', () async {
      final missing = MockClient((r) async => http.Response('{"message":"Not Found"}', 404, headers: _json));
      final u = updater(5, missing);
      expect(await u.check(), isNull);
      expect(u.state, UpdateState.idle);
      await expectLater(
        u.check(manual: true),
        throwsA(isA<UpdateException>().having((e) => e.message, 'message', contains('ikke de nye versjonene'))),
      );
      // fra oppdateringsserveren: forklaringen derfra
      final server = MockClient((r) async => http.Response('{"error": "Fant ikke testbyggene på GitHub"}', 404));
      final v = updater(5, server)..serverBase = () => 'http://192.168.1.10:8766';
      await expectLater(
        v.check(manual: true),
        throwsA(isA<UpdateException>().having((e) => e.message, 'message', 'Fant ikke testbyggene på GitHub')),
      );
    });

    test('en nedlasting som stopper halvveis gir feil, ikke en halv oppdatering', () async {
      final client = MockClient((r) async => r.url.host == 'api.github.com'
          ? http.Response(jsonEncode(_release(7, size: 100)), 200, headers: _json)
          : http.Response.bytes([1, 2, 3], 200));
      final u = updater(5, client);
      await u.check();
      await u.download();
      expect(u.state, UpdateState.failed);
      expect(u.error, contains('ikke fullført'));
      expect(File('${dir.path}/klar.json').existsSync(), isFalse);
    });

    test('GitHub svarer ikke: stille ved automatisk sjekk, feil ved manuell', () async {
      final client = MockClient((r) async => http.Response('oops', 500));
      final u = updater(5, client);
      expect(await u.check(), isNull);
      expect(u.state, UpdateState.idle);
      await expectLater(u.check(manual: true), throwsA(isA<UpdateException>()));
    });

    test('via Fyrlys-serveren: spør serveren, og laster ned derfra', () async {
      final urls = <String>[];
      final client = MockClient((r) async {
        urls.add(r.url.toString());
        if (r.url.path == '/api/app/release') {
          return http.Response(
            jsonEncode({
              'name': 'Fyrlys 0.1.0 · bygg 7 (abc1234)',
              'body': '',
              'assets': [
                {
                  'name': 'Fyrlys-windows.zip',
                  'size': 4,
                  'browser_download_url': 'download/Fyrlys-windows.zip',
                },
              ],
            }),
            200,
            headers: _json,
          );
        }
        return http.Response.bytes([1, 2, 3, 4], 200);
      });
      final u = updater(5, client)..serverBase = () => 'http://192.168.1.10:8766';
      final info = await u.check();
      expect(info?.url, 'http://192.168.1.10:8766/api/app/download/Fyrlys-windows.zip');
      await u.download();
      expect(u.state, UpdateState.ready);
      expect(urls, [
        'http://192.168.1.10:8766/api/app/release',
        'http://192.168.1.10:8766/api/app/download/Fyrlys-windows.zip',
      ]);
    });

    test('serveren uten GitHub-nøkkel: forklaringen vises ved manuell sjekk', () async {
      final client = MockClient(
        (r) async => http.Response(
          jsonEncode({'error': 'Serveren har ingen GitHub-nøkkel (data/github.json)'}),
          503,
          headers: _json,
        ),
      );
      final u = updater(5, client)..serverBase = () => 'http://192.168.1.10:8766';
      expect(await u.check(), isNull);
      await expectLater(
        u.check(manual: true),
        throwsA(isA<UpdateException>().having((e) => e.message, 'message', contains('GitHub-nøkkel'))),
      );
    });

    test('egne bygg (uten byggnummer) ser ikke etter oppdateringer', () async {
      final u = updater(null, MockClient((r) async => fail('skal ikke spørre GitHub')));
      expect(u.enabled, isFalse);
      expect(await u.check(), isNull);
    });
  });

  testWidgets('TV-siden sier fra om ny versjon, med hva som er nytt', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final dir = Directory.systemTemp.createTempSync('fyrlys-banner');
    addTearDown(() => dir.deleteSync(recursive: true));
    SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
    final session = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => FakeSource());
    await session.restore();
    final u = Updater(
      client: MockClient((r) async => http.Response(jsonEncode(_release(7)), 200, headers: _json)),
      currentBuild: 5,
      assetSuffix: '-windows.zip',
      workDir: dir.path,
      canInstall: false,
    );
    await tester.runAsync(() => u.check());

    await tester.pumpWidget(FyrlysApp(session: session, updater: u));
    await tester.pumpAndSettle();
    expect(find.text('Ny versjon: Fyrlys 0.1.0'), findsOneWidget);
    expect(find.text('Last ned'), findsOneWidget);

    await tester.tap(find.text('Hva er nytt?'));
    await tester.pumpAndSettle();
    expect(find.textContaining('volum'), findsOneWidget);
  });
}
