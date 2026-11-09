// Ryddigere lister fra leverandører som har land og kvalitet i navnene: «NOR: TV 2 [720p]», «NO: VIAPLAY [PPV EVENTS]
// [1080p]». Landet og kvaliteten tas ut av navnet (kvaliteten blir et merke på kortet når den ikke er den vanlige,
// 1080p), og landet en kategori hører til, brukes til å vise bare de landene du vil se.

import '../l10n/tr.dart';
import 'models.dart';

/// Kvalitet i klammer eller parentes: «[1080p]», «[720p]», «[H265]», «[4K-Q]+», «(HEVC)», «[FHD]».
final _qualityTag = RegExp(r'[\[(]\s*(\d{3,4}[pi]|h\.?26[45]|hevc|uhd|fhd|hd|sd|[48]k[^\])]*)\s*[\])]\+?', caseSensitive: false);

/// Det samme uten klammene (et merke i et kategorinavn).
final _qualityWord = RegExp(r'^(\d{3,4}[pi]|h\.?26[45]|hevc|uhd|fhd|hd|sd|[48]k.*)$', caseSensitive: false);

/// Et merke foran kanalnavnet: «NOR: », «GOLD: », «UK | », «|NO| », «[NO] ».
final _channelPrefix =
    RegExp(r'^\s*(?:\|\s*[A-Za-z]{2,4}\s*\|\s*|\[\s*[A-Z]{2,4}\s*\]\s*|[A-Z][A-Z0-9+]{1,7}\s*[:|]\s+)');

/// Eventer har «LIVE:» og «NEXT:» foran; de står som de er.
final _eventPrefix = RegExp(r'^\s*(live|next|ended|soon|upcoming|replay|coming up)\s*:', caseSensitive: false);

/// Landet foran et kategorinavn: «NO: », «UK | », «|SE| », «[DK] ».
final _codeBefore =
    RegExp(r'^\s*(?:\|\s*([A-Za-z]{2,4})\s*\|\s*|\[\s*([A-Za-z]{2,4})\s*\]\s*|([A-Z][A-Z0-9+]{1,7})\s*[:|]\s*)');

/// Landet skrevet ut foran resten: «Norway - Sport», «Sweden | Film».
final _nameBefore = RegExp(r'^\s*([A-Za-zÀ-ÿ. ]{2,24}?)\s+[-–|]\s+');

/// Landet bak: «Viaplay Sport SE», «HBO Max Sports DK [B]».
final _codeAfter = RegExp(r'\s([A-Z]{2})(?:\s*\[[^\]]*\])*\s*$');

/// Koder som godtas bak navnet (der kunne det ellers vært «TV» eller «HD»).
const _codesAfter = {
  'NO', 'SE', 'DK', 'FI', 'IS', 'UK', 'US', 'DE', 'NL', 'FR', 'ES', 'IT', 'PL', 'PT', //
  'TR', 'BE', 'CZ', 'GR', 'BR', 'RO', 'AT', 'AU', 'CH', 'HR', 'CA', 'IE',
};

/// Land skrevet ut, på engelsk og på landets eget språk.
const _countryNames = {
  'norway': 'NO', 'norge': 'NO', 'noreg': 'NO', //
  'sweden': 'SE', 'sverige': 'SE',
  'denmark': 'DK', 'danmark': 'DK',
  'finland': 'FI', 'suomi': 'FI',
  'united kingdom': 'UK', 'great britain': 'UK', 'england': 'UK', 'uk': 'UK',
  'usa': 'US', 'united states': 'US', 'us': 'US', 'america': 'US',
  'germany': 'DE', 'deutschland': 'DE', 'tyskland': 'DE',
  'netherlands': 'NL', 'netherland': 'NL', 'holland': 'NL', 'nederland': 'NL',
  'france': 'FR',
  'spain': 'ES', 'españa': 'ES', 'espana': 'ES',
  'italy': 'IT', 'italia': 'IT',
  'poland': 'PL', 'polska': 'PL',
  'portugal': 'PT',
  'turkey': 'TR', 'türkiye': 'TR', 'turkiye': 'TR',
  'belgium': 'BE', 'belgie': 'BE', 'belgique': 'BE',
  'czech': 'CZ', 'czechia': 'CZ', 'czech republic': 'CZ',
  'greece': 'GR',
  'brazil': 'BR', 'brasil': 'BR',
  'romania': 'RO',
  'austria': 'AT', 'österreich': 'AT',
  'australia': 'AU',
  'switzerland': 'CH', 'schweiz': 'CH', 'suisse': 'CH',
  'croatia': 'HR', 'hrvatska': 'HR',
  'canada': 'CA',
  'ireland': 'IE',
};

