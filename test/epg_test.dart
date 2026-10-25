import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/models.dart';

/// Klokkeslett i kveld, «2246» → 22:46 (over midnatt: «2416» → 00:16).
DateTime t(int hhmm) => DateTime(2026, 10, 25).add(Duration(hours: hhmm ~/ 100, minutes: hhmm % 100));

EpgEntry e(String title, int start, int stop, [String description = '']) =>
    EpgEntry(title: title, start: t(start), stop: t(stop), description: description);

List<(String, DateTime, DateTime)> plain(List<EpgEntry> list) => [for (final x in list) (x.title, x.start, x.stop)];

void main() {
  test('samme program to ganger med ulike tider blir ett', () {
    // som på NRK 3: «Bløff» og «Nytt på nytt» to ganger, fire minutter fra hverandre
    final out = cleanEpg([
      e('Bløff', 2246, 2346),
      e('Bløff', 2250, 2350, 'Panel'),
      e('Nytt på nytt', 2346, 2416),
      e('Nytt på nytt', 2350, 2420),
    ]);
    expect(plain(out), [('Bløff', t(2246), t(2346)), ('Nytt på nytt', t(2346), t(2420))]);
    expect(out.first.description, 'Panel');
  });

  test('overlapp: programmet slutter der det neste begynner', () {
    // som på NRK 2: «De arktiske redderne» til 23:15, men «Nashville» begynner 23:05
    final out = cleanEpg([e('Nashville', 2305, 2350), e('De arktiske redderne', 2215, 2315)]);
    expect(plain(out), [('De arktiske redderne', t(2215), t(2305)), ('Nashville', t(2305), t(2350))]);
    expect(nowAndNext(out, t(2310)).now?.title, 'Nashville');
  });

  test('samme start: det lengste blir', () {
    final out = cleanEpg([e('Film', 2000, 2200), e('Nyheter', 2000, 2010), e('Sport', 2200, 2300)]);
    expect(plain(out), [('Film', t(2000), t(2200)), ('Sport', t(2200), t(2300))]);
  });

  test('like titler etter hverandre er egne programmer, og tomme tas bort', () {
    final out = cleanEpg([e('Åsted Norge', 2445, 2545), e('Åsted Norge', 2545, 2615), e('Tomt', 2700, 2700)]);
    expect(plain(out), [('Åsted Norge', t(2445), t(2545)), ('Åsted Norge', t(2545), t(2615))]);
  });
}
