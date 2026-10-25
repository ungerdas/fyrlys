import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/app.dart';
import 'package:fyrlys/core/models.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/core/source.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// En kilde uten nett, med tre kanaler i to kategorier.
class FakeSource implements TvSource {
  @override
  String get kind => 'fake';

  @override
  String get label => 'Test';

  @override
  Map<String, String> get httpHeaders => const {};

  @override
  bool get sharedFavorites => false;

  @override
  Future<void> prepare() async {}

  @override
  Future<Account> account() async => const Account();

  @override
  Future<List<Category>> categories({bool force = false}) async =>
      const [Category(id: '1', name: 'Norge'), Category(id: '2', name: 'Sport')];

  @override
  Future<List<Channel>> channels({bool force = false}) async => const [
        Channel(id: '101', name: 'NRK 1 HD', categoryId: '1', number: '1'),
        Channel(id: '102', name: 'TV 2 HD', categoryId: '1', number: '2'),
        Channel(id: '103', name: '15:00 Man United - Bournemouth | Premier League', categoryId: '2', hasEpg: false),
      ];

  @override
  Future<List<EpgEntry>> epg(String channelId) async => const [];

  @override
  String? logoUrl(String? icon) => null;

  @override
  Future<PlayTarget> open(Channel channel, {bool takeOver = false}) async => const PlayTarget(['http://example/1.ts']);

  @override
  Future<void> close(Channel channel) async {}

  @override
  Future<Favorites?> loadFavorites() async => null;

  @override
  Future<Favorites?> changeFavorites(Map<String, Object?> change) async => null;

  @override
  Map<String, String> toPrefs() => const {'kind': 'fake'};

  @override
  void dispose() {}
}

void main() {
  testWidgets('innloggingen har begge måtene å koble til på', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final session = Session(await SharedPreferences.getInstance());
    await session.restore();
    await tester.pumpWidget(FyrlysApp(session: session));
    await tester.pump();

    expect(find.text('Fyrlys-server'), findsOneWidget);
    expect(find.text('Adresse'), findsOneWidget);
    await tester.tap(find.text('IPTV-leverandør'));
    await tester.pump();
    expect(find.text('Brukernavn'), findsOneWidget);
    expect(find.text('Passord'), findsOneWidget);
  });

  testWidgets('TV-siden: kanaler, eventkanaler, favoritter og søk', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
    final session = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => FakeSource());
    await session.restore();
    await tester.pumpWidget(FyrlysApp(session: session));
    await tester.pumpAndSettle();

    expect(find.text('NRK 1 HD'), findsOneWidget);
    expect(find.text('TV 2 HD'), findsOneWidget);
    // eventkanalen: klokkeslett og kamp på første linje, liga under
    expect(find.text('15:00  Man United - Bournemouth'), findsOneWidget);
    expect(find.text('Premier League'), findsOneWidget);

    await tester.tap(find.byTooltip('Legg til i favoritter').first);
    await tester.pump();
    expect(session.favorites.map((c) => c.id), ['101']);

    await tester.tap(find.text('★ Favoritter'));
    await tester.pump();
    expect(find.text('NRK 1 HD'), findsOneWidget);
    expect(find.text('TV 2 HD'), findsNothing);

    await tester.tap(find.text('Alle kanaler').first);
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'tv 2');
    await tester.pump();
    expect(find.text('TV 2 HD'), findsOneWidget);
    expect(find.text('NRK 1 HD'), findsNothing);
  });
}
