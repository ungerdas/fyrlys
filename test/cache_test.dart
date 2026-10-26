import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/cache.dart';
import 'package:fyrlys/core/models.dart';
import 'package:fyrlys/core/session.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const _nrk = Channel(id: '101', name: 'NRK 1 HD', categoryId: '1', number: '1', icon: 'http://logo/nrk.png');

/// Som FakeSource, men lista kommer først når testen sier fra.
class _SlowSource extends FakeSource {
  final gate = Completer<void>();

  @override
  Future<List<Channel>> channels({bool force = false}) async {
    await gate.future;
    return super.channels(force: force);
  }
}

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('fyrlys-test'));
  tearDown(() async => dir.delete(recursive: true));

  test('stabilt navn', () {
    expect(stableHash('http://logo/nrk.png'), stableHash('http://logo/nrk.png'));
    expect(stableHash('http://logo/nrk.png'), isNot(stableHash('http://logo/tv2.png')));
    expect(stableHash('a'), hasLength(16));
  });

  test('kanallista på disk: lagres og leses per kilde', () async {
    final cache = FileListCache(dir);
    expect(await cache.read('fyrlys|a'), isNull);
    await cache.write('fyrlys|a', const [Category(id: '1', name: 'Norge')], const [_nrk]);
    final back = await cache.read('fyrlys|a');
    expect(back!.categories.single.name, 'Norge');
    expect(back.channels.single.name, 'NRK 1 HD');
    expect(back.channels.single.number, '1');
    expect(back.channels.single.icon, 'http://logo/nrk.png');
    expect(await cache.read('fyrlys|b'), isNull);
    // en ødelagt fil gir ingen liste (den hentes på nytt)
    for (final f in dir.listSync().whereType<File>()) {
      f.writeAsStringSync('{ikke json');
    }
    expect(await cache.read('fyrlys|a'), isNull);
  });

  test('bildene: hentes én gang, så fra disken; feil gir det gamle bildet', () async {
    var calls = 0;
    var fail = false;
    final client = MockClient((req) async {
      calls++;
      if (fail) return http.Response('borte', 500);
      if (req.url.path == '/mangler.png') return http.Response('ikke funnet', 404, headers: {'content-type': 'text/html'});
      return http.Response.bytes(Uint8List.fromList([1, 2, 3]), 200, headers: {'content-type': 'image/png'});
    });
    final store = ImageStore(dir, client: client, maxAge: const Duration(days: 14));

    // to som vil ha samme bilde samtidig: én henting
    final both = await Future.wait([store.bytes('http://logo/nrk.png'), store.bytes('http://logo/nrk.png')]);
    expect(both.first, [1, 2, 3]);
    expect(calls, 1);
    expect(store.fileFor('http://logo/nrk.png').existsSync(), isTrue);

    // fra disken, uten nett
    final again = ImageStore(dir, client: client);
    expect(await again.bytes('http://logo/nrk.png'), [1, 2, 3]);
    expect(calls, 1);

    // gammelt bilde: hentes på nytt, men feiler nettet, brukes det gamle
    fail = true;
    final old = ImageStore(dir, client: client, maxAge: Duration.zero);
    expect(await old.bytes('http://logo/nrk.png'), [1, 2, 3]);
    expect(calls, 2);

    // et bilde som ikke finnes: feil, og det prøves ikke igjen med en gang
    fail = false;
    await expectLater(store.bytes('http://logo/mangler.png'), throwsA(isA<ImageStoreException>()));
    await expectLater(store.bytes('http://logo/mangler.png'), throwsA(isA<ImageStoreException>()));
    expect(calls, 3);
  });

  test('bildebufferet holdes under grensen: de eldste slettes', () async {
    final store = ImageStore(dir, maxBytes: 250);
    final now = DateTime.now();
    for (var i = 0; i < 4; i++) {
      final f = File('${dir.path}/bilde$i')..writeAsBytesSync(List.filled(100, i));
      f.setLastModifiedSync(now.subtract(Duration(days: 10 - i)));
    }
    await store.prune();
    final left = dir.listSync().map((e) => e.path.split(Platform.pathSeparator).last).toList()..sort();
    expect(left, ['bilde2', 'bilde3']);
  });

  test('appen viser lista fra sist med en gang, og lagrer den nye', () async {
    SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
    final cache = MemoryListCache();
    final first = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => FakeSource(), listCache: cache);
    await first.restore();
    await first.load();
    expect(cache.lists[Session.loginId(const {'kind': 'fake'})]!.channels, hasLength(3));

    // neste gang: lista fra sist er der før den nye er hentet
    final slow = _SlowSource();
    final second = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => slow, listCache: cache);
    await second.restore();
    await pumpEventQueue();
    expect(second.channels.map((c) => c.name), contains('NRK 1 HD'));
    expect(second.categories, hasLength(2));
    expect(second.loading, isTrue);
    slow.gate.complete();
    await pumpEventQueue();
    expect(second.loading, isFalse);
    expect(second.channels, hasLength(3));
  });

  test('programinfo for favorittene hentes med en gang lista er klar', () async {
    SharedPreferences.setMockInitialValues({
      'source': '{"kind":"fake"}',
      'favorites': '[{"id":"101","name":"NRK 1 HD","cat":"1","num":"1"}]',
    });
    final session = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => FakeSource());
    await session.restore();
    await pumpEventQueue();
    expect(session.epgCached('101')?.first.title, 'Dagsrevyen');
    // TV 2 er ikke favoritt og er ikke sett: hentes først når den vises
    expect(session.epgCached('102'), isNull);
  });
}
