import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/models.dart';
import 'package:fyrlys/core/names.dart';

void main() {
  test('eventkanal: klokkeslett, kamp og resten', () {
    final p = nameParts('12:45 Aston Villa - Man City | Premier League 10/24 [Viaplay NO]');
    expect(p.time, '12:45');
    expect(p.main, 'Aston Villa - Man City');
    expect(p.sub, 'Premier League 10/24 [Viaplay NO]');
  });

  test('vanlig kanal', () {
    final p = nameParts('NRK 1 HD');
    expect(p.time, '');
    expect(p.main, 'NRK 1 HD');
    expect(p.sub, '');
  });

  test('punktum i klokkeslettet blir kolon', () {
    expect(nameParts('15.00 Lag A - Lag B').time, '15:00');
  });

  test('nå og neste fra EPG-en', () {
    final t = DateTime(2026, 10, 25, 20, 0);
    final list = [
      EpgEntry(title: 'Før', start: DateTime(2026, 10, 25, 18), stop: DateTime(2026, 10, 25, 19)),
      EpgEntry(title: 'Nå', start: DateTime(2026, 10, 25, 19, 30), stop: DateTime(2026, 10, 25, 20, 30)),
      EpgEntry(title: 'Senere', start: DateTime(2026, 10, 25, 21), stop: DateTime(2026, 10, 25, 22)),
      EpgEntry(title: 'Neste', start: DateTime(2026, 10, 25, 20, 30), stop: DateTime(2026, 10, 25, 21)),
    ];
    final nn = nowAndNext(list, t);
    expect(nn.now?.title, 'Nå');
    expect(nn.next?.title, 'Neste');
    expect(nn.now!.progressAt(t), 0.5);
    expect(hhmm(t), '20:00');
  });
}
