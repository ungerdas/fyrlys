import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/failure.dart';
import 'package:fyrlys/ui/playback.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fakes.dart';

void main() {
  test('forklaringen etter HTTP-koden', () {
    expect(refusedText(404), startsWith('Kanalen finnes ikke hos leverandøren (HTTP 404)'));
    expect(refusedText(404, channel: false), startsWith('Finnes ikke hos leverandøren (HTTP 404)'));
    expect(refusedText(403), 'Leverandøren gir ikke tilgang (HTTP 403). Sjekk at abonnementet er aktivt.');
    expect(refusedText(503), 'Feil hos leverandøren (HTTP 503). Prøv igjen om litt.');
    expect(refusedText(407), startsWith('Leverandøren avviser denne kanalen (HTTP 407).'));
    expect(refusedText(407, channel: false), 'Leverandøren avviser avspillingen (HTTP 407). Prøv igjen senere.');
  });

  test('meldingen fra avspilleren i parentes: uten punktum til slutt', () {
    expect(plainMessage('Failed to recognize file format.'), 'Failed to recognize file format');
    expect(plainMessage(' Error while decoding frame! '), 'Error while decoding frame');
    expect(plainMessage('HTTP 509'), 'HTTP 509');
  });

  test('bare feil i åpningen og nettet stopper avspillingen, ikke feil i dekoderen', () {
    expect(mpvErrorIsFatal('cplayer', 'error', 'Failed to recognize file format.'), isTrue);
    expect(mpvErrorIsFatal('stream', 'error', 'Failed to open http://example/1.ts.'), isTrue);
    expect(mpvErrorIsFatal('ffmpeg', 'error', 'tcp: Connection refused'), isTrue);
    expect(mpvErrorIsFatal('vd', 'error', 'Error while decoding frame!'), isFalse);
    expect(mpvErrorIsFatal('ad', 'error', 'Error decoding audio.'), isFalse);
    expect(mpvErrorIsFatal('ffmpeg/video', 'error', 'h264: decode_slice_header error'), isFalse);
    expect(mpvErrorIsFatal('cplayer', 'warn', 'Something'), isFalse);
  });

  test('HTTP-koden fra leverandøren, med User-Agent', () async {
    final asked = <http.BaseRequest>[];
    final client = MockClient((req) async {
      asked.add(req);
      return http.Response('nei', 407);
    });
    expect(await httpStatus(client, 'http://example/live/u/p/1.ts', const {'User-Agent': 'VLC'}), 407);
    expect(asked.single.url.toString(), 'http://example/live/u/p/1.ts');
    expect(asked.single.headers['User-Agent'], 'VLC');

    final down = MockClient((req) async => throw http.ClientException('borte'));
    expect(await httpStatus(down, 'http://example/1.ts', const {}), isNull);
  });

  test('alle tilkoblingene i bruk går foran HTTP-koden, og uten feilkode brukes det avspilleren sa', () async {
    final src = FakeSource(connections: 1)
      ..activeConnections = 1
      ..streamCode = 407;
    expect(await explainFailure(src, 'http://example/1.ts', fallback: 'mpv'), startsWith('Tilkoblingen i abonnementet'));
    expect(src.statusAsked, isEmpty);

    src.activeConnections = 0;
    expect(await explainFailure(src, 'http://example/1.ts', fallback: 'mpv'), contains('HTTP 407'));
    expect(src.statusAsked, ['http://example/1.ts']);

    src.streamCode = 200;
    expect(await explainFailure(src, 'http://example/1.ts', fallback: 'mpv'), 'mpv');
    src.streamCode = null;
    expect(await explainFailure(src, 'http://example/1.ts', fallback: 'mpv'), 'mpv');
  });
}
