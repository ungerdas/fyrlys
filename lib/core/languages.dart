// Språkene du foretrekker for lydspor og undertekster, og kodene avspilleren kjenner dem på.

/// Et språk du kan velge, med kodene det kan ha i filer og sendinger (ISO 639-2 og -1, og norsk bokmål/nynorsk).
class Language {
  const Language(this.id, this.name, this.codes);

  final String id;
  final String name;
  final List<String> codes;
}

const languages = [
  Language('no', 'Norsk', ['nor', 'nob', 'nno', 'no', 'nb', 'nn']),
  Language('en', 'Engelsk', ['eng', 'en']),
  Language('sv', 'Svensk', ['swe', 'sv']),
  Language('da', 'Dansk', ['dan', 'da']),
  Language('fi', 'Finsk', ['fin', 'fi']),
  Language('de', 'Tysk', ['ger', 'deu', 'de']),
  Language('fr', 'Fransk', ['fre', 'fra', 'fr']),
  Language('es', 'Spansk', ['spa', 'es']),
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

  /// «norsk, så engelsk»
  static String describe(List<String> ids) {
    final names = [for (final id in ids) if (languageById(id) case final l?) l.name.toLowerCase()];
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    return '${names.take(names.length - 1).join(', ')}, så ${names.last}';
  }

  /// Kort til menyen: «Lyd: norsk, så engelsk · Undertekster: av»
  String get summary {
    final a = describe(audio);
    final s = subtitlesOff ? 'av' : describe(subtitles);
    return [if (a.isNotEmpty) 'Lyd: $a', if (s.isNotEmpty) 'Undertekster: $s'].join(' · ');
  }
}
