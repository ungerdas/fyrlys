import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/models.dart';
import 'package:fyrlys/core/public_streams.dart';
import 'package:fyrlys/core/session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Slik en leverandør har dem: land bak, HD og FHD, og NRK3 og NRK Super som én kanal.
const _provider = [
  Channel(id: '2071', name: '-= Norway =-', categoryId: '7', number: '2071', hasEpg: false),
  Channel(id: '2073', name: 'NRK 1 HD NO', categoryId: '7', number: '2073', icon: 'http://logo/nrk1.png'),
  Channel(id: '2074', name: 'NRK 1 FHD NO', categoryId: '7', number: '2074', icon: 'http://logo/nrk1.png', archiveDays: 7),
  Channel(id: '2075', name: 'NRK 2 HD NO', categoryId: '7', number: '2075'),
  Channel(id: '2076', name: 'NRK 2 FHD NO', categoryId: '7', number: '2076'),
  Channel(id: '2077', name: 'NRK 2 Lydtekst HD NO', categoryId: '7', number: '2077'),
  Channel(id: '2078', name: 'NRK 3/SUPER NO', categoryId: '7', number: '2078'),
  Channel(id: '2079', name: 'NRK 3/SUPER HD NO', categoryId: '7', number: '2079'),
  Channel(id: '2080', name: 'NRK 3/SUPER FHD NO', categoryId: '7', number: '2080'),
  Channel(id: '2081', name: 'NRK Rogaland 24 NO', categoryId: '7', number: '2081'),
  Channel(id: '2082', name: 'TV2 HD NO', categoryId: '7', number: '2082'),
];

void main() {
  test('NRK-kanalene kjennes igjen, med land og kvalitet foran eller bak navnet', () {
    for (final name in [
      'NRK1',
      'NRK 1',
      'NRK1 HD',
      'NRK 1 FHD',
      'NRK 1 HD NO',
      'NRK 1 FHD NO',
      'NO: NRK 1 HD',
      'NO | NRK1',
      '|NO| NRK 1 HD',
      '[NO] NRK1 (1080i)',
      'NOR - NRK1 HEVC',
      'NRK1HD',
      'nrk1 hd+',
    ]) {
      expect(publicStreamKeys(name), ['nrk1'], reason: name);
    }
    expect(publicStreamKey('NRK 2 FHD NO'), 'nrk2');
    expect(publicStreamKey('NO: NRK3 FHD'), 'nrk3');
    expect(publicStreamKey('NRK Super HD'), 'nrksuper');
    expect(publicStreamKey('NRK SUPER (1080i)'), 'nrksuper');
    // NRK3 og NRK Super som én kanal hos leverandøren
    for (final name in ['NRK 3/SUPER NO', 'NRK 3/SUPER FHD NO', 'NRK3/NRK Super']) {
      expect(publicStreamKeys(name), ['nrk3', 'nrksuper'], reason: name);
      expect(publicStreamKey(name), isNull, reason: name);
    }
  });

  test('regionale NRK1, lydtekst og andre kanaler beholder leverandørens strøm', () {
    for (final name in [
      'NRK1 Rogaland',
      'NRK 1 (Agder)',
      'NRK1 Midtnytt HD',
      'NRK Rogaland 24 NO',
      'NRK 2 Lydtekst HD NO',
      'NRK Tegnspråk',
      'NRK1 +1',
      'TV 2 HD',
      'TV2 HD NO',
      'Norway: TV Norge',
      '-= Norway =-',
      'NRK 12',
    ]) {
      expect(publicStreamKeys(name), isEmpty, reason: name);
    }
  });

  test('adressene til NRK, og hvilke som er det', () {
    final nrk1 = publicStreamFor('NRK 1 HD NO')!;
    expect(nrk1, endsWith('/nrk1/muxed.m3u8'));
    expect(nrk1, startsWith('https://'));
    expect(isPublicStream(nrk1), isTrue);
    expect(publicStreamFor('NRK Super'), endsWith('/nrksuper/muxed.m3u8'));
    expect(publicStreamFor('TV 2'), isNull);
    expect(isPublicStream('http://iptv.example/live/u/p/101.m3u8'), isFalse);
    expect(providerChannelId('2078~nrksuper'), '2078');
    expect(providerChannelId('2078'), '2078');
  });

  test('variantene blir én kanal hver, der den første sto, med den beste variantens id, logo og arkiv', () {
    final merged = mergePublicChannels(_provider);
    expect(merged.map((c) => c.name), [
      '-= Norway =-',
      'NRK1',
      'NRK2',
      'NRK 2 Lydtekst HD NO',
      'NRK3',
      'NRK Super',
      'NRK Rogaland 24 NO',
      'TV2 HD NO',
    ]);
    final byName = {for (final c in merged) c.name: c};
    // FHD er best; nummeret er det første av variantene
    expect(byName['NRK1']!.id, '2074');
    expect(byName['NRK1']!.number, '2073');
    expect(byName['NRK1']!.icon, 'http://logo/nrk1.png');
    expect(byName['NRK1']!.archiveDays, 7);
    expect(byName['NRK2']!.id, '2076');
    // NRK3 og NRK Super deler variantene av «NRK 3/SUPER», med hver sin id
    expect(byName['NRK3']!.id, '2080');
    expect(byName['NRK Super']!.id, '2079');
    expect(merged.map((c) => c.id).toSet(), hasLength(merged.length));
    // samme svar når lista slås sammen på nytt (lista fra sist er alt sammenslått)
    expect(mergePublicChannels(merged).map((c) => '${c.id} ${c.name}'), merged.map((c) => '${c.id} ${c.name}'));
  });

  test('bare én «NRK 3/SUPER»: NRK Super får en egen id som peker på den', () {
    final merged = mergePublicChannels(const [Channel(id: '9', name: 'NRK 3/SUPER NO')]);
    expect(merged.map((c) => '${c.id} ${c.name}'), ['9 NRK3', '9~nrksuper NRK Super']);
    expect(providerChannelId(merged.last.id), '9');
  });

  test('én variant står som den er', () {
    const one = [Channel(id: '101', name: 'NRK 1 HD'), Channel(id: '102', name: 'TV 2 HD')];
    expect(mergePublicChannels(one).map((c) => '${c.id} ${c.name}'), ['101 NRK 1 HD', '102 TV 2 HD']);
  });

  test('favoritter og «sist sett» på en variant blir den samlede kanalen, én gang', () async {
    // favorittene fra før sammenslåingen: begge NRK1-variantene og den delte NRK3/Super (flyttes inn ved oppstart)
    SharedPreferences.setMockInitialValues({
      'source': '{"kind":"fake"}',
      'favorites': jsonEncode([for (final i in [1, 2, 6]) _provider[i].toJson()]),
    });
    final session =
        Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => FakeSource(list: _provider));
    await session.restore();
    await session.load();
    expect(session.channels.map((c) => c.name), contains('NRK Super'));
    expect(session.favorites.map((c) => c.name), ['NRK1', 'NRK3']);
    expect(session.favorites.first.id, '2074');
  });
}