/// «[1080p]» og «FHD» er det vanlige og får ikke noe merke; ellers «720p», «H265», «4K» …
String? _qualityLabel(String tag) {
  final t = tag.trim().toLowerCase();
  if (t.startsWith('1080') || t == 'fhd') return null;
  if (t.startsWith('4k') || t == 'uhd' || t.startsWith('2160')) return '4K';
  if (t.startsWith('8k')) return '8K';
  if (t == 'hevc' || t == 'h265' || t == 'h.265') return 'H265';
  if (t == 'h264' || t == 'h.264') return 'H264';
  if (t == 'hd') return 'HD';
  if (t == 'sd') return 'SD';
  return t;
}

/// Mellomrom samlet, og det som ble hengende igjen foran og bak («TV 2 -», «: TV 2»).
String _tidySpaces(String s) =>
    s.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'^[\s:|\-–·]+|[\s:|\-–·]+$'), '').trim();

/// Kanalnavnet uten merket foran og kvaliteten i klammer: «NOR: TV 2 [720p]» → «TV 2» og «720p»; «GOLD: NRK1
/// [1080p]» → «NRK1» (1080p er det vanlige). Navn uten slike merker står som de er.
({String name, String? quality}) tidyChannelName(String name) {
  String? quality;
  var changed = false;
  var n = name.replaceAllMapped(_qualityTag, (m) {
    changed = true;
    quality ??= _qualityLabel(m.group(1)!);
    return ' ';
  });
  if (!_eventPrefix.hasMatch(n)) {
    final m = _channelPrefix.firstMatch(n);
    if (m != null) {
      n = n.substring(m.end);
      changed = true;
    }
  }
  if (!changed) return (name: name, quality: null);
  n = _tidySpaces(n);
  return n.isEmpty ? (name: name.trim(), quality: null) : (name: n, quality: quality);
}

/// Klammer (merker) og teksten mellom dem.
final _segments = RegExp(r'\[([^\]]*)\]\+?|([^\[]+)');

/// Det som står mellom to kvalitetsmerker: «[720p] AND [H265]».
final _joiner = RegExp(r'^(and|og|&|\+|/|,|-|–)$', caseSensitive: false);

/// Kategorinavnet uten landet foran og den vanlige kvaliteten: «NO: VIAPLAY [PPV EVENTS] [1080p]» → «VIAPLAY · PPV
/// EVENTS», «NO: SPORT [720p] AND [H265]» → «SPORT · 720p · H265», «NO: [1080p]» → «Norge». Med [keepCountry] (flere
/// land vises) står koden foran: «NO · SPORT · 720p · H265». Navn uten land foran og kvalitet står som de er.
String tidyCategoryName(String name, {bool keepCountry = false}) {
  final m = _codeBefore.firstMatch(name);
  final code = m == null ? null : normalizeCountry((m.group(1) ?? m.group(2) ?? m.group(3))!);
  final rest = m == null ? name : name.substring(m.end);
  var changed = m != null;
  final parts = <String>[];
  final fromTag = <bool>[];
  final qualities = <String>[];
  for (final s in _segments.allMatches(rest)) {
    final tag = s.group(1);
    if (tag != null) {
      final t = tag.trim();
      if (_qualityWord.hasMatch(t)) {
        changed = true;
        final q = _qualityLabel(t);
        if (q != null && !qualities.contains(q)) qualities.add(q);
      } else if (t.isNotEmpty) {
        parts.add(t);
        fromTag.add(true);
      }
    } else {
      final text = _tidySpaces(s.group(2)!);
      if (text.isEmpty || _joiner.hasMatch(text)) continue;
      parts.add(text);
      fromTag.add(false);
    }
  }
  if (!changed) return name;
  final b = StringBuffer();
  for (var i = 0; i < parts.length; i++) {
    // et merke helt først hører til teksten etter: «[PLUS] PLAY» → «PLUS PLAY»
    if (i > 0) b.write(i == 1 && fromTag[0] && !fromTag[1] ? ' ' : ' · ');
    b.write(parts[i]);
  }
  final title = b.toString();
  final out = [
    // bare kvalitet («NO: [720p] AND [H265]»): landet er navnet
    if (title.isEmpty && code != null) countryLabel(code),
    if (title.isNotEmpty && keepCountry && code != null) code,
    if (title.isNotEmpty) title,
    ...qualities,
  ].join(' · ');
  return out.isEmpty ? name : out;
}

