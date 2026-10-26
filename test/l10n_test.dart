import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/app.dart';
import 'package:fyrlys/core/session.dart';
import 'package:fyrlys/l10n/dates.dart';
import 'package:fyrlys/l10n/en.dart';
import 'package:fyrlys/l10n/tr.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

/// Én Dart-streng fra [i] ('…', "…", r'…', '''…'''): teksten, hvor den slutter, og om den har $-innsetting.
({String text, int end, bool interpolated})? _string(String src, int i) {
  var raw = false;
  if (i < src.length && src[i] == 'r' && i + 1 < src.length && (src[i + 1] == "'" || src[i + 1] == '"')) {
    raw = true;
    i++;
  }
  if (i >= src.length || (src[i] != "'" && src[i] != '"')) return null;
  final q = src[i];
  final triple = src.startsWith(q * 3, i);
  final end = triple ? q * 3 : q;
  i += end.length;
  final out = StringBuffer();
  var interpolated = false;
  while (i < src.length) {
    if (src.startsWith(end, i)) return (text: out.toString(), end: i + end.length, interpolated: interpolated);
    final c = src[i];
    if (c == r'\' && !raw) {
      final n = src[i + 1];
      out.write(switch (n) { 'n' => '\n', 't' => '\t', _ => n });
      i += 2;
      continue;
    }
    if (c == r'$' && !raw) interpolated = true;
    out.write(c);
    i++;
  }
  return null;
}

int _skip(String src, int i) {
  while (i < src.length) {
    if (' \t\r\n'.contains(src[i])) {
      i++;
    } else if (src.startsWith('//', i)) {
      final nl = src.indexOf('\n', i);
      i = nl < 0 ? src.length : nl;
    } else {
      break;
    }
  }
  return i;
}

/// Strenger etter hverandre ('a' 'b') fra [i], slått sammen.
({String text, int end, bool interpolated})? _strings(String src, int i) {
  final parts = <String>[];
  var interpolated = false;
  while (true) {
    final j = _skip(src, i);
    final s = _string(src, j);
    if (s == null) break;
    parts.add(s.text);
    interpolated |= s.interpolated;
    i = s.end;
  }
  if (parts.isEmpty) return null;
  return (text: parts.join(), end: i, interpolated: interpolated);
}

/// Alle tr('…') i lib/, med hvor de står.
Map<String, List<String>> _keys() {
  final keys = <String, List<String>>{};
  final call = RegExp(r'(?<![\w.$])tr\(');
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    final name = f.uri.pathSegments.last;
    if (f.parent.uri.pathSegments.contains('l10n') && name.startsWith('en')) continue;
    final src = f.readAsStringSync();
    for (final m in call.allMatches(src)) {
      final lineStart = src.lastIndexOf('\n', m.start) + 1;
      if (src.substring(lineStart, m.start).trimLeft().startsWith('//')) continue;
      final s = _strings(src, m.end);
      if (s == null) continue;
      final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
      final where = '${f.path}:$line';
      if (s.interpolated) fail(r'$ i nøkkelen (bruk {navn}): ' '$where ${s.text}');
      keys.putIfAbsent(s.text, () => []).add(where);
    }
  }
  return keys;
}

final _placeholder = RegExp(r'\{(\w+)\}');

Set<String> _placeholders(String s) => {for (final m in _placeholder.allMatches(s)) m.group(1)!};

void main() {
  tearDown(() => appLanguage = 'no');

  test('alt med tr() er oversatt til engelsk, med de samme {navnene}', () {
    final keys = _keys();
    expect(keys, isNotEmpty);
    final missing = [
      for (final e in keys.entries)
        if ((english[e.key] ?? '').trim().isEmpty) '${e.value.first}: ${e.key}',
    ];
    expect(missing, isEmpty, reason: 'mangler engelsk');
    final mismatched = [
      for (final e in keys.entries)
        if (english[e.key] != null && !_setEquals(_placeholders(e.key), _placeholders(english[e.key]!)))
          '${e.key} → ${english[e.key]}',
    ];
    expect(mismatched, isEmpty, reason: 'ulike {} i norsk og engelsk');
  });

  test('tr: norsk som standard, engelsk når det er valgt, {navn} byttes ut', () {
    expect(tr('Lagre feilrapport'), 'Lagre feilrapport');
    expect(tr('Bildeformat: {name}', {'name': 'Original'}), 'Bildeformat: Original');
    appLanguage = 'en';
    expect(tr('Lagre feilrapport'), english['Lagre feilrapport']);
    expect(tr('finnes ikke i oversettelsen'), 'finnes ikke i oversettelsen');
    expect(languageOfLocale('nb'), 'no');
    expect(languageOfLocale('NN'), 'no');
    expect(languageOfLocale('en'), 'en');
    expect(languageOfLocale('sv'), 'en');
  });

  testWidgets('språket byttes i innstillingene, og alt bygges på nytt uten at noe lukkes', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'source': '{"kind":"fake"}'});
    final session = Session(await SharedPreferences.getInstance(), sourceFactory: (_) async => FakeSource());
    await session.restore();
    await tester.pumpWidget(FyrlysApp(session: session));
    await tester.pumpAndSettle();
    expect(session.language, 'auto');
    await tester.tap(find.byTooltip('Innstillinger'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(session.language, 'en');
    expect(appLanguage, 'en');
    expect((await SharedPreferences.getInstance()).getString('language'), 'en');
    // innstillingene er fortsatt åpne, nå på engelsk
    expect(find.text(english['Innstillinger']!), findsOneWidget);
    expect(find.text('Innstillinger'), findsNothing);
    expect(find.text(english['Språk']!), findsWidgets);
    // og TV-siden under
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byTooltip(english['Innstillinger']!), findsOneWidget);

    await tester.tap(find.byTooltip(english['Innstillinger']!));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Norsk'));
    await tester.pumpAndSettle();
    expect(appLanguage, 'no');
    expect(find.text('Innstillinger'), findsOneWidget);
  });

  test('datoene på begge språk', () {
    final t = DateTime(2026, 10, 24);
    expect(longDate(t), 'Lørdag 24. oktober');
    appLanguage = 'en';
    expect(longDate(t), 'Saturday 24 October');
  });
}

bool _setEquals(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);
