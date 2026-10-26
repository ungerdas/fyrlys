// Språkene du foretrekker for lydspor og undertekster, og kodene avspilleren kjenner dem på.

import '../l10n/tr.dart';

/// Et språk du kan velge, med kodene det kan ha i filer og sendinger (ISO 639-2 og -1, og norsk bokmål/nynorsk).
class Language {
  const Language(this.id, this.codes);

  final String id;
  final List<String> codes;

  /// «Norsk», «Engelsk» … på språket appen vises på
  String get name => switch (id) {
        'no' => tr('Norsk'),
        'en' => tr('Engelsk'),
        'sv' => tr('Svensk'),
        'da' => tr('Dansk'),
        'fi' => tr('Finsk'),
        'de' => tr('Tysk'),
        'fr' => tr('Fransk'),
        'es' => tr('Spansk'),
        _ => id,
      };
}

const languages = [
  Language('no', ['nor', 'nob', 'nno', 'no', 'nb', 'nn']),
  Language('en', ['eng', 'en']),
  Language('sv', ['swe', 'sv']),
  Language('da', ['dan', 'da']),
  Language('fi', ['fin', 'fi']),
  Language('de', ['ger', 'deu', 'de']),
  Language('fr', ['fre', 'fra', 'fr']),
  Language('es', ['spa', 'es']),
];

Language? languageById(String id) {
  for (final l in languages) {
    if (l.id == id) return l;
  }
  return null;
}

/// Det du har valgt, i den rekkefølgen du valgte. Undertekster kan også være slått av helt («off»).
class LanguagePrefs {
  const LanguagePrefs({this.audio = const [], this.subtitles = const []});

  /// språk-id-er («no», «en» …), det viktigste først; tom: som filen eller kanalen selv velger
  final List<String> audio;

  /// språk-id-er, eller bare «off»; tom: bare undertekster filen selv slår på
  final List<String> subtitles;

  static const off = 'off';

  bool get subtitlesOff => subtitles.contains(off);

  /// til mpv sin `alang`
  String get audioCodes => _codes(audio);

  /// til mpv sin `slang`
  String get subtitleCodes => subtitlesOff ? '' : _codes(subtitles);

  bool get isEmpty => audio.isEmpty && subtitles.isEmpty;

  static String _codes(List<String> ids) => [for (final id in ids) ...?languageById(id)?.codes].join(',');

  /// «norsk, så engelsk» (på engelsk med stor forbokstav: «Norwegian, then English»)
  static String describe(List<String> ids) {
    final names = [
      for (final id in ids)
        if (languageById(id) case final l?) appLanguage == 'en' ? l.name : l.name.toLowerCase(),
    ];
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    return tr('{first}, så {last}', {'first': names.take(names.length - 1).join(', '), 'last': names.last});
  }

  /// Kort til innstillingene: «Lyd: norsk, så engelsk · Undertekster: av»
  String get summary {
    final a = describe(audio);
    final s = subtitlesOff ? tr('av') : describe(subtitles);
    return [
      if (a.isNotEmpty) tr('Lyd: {languages}', {'languages': a}),
      if (s.isNotEmpty) tr('Undertekster: {languages}', {'languages': s}),
    ].join(' · ');
  }
}
