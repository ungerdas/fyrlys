import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/app.dart';
import 'package:fyrlys/core/models.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/ui/home_page.dart';
import 'package:fyrlys/ui/login_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Innlogginger med testkilden: navnet i det som er lagret, avgjør hvilken det er.
Future<Session> _session([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final s = Session(
    await SharedPreferences.getInstance(),
    sourceFactory: (saved) async => FakeSource(name: saved['name'] ?? 'Test'),
  );
  await s.restore();
  return s;
}

String _channels(List<Channel> list) => jsonEncode([for (final c in list) c.toJson()]);

const _nrk = Channel(id: '101', name: 'NRK 1 HD', categoryId: '1', number: '1');
const _tv2 = Channel(id: '102', name: 'TV 2 HD', categoryId: '1', number: '2');

void main() {
  test('innloggingen fra før 2.1.14 flyttes til lista, med favorittene og resten', () async {
    final s = await _session({
      'source': '{"kind":"fake"}',
      'favorites': _channels([_nrk]),
      'favoriteCategories': ['2'],
      'recent': _channels([_tv2]),
      'guide_cat': 'fav',
      'resume': '{"film:201":[120,6000,1]}',
    });
    expect(s.source?.label, 'Test');
    expect(s.logins.map((l) => l.name), ['Test']);
    expect(s.activeLogin, s.logins.single.id);
    expect(s.favorites.map((c) => c.id), ['101']);
    expect(s.favoriteCategories, ['2']);
    expect(s.recent.map((c) => c.id), ['102']);
    expect(s.guideCategory, 'fav');
    expect(s.resumeAt('film:201'), const Duration(minutes: 2));

    final prefs = await SharedPreferences.getInstance();
    for (final old in ['source', 'favorites', 'favoriteCategories', 'recent', 'guide_cat', 'resume']) {
      expect(prefs.containsKey(old), isFalse, reason: old);
    }

    // neste gang: samme innlogging, uten å flytte noe på nytt
    final again = Session(prefs, sourceFactory: (saved) async => FakeSource(name: saved['name'] ?? 'Test'));
    await again.restore();
    expect(again.logins, hasLength(1));
    expect(again.favorites.map((c) => c.id), ['101']);
  });

  test('logget ut før 2.1.14: favorittene fra før går til den første du logger inn med', () async {
    final s = await _session({'favorites': _channels([_nrk]), 'guide_cat': 'fav'});
    expect(s.source, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('favorites'), isTrue);

    await s.useSource(FakeSource(name: 'Ny'));
    expect(s.favorites.map((c) => c.id), ['101']);
    expect(s.guideCategory, 'fav');
    expect(prefs.containsKey('favorites'), isFalse);

    // den neste får ikke de samme
    await s.useSource(FakeSource(name: 'Sport'));
    expect(s.favorites, isEmpty);
  });

  test('to innlogginger: hver med sine favoritter, og du bytter mellom dem', () async {
    final s = await _session({'source': '{"kind":"fake"}'});
    final first = s.activeLogin!;
    await s.toggleFavorite(_nrk);
    s.addRecent(_nrk);

    await s.useSource(FakeSource(name: 'Sport'));
    expect(s.source?.label, 'Sport');
    expect(s.logins.map((l) => l.name), ['Test', 'Sport']);
    expect(s.activeLogin, isNot(first));
    expect(s.favorites, isEmpty);
    expect(s.recent, isEmpty);
    await s.toggleFavorite(_tv2);

    await s.switchLogin(first);
    expect(s.source?.label, 'Test');
    expect(s.favorites.map((c) => c.id), ['101']);
    expect(s.recent.map((c) => c.id), ['101']);

    // neste gang appen starter: den du brukte sist
    final prefs = await SharedPreferences.getInstance();
    final next = Session(prefs, sourceFactory: (saved) async => FakeSource(name: saved['name'] ?? 'Test'));
    await next.restore();
    expect(next.source?.label, 'Test');
    await next.switchLogin(next.logins.last.id);
    expect(next.favorites.map((c) => c.id), ['102']);
  });

  test('samme konto igjen blir ikke to, og navnet du har gitt den, står', () async {
    final s = await _session({'source': '{"kind":"fake"}'});
    await s.renameLogin(s.activeLogin!, 'Hjemme');
    await s.useSource(FakeSource());
    expect(s.logins.map((l) => l.name), ['Hjemme']);
    expect(s.currentLogin?.name, 'Hjemme');
  });

  test('logg ut: den neste tas i bruk; favorittene er der igjen når du logger inn på nytt', () async {
    final s = await _session({'source': '{"kind":"fake"}'});
    final first = s.activeLogin!;
    await s.useSource(FakeSource(name: 'Sport'));
    await s.toggleFavorite(_tv2);

    await s.logout();
    expect(s.activeLogin, first);
    expect(s.source?.label, 'Test');
    expect(s.logins.map((l) => l.name), ['Test']);

    await s.removeLogin(first);
    expect(s.source, isNull);
    expect(s.logins, isEmpty);
    expect(s.favorites, isEmpty);

    await s.useSource(FakeSource(name: 'Sport'));
    expect(s.favorites.map((c) => c.id), ['102']);
  });

  test('id-en er kontoen, ikke passordet', () {
    final a = Session.loginId({'kind': 'xtream', 'server': 'http://iptv.example', 'user': 'kari', 'password': 'en'});
    final b = Session.loginId({'kind': 'xtream', 'server': 'http://iptv.example', 'user': 'kari', 'password': 'to'});
    final c = Session.loginId({'kind': 'xtream', 'server': 'http://iptv.example', 'user': 'ola', 'password': 'en'});
    expect(a, b);
    expect(a, isNot(c));
    final m1 = Session.loginId({'kind': 'm3u', 'url': 'http://iptv.example/get.php?username=kari&password=en'});
    final m2 = Session.loginId({'kind': 'm3u', 'url': 'http://iptv.example/get.php?username=kari&password=to'});
    expect(m1, m2);
  });

  testWidgets('menyen: bytt innlogging, gi nytt navn, legg til og logg ut', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final s = await _session({'source': '{"kind":"fake"}'});
    await s.useSource(FakeSource(name: 'Sport'));
    await tester.pumpWidget(FyrlysApp(session: s));
    await tester.pumpAndSettle();

    // øverst i menyen: den du bruker («Sport» er også en kategori, så det trykkes på teksten under)
    await tester.tap(find.byTooltip('Meny'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, 'Sport'), findsOneWidget);
    await tester.tap(find.text('Bytt innlogging'));
    await tester.pumpAndSettle();
    expect(find.text('Innlogginger'), findsOneWidget);
    expect(find.text('fake · i bruk'), findsOneWidget);

    // bytt til den andre
    await tester.tap(find.text('Test'));
    await tester.pumpAndSettle();
    expect(s.source?.label, 'Test');
    expect(find.text('Innlogginger'), findsNothing);
    expect(find.text('Byttet til Test'), findsOneWidget);
    expect(find.byType(HomePage), findsOneWidget);

    // gi den et navn
    await tester.tap(find.byTooltip('Meny'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bytt innlogging'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mer om Test'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gi nytt navn'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Hjemme');
    await tester.tap(find.text('Lagre'));
    await tester.pumpAndSettle();
    expect(find.text('Hjemme'), findsOneWidget);
    expect(s.currentLogin?.name, 'Hjemme');

    // en til: innloggingen åpnes over appen, og lukkes med pila
    await tester.tap(find.text('Legg til innlogging'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('Ny innlogging'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsNothing);

    // logg ut: spør først, og bytter så til den andre
    await tester.tap(find.byTooltip('Meny'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logg ut'));
    await tester.pumpAndSettle();
    expect(find.text('Logg ut av Hjemme?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Logg ut'));
    await tester.pumpAndSettle();
    expect(s.source?.label, 'Sport');
    expect(s.logins.map((l) => l.name), ['Sport']);
    expect(find.byType(HomePage), findsOneWidget);

    // én igjen: menyen tilbyr å legge til en
    await tester.tap(find.byTooltip('Meny'));
    await tester.pumpAndSettle();
    expect(find.text('Legg til en innlogging'), findsOneWidget);
    await tester.tapAt(const Offset(10, 890));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
