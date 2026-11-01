import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/public_streams.dart';

void main() {
  test('NRK-kanalene kjennes igjen, med land og kvalitet rundt navnet', () {
    for (final name in [
      'NRK1',
      'NRK 1',
      'NRK1 HD',
      'NRK 1 FHD',
      'NO: NRK 1 HD',
      'NO | NRK1',
      '|NO| NRK 1 HD',
      '[NO] NRK1 (1080i)',
      'NOR - NRK1 HEVC',
      'NRK1HD',
      'nrk1 hd+',
    ]) {
      expect(publicStreamKey(name), 'nrk1', reason: name);
    }
    expect(publicStreamKey('NRK 2 HD'), 'nrk2');
    expect(publicStreamKey('NO: NRK3 FHD'), 'nrk3');
    expect(publicStreamKey('NRK Super HD'), 'nrksuper');
    expect(publicStreamKey('NRK SUPER (1080i)'), 'nrksuper');
  });

  test('regionale NRK1 og andre kanaler beholder leverandørens strøm', () {
    for (final name in [
      'NRK1 Rogaland',
      'NRK 1 (Agder)',
      'NRK1 Midtnytt HD',
      'NRK Tegnspråk',
      'NRK3/NRK Super',
      'NRK1 +1',
      'TV 2 HD',
      'Norway: TV Norge',
      'NRK 12',
    ]) {
      expect(publicStreamKey(name), isNull, reason: name);
    }
  });

  test('adressene til NRK, og hvilke som er det', () {
    final nrk1 = publicStreamFor('NRK 1 HD')!;
    expect(nrk1, endsWith('/nrk1/muxed.m3u8'));
    expect(nrk1, startsWith('https://'));
    expect(isPublicStream(nrk1), isTrue);
    expect(publicStreamFor('NRK Super'), endsWith('/nrksuper/muxed.m3u8'));
    expect(publicStreamFor('TV 2'), isNull);
    expect(isPublicStream('http://iptv.example/live/u/p/101.m3u8'), isFalse);
  });
}
