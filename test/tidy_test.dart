import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/cache.dart';
import 'package:fyrlys/core/models.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/core/tidy.dart';
import 'package:fyrlys/theme.dart';
import 'package:fyrlys/ui/channel_card.dart';
import 'package:fyrlys/ui/country_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Slik noen leverandører skriver lista: land foran kategoriene, et merke og kvaliteten i kanalnavnene, og NRK1 i
/// både 1080p og 720p.
const _categories = [
  Category(id: 'no720', name: 'NO: [720p] AND [H265]'),
  Category(id: 'no1080', name: 'NO:   [1080p]'),
  Category(id: 'noppv', name: 'NO: VIAPLAY [PPV EVENTS] [EXTRA] [1080p]'),
  Category(id: 'se', name: 'SE: SPORT [1080p]'),
];

const _channels = [
  Channel(id: '1', name: 'NRK1', categoryId: 'no720', number: '1'),
  Channel(id: '2', name: 'NOR: TV 2 [720p]', categoryId: 'no720', number: '2'),
  Channel(id: '3', name: 'NOR: TV 2 [H265]', categoryId: 'no720', number: '3'),
  Channel(id: '4', name: 'VIP: AKVARIUM [1080p]', categoryId: 'no1080', number: '4'),
  Channel(id: '5', name: 'VIP: NRK1 [1080p]', categoryId: 'no1080', number: '5'),
  Channel(id: '6', name: 'VIP: NRK1 ØSTLANDET [1080p]', categoryId: 'no1080', number: '6'),
  Channel(id: '7', name: 'NOR: VIAPLAY EVENT 1 [1080p]', categoryId: 'noppv', number: '7'),
  Channel(id: '8', name: 'SWE: TV 4 [1080p]', categoryId: 'se', number: '8'),
  Channel(id: '9', name: 'SWE: SPORT ULTRA [4K-Q]+', categoryId: 'se', number: '9'),
];

Future<Session> _session({Map<String, Object> prefs = const {}, ListCache? cache}) async {
  SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}', ...prefs});
  final s = Session(
    await SharedPreferences.getInstance(),
    sourceFactory: (_) async => FakeSource(list: _channels, categoryList: _categories),
    listCache: cache,
  );
  await s.restore();
  await s.load();
  return s;
}