/// Én kode per land, uansett hvordan leverandøren skriver den («NOR» og «NO» er begge Norge).
String normalizeCountry(String code) => switch (code.toUpperCase()) {
      'NOR' => 'NO',
      'SWE' => 'SE',
      'DNK' || 'DEN' => 'DK',
      'FIN' => 'FI',
      'GBR' || 'GB' || 'ENG' => 'UK',
      'USA' => 'US',
      'DEU' || 'GER' => 'DE',
      'FRA' => 'FR',
      'ESP' || 'SPA' => 'ES',
      'ITA' => 'IT',
      'NLD' || 'HOL' => 'NL',
      'POL' => 'PL',
      'PRT' || 'POR' => 'PT',
      'TUR' => 'TR',
      'BEL' => 'BE',
      'CZE' => 'CZ',
      'GRC' || 'GRE' => 'GR',
      'BRA' => 'BR',
      'ROU' || 'ROM' => 'RO',
      'AUT' => 'AT',
      'AUS' => 'AU',
      'CHE' || 'SUI' => 'CH',
      'HRV' || 'CRO' => 'HR',
      'CAN' => 'CA',
      'IRL' => 'IE',
      final c => c,
    };

/// Landet en kategori hører til: «NO: Sport», «|SE| Film», «[DK] Nyheter», «Norway - Sport», «Viaplay Sport SE»
/// eller bare «Sweden». Null når navnet ikke sier noe om land.
String? countryOf(String category) {
  final m = _codeBefore.firstMatch(category);
  if (m != null) return normalizeCountry((m.group(1) ?? m.group(2) ?? m.group(3))!);
  final whole = _countryNames[category.trim().toLowerCase()];
  if (whole != null) return whole;
  final n = _nameBefore.firstMatch(category);
  if (n != null) {
    final c = _countryNames[n.group(1)!.trim().toLowerCase()];
    if (c != null) return c;
  }
  final a = _codeAfter.firstMatch(category);
  if (a != null && _codesAfter.contains(a.group(1))) return a.group(1);
  return null;
}

/// Navnet på landet («Norge»), eller koden slik leverandøren skriver den når den ikke er et kjent land («ARA» er
/// arabisk, men «AS» kan være mye). '' er kategoriene uten land.
String countryLabel(String code) => switch (code) {
      '' => tr('Uten land'),
      'NO' => tr('Norge'),
      'SE' => tr('Sverige'),
      'DK' => tr('Danmark'),
      'FI' => tr('Finland'),
      'UK' => tr('Storbritannia'),
      'US' => tr('USA'),
      'DE' => tr('Tyskland'),
      'NL' => tr('Nederland'),
      'FR' => tr('Frankrike'),
      'ES' => tr('Spania'),
      'IT' => tr('Italia'),
      'PL' => tr('Polen'),
      'PT' => tr('Portugal'),
      'TR' => tr('Tyrkia'),
      'BE' => tr('Belgia'),
      'CZ' => tr('Tsjekkia'),
      'GR' => tr('Hellas'),
      'BR' => tr('Brasil'),
      'RO' => tr('Romania'),
      'AT' => tr('Østerrike'),
      'AU' => tr('Australia'),
      'CH' => tr('Sveits'),
      'HR' => tr('Kroatia'),
      'CA' => tr('Canada'),
      'IE' => tr('Irland'),
      'ARA' => tr('Arabisk'),
      'EXYU' => tr('Eks-Jugoslavia'),
      'AFRICAN' => tr('Afrika'),
      'GLOBAL' => tr('Internasjonalt'),
      _ => code,
    };

/// Et land i lista: koden ('' = uten land), hvor mange kategorier og kanaler, og en av kategoriene slik
/// leverandøren skriver den (så en ukjent kode kan kjennes igjen).
typedef CountryGroup = ({String code, int categories, int channels, String example});

/// Landene i lista, i alfabetisk rekkefølge etter navnet, og «Uten land» sist. Bare land med kanaler.
List<CountryGroup> countryGroups(List<Category> categories, List<Channel> channels) {
  final countryOfCategory = {for (final c in categories) c.id: countryOf(c.name) ?? ''};
  final cats = <String, int>{};
  final example = <String, String>{};
  for (final c in categories) {
    final k = countryOfCategory[c.id]!;
    cats[k] = (cats[k] ?? 0) + 1;
    example.putIfAbsent(k, () => c.name);
  }
  final chans = <String, int>{};
  for (final c in channels) {
    final k = countryOfCategory[c.categoryId] ?? '';
    chans[k] = (chans[k] ?? 0) + 1;
  }
  final out = [
    for (final e in chans.entries)
      (code: e.key, categories: cats[e.key] ?? 0, channels: e.value, example: example[e.key] ?? ''),
  ];
  out.sort((a, b) {
    if (a.code.isEmpty != b.code.isEmpty) return a.code.isEmpty ? 1 : -1;
    return countryLabel(a.code).toLowerCase().compareTo(countryLabel(b.code).toLowerCase());
  });
  return out;
}
