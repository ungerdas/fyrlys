import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/plex/plex_account.dart';
import 'package:fyrlys/core/plex/plex_api.dart';
import 'package:fyrlys/core/plex/plex_models.dart';
import 'package:fyrlys/core/secrets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plex_fake.dart';

Future<(PlexAccount, FakePlex, SharedPreferences)> _account([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final fake = FakePlex();
  return (PlexAccount(p, const NoSecretCodec(), client: fake.client), fake, p);
}

/// venter til det som er sendt i bakgrunnen (beskjedene til Plex), er ferdig
Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('serverne', () {
    test('fra plex.tv: bare servere, uten IPv6, egne først', () {
      final servers = sortServers([
        for (final j in [
          FakePlex.serverJson(id: 'venn', name: 'Vennens', owned: false),
          FakePlex.serverJson(),
          {'name': 'Telefonen', 'provides': 'client,player', 'clientIdentifier': 'tlf', 'accessToken': 'x'},
        ])
          if (PlexServer.fromJson(j) case final s?) s,
      ]);
      expect([for (final s in servers) s.id], ['srv1', 'venn']);
      final s = servers.first;
      expect(s.owned, isTrue);
      expect(s.token, FakePlex.serverToken);
      expect([for (final c in s.connections) c.tier], [0, 1, 2]);
      expect(s.connections.first.lanHttp?.uri, FakePlex.lanHttp);
      // over nettet og via Plex: aldri ukryptert
      expect(s.connections[1].lanHttp, isNull);
      expect(s.connections[2].lanHttp, isNull);
      // lagret og lest igjen
      final again = PlexServer.fromSaved(jsonDecode(jsonEncode(s.toJson())));
      expect(again?.connections.length, 3);
      expect(again?.token, FakePlex.serverToken);
    });

    test('adressen: hjemmenettet med https først, så http der, så over nettet', () async {
      final fake = FakePlex();
      const info = PlexClientInfo(id: 'test');
      final server = PlexServer.fromJson(FakePlex.serverJson())!;
      expect((await pickConnection(server, fake.client, info))?.uri, FakePlex.local);

      // ruteren stopper …plex.direct-navnet i hjemmenettet
      fake.localWorks = false;
      expect((await pickConnection(server, fake.client, info))?.uri, FakePlex.lanHttp);

      // borte fra hjemmenettet
      fake.lanHttpWorks = false;
      final remote = await pickConnection(server, fake.client, info);
      expect(remote?.uri, FakePlex.remote);
      expect(remote?.tier, 1);

      fake.remoteWorks = false;
      expect(await pickConnection(server, fake.client, info), isNull);
    });

    test('en annen server på samme adresse godtas ikke', () async {
      final fake = FakePlex();
      final other = PlexServer.fromJson(FakePlex.serverJson(id: 'annen'))!;
      expect(await probeServer(FakePlex.local, other, fake.client, const PlexClientInfo(id: 'test')), isFalse);
    });
  });

  group('det som ligger på serveren', () {
    test('en film: bildet, lyden, merkene og hvor du slapp', () {
      final m = PlexItem.fromJson(FakePlex.movie);
      expect(m.type, PlexType.movie);
      expect(m.title, 'Fyrlyset');
      expect(m.year, 2024);
      expect(m.rating, 7.5);
      expect(m.genres, ['Drama']);
      expect(m.cast, ['Kari Nordmann']);
      expect(m.directors, ['Ola Regissør']);
      expect(m.duration, const Duration(minutes: 100));
      expect(m.part?.key, '/library/parts/100/1700000000/file.mkv');
      expect(m.tech.badges, containsAll(['4K', 'H.265', '5.1', 'Dolby Digital+']));
      expect(m.watched, isFalse);
      expect(m.resumeAt, isNull);

      final n = PlexItem.fromJson(FakePlex.started);
      expect(n.resumeAt, const Duration(minutes: 10));
      expect(n.progress, closeTo(10 / 90, 0.001));
    });

    test('en episode: koden, serien og plakaten til serien', () {
      // episoden du skal se nå: ett objekt fra serveren
      final show = PlexItem.fromJson({...FakePlex.show, 'OnDeck': {'Metadata': FakePlex.season1[1]}});
      expect(show.onDeck?.ratingKey, '32');
      final e = PlexItem.fromJson(FakePlex.season1[1]);
      expect(e.code, 'S01E02');
      expect(e.cardTitle, 'Kysten');
      expect(e.cardLine, 'S01E02 · Etter stormen');
      expect(e.poster, '/library/metadata/20/thumb/1');
      expect(e.resumeAt, const Duration(minutes: 5));
      final seen = PlexItem.fromJson(FakePlex.season1[0]);
      expect(seen.watched, isTrue);
      expect(seen.resumeAt, isNull);
    });

    test('en serie: sett av episodene og hva som er igjen', () {
      final s = PlexItem.fromJson(FakePlex.show);
      expect(s.watched, isFalse);
      expect(s.unwatched, 3);
      expect(s.cardLine, '2 sesonger');
    });

    test('tall, tekst og sant/usant kommer i alle former', () {
      expect(plexInt('12'), 12);
      expect(plexInt(12.6), 13);
      expect(plexInt('NaN'), isNull);
      expect(plexBool('1'), isTrue);
      expect(plexBool(0), isFalse);
      expect(plexDouble('7.5'), 7.5);
      expect(plexText(null), '');
      expect(plexPath('  '), isNull);
    });

    test('resumeFrom: ikke helt i starten og ikke nesten ferdig', () {
      const length = Duration(minutes: 40);
      expect(resumeFrom(const Duration(seconds: 5), length), isNull);
      expect(resumeFrom(const Duration(minutes: 10), length), const Duration(minutes: 10));
      expect(resumeFrom(const Duration(minutes: 39), length), isNull);
    });
  });

  group('API-et', () {
    test('bibliotek, sider, sortering, sjanger og bilder', () async {
      final fake = FakePlex();
      final api = PlexServerApi(
        base: FakePlex.local,
        token: FakePlex.serverToken,
        info: const PlexClientInfo(id: 'test'),
        client: fake.client,
      );
      final libs = await api.libraries();
      expect([for (final l in libs) l.title], ['Mine filmer', 'Mine serier']);

      final page = await api.items(libs[0], sort: PlexSort.alpha, genre: '5', start: 0, size: 50);
      expect([for (final i in page.items) i.title], ['Fyrlyset']);
      var q = fake.calls('/library/sections/1/all').last;
      expect(q['type'], '1');
      expect(q['sort'], 'titleSort');
      expect(q['genre'], '5');
      expect(q['X-Plex-Container-Size'], '50');

      await api.recentlyAdded(libs[1]);
      q = fake.calls('/library/sections/2/all').last;
      expect(q['type'], '2');
      // serier: der det sist kom en episode
      expect(q['sort'], 'episode.addedAt:desc');

      final image = api.image('/library/metadata/10/thumb/1', width: 300, height: 450)!;
      expect(image, startsWith('${FakePlex.local}/photo/:/transcode?'));
      expect(Uri.parse(image).queryParameters['url'], '/library/metadata/10/thumb/1');
      expect(Uri.parse(image).queryParameters['X-Plex-Token'], FakePlex.serverToken);
      // filen: innloggingen går som hode, ikke i adressen
      expect(api.file(PlexItem.fromJson(FakePlex.movie).part!), '${FakePlex.local}/library/parts/100/1700000000/file.mkv');
      expect(api.headers['X-Plex-Token'], FakePlex.serverToken);
      expect(api.headers['X-Plex-Product'], 'Fyrlys');
    });

    test('fortsett å se, også på en eldre server', () async {
      final fake = FakePlex();
      final api = PlexServerApi(
        base: FakePlex.local,
        token: FakePlex.serverToken,
        info: const PlexClientInfo(id: 'test'),
        client: fake.client,
      );
      expect([for (final i in await api.continueWatching()) i.ratingKey], ['11', '32']);
      fake.oldServer = true;
      expect([for (final i in await api.continueWatching()) i.ratingKey], ['32']);
    });

    test('radene på Hjem: rekkefølgen fra Plex, bare filmer og serier fra bibliotekene som vises', () async {
      final fake = FakePlex();
      final api = PlexServerApi(
        base: FakePlex.local,
        token: FakePlex.serverToken,
        info: const PlexClientInfo(id: 'test'),
        client: fake.client,
      );
      expect(api.headers['X-Plex-Language'], 'nb');
      final libs = await api.libraries();
      var hubs = await api.homeHubs(libs);
      // uten «Fortsett å se» (egen rad) og musikk
      expect([for (final h in hubs) h.title], ['Nytt fra Kystkanalen', 'Nylig lagt til i Mine filmer', 'Nylig lagt til i Mine serier']);
      expect([for (final i in hubs.first.items) i.ratingKey], ['34', '33']);
      expect(hubs.first.canShowAll, isTrue);
      expect(hubs[1].canShowAll, isFalse);
      final q = fake.calls('/hubs/promoted').last;
      expect(q['contentDirectoryID'], '1,2');
      expect(q['count'], '20');

      // bare filmene: det fra serie-biblioteket tas bort, også når serveren sender det
      hubs = await api.homeHubs([libs.first]);
      expect([for (final h in hubs) h.title], ['Nylig lagt til i Mine filmer']);
      expect(fake.calls('/hubs/promoted').last['contentDirectoryID'], '1');
      expect(await api.homeHubs(const []), isEmpty);

      // hele raden, en side om gangen
      final page = await api.hubItems('/library/collections/77/children', sections: {'1', '2'}, start: 2, size: 2);
      expect([for (final i in page.items) i.ratingKey], ['31', '32']);
      expect(page.fetched, 2);
      expect(page.total, 4);
      expect(fake.calls('/library/collections/77/children').last['X-Plex-Container-Start'], '2');
      final hidden = await api.hubItems('/library/collections/77/children', sections: {'1'});
      expect(hidden.items, isEmpty);
      expect(hidden.fetched, 4);
    });

    test('søket gir bare filmer, serier og episoder', () async {
      final fake = FakePlex();
      final api = PlexServerApi(
        base: FakePlex.local,
        token: FakePlex.serverToken,
        info: const PlexClientInfo(id: 'test'),
        client: fake.client,
      );
      final hits = await api.search('nord', section: '1');
      expect([for (final i in hits) i.title], ['Nordlys']);
      expect(fake.calls('/hubs/search').last['sectionId'], '1');
    });

    test('feil fra serveren blir en forklaring', () async {
      final fake = FakePlex();
      final api = PlexServerApi(
        base: FakePlex.local,
        token: 'feil',
        info: const PlexClientInfo(id: 'test'),
        client: fake.client,
      );
      await expectLater(api.libraries(), throwsA(isA<PlexException>().having((e) => e.status, 'status', 401)));
      fake.localWorks = false;
      await expectLater(api.libraries(), throwsA(isA<PlexException>().having((e) => e.network, 'network', isTrue)));
    });
  });

  group('kontoen', () {
    test('innlogging med PIN: serveren velges, lagres og kobles til', () async {
      final (plex, fake, prefs) = await _account();
      fake.approveAt = 2;
      final pin = await plex.startLogin();
      final url = plex.authUrl(pin);
      expect(url, startsWith('https://app.plex.tv/auth#?clientID='));
      expect(url, contains('code=abcd1234'));
      expect(await plex.finishLogin(pin), isFalse);
      expect(await plex.finishLogin(pin), isTrue);
      expect(plex.linked, isTrue);
      expect(plex.user, 'kari');
      // egen server foran den som er delt
      expect(plex.server?.id, 'srv1');
      expect(prefs.getString('plex_plain'), contains(FakePlex.accountToken));
      // samme id hver gang
      final id = prefs.getString('plex_client_id');
      expect(id, isNotNull);
      expect(fake.requests.first.headers['X-Plex-Client-Identifier'], id);

      final api = await plex.connect();
      expect(api.base, FakePlex.local);
      expect([for (final l in plex.libraries) l.title], ['Mine filmer', 'Mine serier']);
      expect(plex.status, PlexStatus.ready);

      // neste gang appen starter: innloggingen og adressen er der
      final again = PlexAccount(prefs, const NoSecretCodec(), client: fake.client);
      expect(again.linked, isTrue);
      expect(again.user, 'kari');
      expect((await again.connect()).base, FakePlex.local);
      expect(again.reportLine, contains('egen server'));
      expect(again.reportLine, isNot(contains('Hjemme')));

      await again.logout();
      expect(again.linked, isFalse);
      expect(prefs.getString('plex_plain'), isNull);
    });

    test('skjulte biblioteker huskes per server', () async {
      final (plex, _, prefs) = await _account({'plex_plain': FakePlex.saved()});
      await plex.connect();
      expect([for (final l in plex.shownLibraries) l.title], ['Mine filmer', 'Mine serier']);
      plex.setHidden(plex.libraries[1], true);
      expect([for (final l in plex.shownLibraries) l.title], ['Mine filmer']);
      expect(plex.shownSections, {'1'});
      expect(plex.isHidden(plex.libraries[1]), isTrue);
      expect(prefs.getStringList('plex_hidden_libraries'), ['srv1/2']);
      plex.setHidden(plex.libraries[1], false);
      expect(plex.shownSections, {'1', '2'});
      expect(prefs.getStringList('plex_hidden_libraries'), isEmpty);
    });

    test('rekkefølgen på bibliotekene huskes per server, og nye biblioteker kommer sist', () async {
      final (plex, fake, prefs) = await _account({
        'plex_plain': FakePlex.saved(),
        // en annen server, og den rekkefølgen som var valgt her
        'plex_library_order': ['srv2/7', 'srv1/2'],
      });
      List<String> titles(List<PlexLibrary> libs) => [for (final l in libs) l.title];
      var changes = 0;
      plex.addListener(() => changes++);
      await plex.connect();
      // det som ikke står i rekkefølgen, kommer etter
      expect(titles(plex.libraries), ['Mine serier', 'Mine filmer']);

      plex.moveLibrary(plex.libraries[1], -1);
      expect(titles(plex.libraries), ['Mine filmer', 'Mine serier']);
      expect(prefs.getStringList('plex_library_order'), ['srv2/7', 'srv1/1', 'srv1/2']);
      final before = changes;
      // øverst kan ikke flyttes opp, nederst ikke ned
      plex.moveLibrary(plex.libraries.first, -1);
      plex.moveLibrary(plex.libraries.last, 1);
      expect(titles(plex.libraries), ['Mine filmer', 'Mine serier']);
      expect(changes, before);

      // et nytt bibliotek på serveren kommer sist
      fake.homeVideos = true;
      await plex.connect(force: true);
      expect(titles(plex.libraries), ['Mine filmer', 'Mine serier', 'Hjemmevideoer']);

      // et skjult bibliotek har også sin plass (i valget av biblioteker står alle)
      plex.setHidden(plex.libraries[1], true);
      plex.moveLibrary(plex.libraries[2], -1);
      expect(titles(plex.libraries), ['Mine filmer', 'Hjemmevideoer', 'Mine serier']);
      expect(titles(plex.shownLibraries), ['Mine filmer', 'Hjemmevideoer']);
      plex.moveLibrary(plex.libraries[2], -1);
      expect(titles(plex.libraries), ['Mine filmer', 'Mine serier', 'Hjemmevideoer']);
      expect(prefs.getStringList('plex_library_order'), ['srv2/7', 'srv1/1', 'srv1/2', 'srv1/4']);

      // neste gang appen starter
      final again = PlexAccount(prefs, const NoSecretCodec(), client: fake.client);
      await again.connect();
      expect(titles(again.libraries), ['Mine filmer', 'Mine serier', 'Hjemmevideoer']);
      expect(titles(again.shownLibraries), ['Mine filmer', 'Hjemmevideoer']);
    });

    test('adressen fra sist svarer ikke: de andre prøves, og plex.tv spørres når ingen svarer', () async {
      final (plex, fake, _) = await _account({'plex_plain': FakePlex.saved()});
      fake.localWorks = false;
      fake.lanHttpWorks = false;
      final api = await plex.connect();
      expect(api.base, FakePlex.remote);
      expect(api.tier, 1);

      fake.remoteWorks = false;
      await expectLater(plex.connect(force: true), throwsA(isA<PlexException>()));
      expect(plex.status, PlexStatus.failed);
      expect(plex.error, contains('Hjemme'));
      // plex.tv ble spurt om adressene på nytt
      expect(fake.requests.where((r) => r.url.host == 'clients.plex.tv'), isNotEmpty);
    });

    test('mister kontakten midt i: adressen finnes på nytt og det prøves én gang til', () async {
      final (plex, fake, _) = await _account({'plex_plain': FakePlex.saved()});
      await plex.connect();
      fake.localWorks = false;
      final libs = await plex.run((api) => api.libraries());
      expect(libs, hasLength(2));
      expect(plex.api?.base, FakePlex.lanHttp);
    });
  });

  group('Plex Home', () {
    test('brukerne, bytte med PIN-kode, og samme bruker neste gang', () async {
      final (plex, fake, prefs) = await _account({'plex_plain': FakePlex.saved()});
      fake.home = true;
      await plex.connect();
      expect(plex.hasHome, isFalse);
      final users = await plex.loadHomeUsers();
      expect([for (final u in users) u.title], ['Kari', 'Ola']);
      expect(plex.hasHome, isTrue);
      expect(users[1].protected, isTrue);
      expect(users[1].restricted, isTrue);
      // kontoen som koblet til
      expect(plex.currentHomeUser?.uuid, 'kari-uuid');

      // uten PIN-kode, og med feil
      await expectLater(plex.switchUser(users[1]), throwsA(isA<PlexException>().having((e) => e.pin, 'pin', isTrue)));
      await expectLater(
        plex.switchUser(users[1], pin: '0000'),
        throwsA(isA<PlexException>().having((e) => e.pin, 'pin', isTrue)),
      );
      expect(plex.user, 'kari');
      expect(plex.api, isNotNull);

      await plex.switchUser(users[1], pin: FakePlex.olaPin);
      expect(plex.user, 'Ola');
      expect(plex.currentHomeUser?.uuid, 'ola-uuid');
      expect(plex.server?.id, 'srv1');
      // byttet med kontoens innlogging, og serverne hentet med Olas
      final switched = fake.requests.lastWhere((r) => r.url.path == '/api/v2/home/users/ola-uuid/switch');
      expect(switched.headers['X-Plex-Token'], FakePlex.accountToken);
      expect(switched.url.queryParameters['pin'], FakePlex.olaPin);
      expect(fake.requests.last.url.path, '/api/v2/resources');
      expect(fake.requests.last.headers['X-Plex-Token'], FakePlex.olaToken);
      // på serveren med Olas innlogging der: det han har sett
      expect((await plex.connect()).token, FakePlex.olaServerToken);
      expect(await plex.run((api) => api.continueWatching()), isEmpty);
      expect(plex.reportLine, contains('Plex Home: 2 brukere'));
      expect(plex.reportLine, isNot(contains('Ola')));

      // neste gang appen starter: Ola, og brukerne hentes med kontoens innlogging
      final again = PlexAccount(prefs, const NoSecretCodec(), client: fake.client);
      expect(again.user, 'Ola');
      expect(again.currentHomeUser?.uuid, 'ola-uuid');
      expect((await again.connect()).token, FakePlex.olaServerToken);
      await again.ensureHomeUsers();
      expect(again.hasHome, isTrue);
      expect(fake.requests.lastWhere((r) => r.url.path == '/api/v2/home/users').headers['X-Plex-Token'],
          FakePlex.accountToken);

      // tilbake til Kari (uten PIN-kode)
      await again.switchUser(again.homeUsers.first);
      expect(again.user, 'Kari');
      expect((await again.connect()).token, FakePlex.serverToken);
      expect(await again.run((api) => api.continueWatching()), hasLength(2));

      // koblet fra: ingen Plex Home
      await again.logout();
      expect(again.homeUsers, isEmpty);
      expect(again.homeUser, isNull);
    });

    test('uten Plex Home: ingen å bytte til', () async {
      final (plex, _, _) = await _account({'plex_plain': FakePlex.saved()});
      await plex.connect();
      await plex.ensureHomeUsers();
      expect(plex.homeUsers, hasLength(1));
      expect(plex.hasHome, isFalse);
      expect(plex.currentHomeUser?.title, 'Kari');
    });
  });

  group('framdriften til Plex', () {
    test('Plex merker den som sett selv når den ser deg gå forbi 90 %', () async {
      final (plex, fake, _) = await _account({'plex_plain': FakePlex.saved()});
      await plex.connect();
      final report = PlexReporter(plex, '10');
      const length = Duration(minutes: 100);
      report.progress(const Duration(minutes: 50), length, playing: true);
      await _settle();
      report.progress(const Duration(minutes: 95), length, playing: true);
      await _settle();
      final calls = fake.calls('/:/timeline');
      expect([for (final c in calls) c['time']], ['3000000', '5700000']);
      expect(calls.first['state'], 'playing');
      expect(calls.first['ratingKey'], '10');
      expect(calls.first['duration'], '6000000');
      expect(fake.calls('/:/scrobble'), isEmpty);
    });

    test('begynte nesten ved slutten: merkes som sett her, én gang', () async {
      final (plex, fake, _) = await _account({'plex_plain': FakePlex.saved()});
      await plex.connect();
      final report = PlexReporter(plex, '10');
      const length = Duration(minutes: 100);
      report.progress(const Duration(minutes: 96), length, playing: true);
      await _settle();
      report.finished(length);
      await _settle();
      report.stopped(length, length);
      await _settle();
      expect(fake.calls('/:/scrobble'), hasLength(1));
      expect(fake.calls('/:/scrobble').single['key'], '10');
      // «stoppet» to ganger på samme sted sendes én gang
      expect([for (final c in fake.calls('/:/timeline')) c['state']], ['playing', 'stopped']);
    });
  });
}