void main() {
  test('kanalnavnene uten merket foran og kvaliteten i klammer', () {
    expect(tidyChannelName('NOR: TV 2 [720p]'), (name: 'TV 2', quality: '720p'));
    expect(tidyChannelName('NOR: TV 2 [H265]'), (name: 'TV 2', quality: 'H265'));
    expect(tidyChannelName('VIP: NRK1 ØSTLANDET [1080p]'), (name: 'NRK1 ØSTLANDET', quality: null));
    expect(tidyChannelName('NOR: TV 2 DIREKTE  [1080p]'), (name: 'TV 2 DIREKTE', quality: null));
    expect(tidyChannelName('NOR: SPORT ULTRA [4K-Q]+'), (name: 'SPORT ULTRA', quality: '4K'));
    expect(tidyChannelName('SWE: TV 4 [480p]'), (name: 'TV 4', quality: '480p'));
    expect(tidyChannelName('UK | BBC One [HD]'), (name: 'BBC One', quality: 'HD'));
    expect(tidyChannelName('|NO| TV Norge (1080p)'), (name: 'TV Norge', quality: null));
    expect(tidyChannelName('[NO] NRK1'), (name: 'NRK1', quality: null));
    // eventer beholder «LIVE:», og navn uten slike merker står som de er
    expect(tidyChannelName('LIVE: Kamp i dag [1080p]').name, 'LIVE: Kamp i dag');
    for (final name in ['NRK 1 HD', '15:00 Man United - Bournemouth | Premier League', '-= Sweden =-', 'TV 2 HD NO']) {
      expect(tidyChannelName(name), (name: name, quality: null), reason: name);
    }
    // ingenting igjen: navnet som det var
    expect(tidyChannelName('NOR: [720p]').name, 'NOR: [720p]');
  });

  test('kategorinavnene uten landet og den vanlige kvaliteten', () {
    expect(tidyCategoryName('NO: VIAPLAY [PPV EVENTS] [EXTRA] [1080p]'), 'VIAPLAY · PPV EVENTS · EXTRA');
    expect(tidyCategoryName('NO: SPORT [720p] AND [H265]'), 'SPORT · 720p · H265');
    expect(tidyCategoryName('NO: [720p] AND [H265]'), 'Norge · 720p · H265');
    expect(tidyCategoryName('NO:   [1080p]'), 'Norge');
    expect(tidyCategoryName('NO: [PLUS] PLAY [1080p]'), 'PLUS PLAY');
    expect(tidyCategoryName('NO: TV2 PLAY  [1080p]'), 'TV2 PLAY');
    // flere land: koden står igjen, så to like kategorier kan skilles
    expect(tidyCategoryName('SE: SPORT [720p]', keepCountry: true), 'SE · SPORT · 720p');
    expect(tidyCategoryName('USA: NEWS [1080p]', keepCountry: true), 'US · NEWS');
    expect(tidyCategoryName('SE: [1080p]', keepCountry: true), 'Sverige');
    for (final name in ['Viaplay Sport SE [B]', 'Sweden - Sport', 'Norge', 'Sport']) {
      expect(tidyCategoryName(name), name, reason: name);
    }
  });

  test('landet i kategorinavnet, slik leverandørene skriver det', () {
    final expected = {
      'NO: Sport': 'NO',
      'NOR: Sport': 'NO',
      'USA: News': 'US',
      '|SE| Film': 'SE',
      '[DK] Nyheter': 'DK',
      'UK | Sports': 'UK',
      'Norway - Sport': 'NO',
      'Netherland - Algemeen': 'NL',
      'Sweden': 'SE',
      'Norge': 'NO',
      'Viaplay Sport SE': 'SE',
      'HBO Max Sports DK [B]': 'DK',
      'ARA: Nyheter': 'ARA',
    };
    expected.forEach((name, code) => expect(countryOf(name), code, reason: name));
    for (final name in ['World Padel Tour TV', 'FIFA+ Events', 'Sport', '24/7 Movies']) {
      expect(countryOf(name), isNull, reason: name);
    }
    expect(countryLabel('NO'), 'Norge');
    expect(countryLabel('ARA'), 'Arabisk');
    expect(countryLabel('AS'), 'AS');
    expect(countryLabel(''), 'Uten land');
  });

  test('landene i lista, med antall, alfabetisk og «Uten land» sist', () {
    final groups = countryGroups(
      [..._categories, const Category(id: 'x', name: 'Sport')],
      [..._channels, const Channel(id: '10', name: 'Kanal', categoryId: 'x')],
    );
    expect(groups.map((g) => g.code), ['NO', 'SE', '']);
    expect(groups.first.categories, 3);
    expect(groups.first.channels, 7);
    expect(groups[1].channels, 2);
    expect(groups.first.example, 'NO: [720p] AND [H265]');
  });

  test('lista: ryddige navn, NRK samlet i 1080p-kategorien, og bare landene du velger', () async {
    final cache = MemoryListCache();
    final s = await _session(cache: cache);

    // to land: koden står foran kategoriene (unntatt der landet er navnet)
    expect(s.categories.map((c) => c.name), ['Norge · 720p · H265', 'Norge', 'NO · VIAPLAY · PPV EVENTS · EXTRA', 'SE · SPORT']);
    final tv2 = s.channels.where((c) => c.name == 'TV 2').toList();
    expect(tv2.map((c) => c.quality), ['720p', 'H265']);
    expect(s.channels.map((c) => c.name), containsAll(['AKVARIUM', 'NRK1 ØSTLANDET', 'TV 4', 'SPORT ULTRA']));
    // NRK1 er én kanal, i kategorien til den beste varianten (1080p), med den variantens id
    final nrk1 = s.channels.where((c) => c.name == 'NRK1').single;
    expect(nrk1.categoryId, 'no1080');
    expect(nrk1.id, '5');
    // lista på disk er slik leverandøren sendte den
    expect(cache.lists.values.single.channels.map((c) => c.name), contains('NOR: TV 2 [720p]'));

    // landene i hele lista
    expect(s.countryGroupsInList.map((g) => (g.code, g.channels)), [('NO', 7), ('SE', 2)]);

    // bare Norge: Sverige er borte, og koden foran kategoriene trengs ikke
    await s.setShownCountries({'NO'});
    expect(s.shownCountries, {'NO'});
    expect(s.categories.map((c) => c.name), ['Norge · 720p · H265', 'Norge', 'VIAPLAY · PPV EVENTS · EXTRA']);
    expect(s.channels.map((c) => c.name), isNot(contains('TV 4')));
    expect(s.categoryCounts['se'], isNull);
    // valget av land står i lista over land, også for det som er skjult
    expect(s.countryGroupsInList.map((g) => g.code), ['NO', 'SE']);

    // huskes til neste gang (per innlogging)
    final again = Session(
      await SharedPreferences.getInstance(),
      sourceFactory: (_) async => FakeSource(list: _channels, categoryList: _categories),
    );
    await again.restore();
    await again.load();
    expect(again.shownCountries, {'NO'});
    expect(again.channels.map((c) => c.name), isNot(contains('TV 4')));

    // navnene som leverandøren skrev dem
    await s.setTidyNames(false);
    expect(s.channels.map((c) => c.name), contains('NOR: TV 2 [720p]'));
    expect(s.categories.map((c) => c.name), contains('NO:   [1080p]'));
    expect(s.channels.where((c) => c.name == 'NRK1'), hasLength(1));

    // alle land igjen
    await s.setTidyNames(true);
    await s.setShownCountries(null);
    expect(s.shownCountries, isNull);
    expect(s.channels.map((c) => c.name), contains('TV 4'));
  });

  test('land som ikke finnes i lista lenger: heller alt enn ingenting', () async {
    final s = await _session(prefs: {'countries@${Session.loginId(const {'kind': 'fake'})}': <String>['FI']});
    expect(s.channels, isNotEmpty);
    expect(s.categories, hasLength(4));
  });

  testWidgets('valget av land: kryss av, bruk, og alle igjen', (tester) async {
    final s = await _session();
    await tester.pumpWidget(MaterialApp(
      theme: fyrlysTheme(Brightness.dark),
      home: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () => showCountryDialog(context, s),
            child: const Text('Velg'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Velg'));
    await tester.pumpAndSettle();
    expect(find.text('Norge (NO)'), findsOneWidget);
    expect(find.text('Sverige (SE)'), findsOneWidget);
    // alle er krysset av når ingen er valgt
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('land:SE'))).value, isTrue);

    await tester.tap(find.byKey(const ValueKey('land:SE')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('land-bruk')));
    await tester.pumpAndSettle();
    expect(s.shownCountries, {'NO'});
    expect(countriesSummary(s.shownCountries), 'Norge');

    // «Ingen» kan ikke brukes; «Alle» gir alle land (også de som kommer til senere)
    await tester.tap(find.text('Velg'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('land-ingen')));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('land-bruk'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('land-alle')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('land-bruk')));
    await tester.pumpAndSettle();
    expect(s.shownCountries, isNull);
    expect(countriesSummary(null), 'Alle land');
  });

  testWidgets('kvaliteten står som et merke etter navnet på kortet', (tester) async {
    final s = await _session();
    final tv2 = s.channels.firstWhere((c) => c.quality == '720p');
    await tester.pumpWidget(MaterialApp(
      theme: fyrlysTheme(Brightness.dark),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 380, height: 84, child: ChannelCard(session: s, channel: tv2, onTap: () {})),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('kvalitet:720p')), findsOneWidget);
    expect(find.textContaining('TV 2'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 300));
  });
}
