// Kanaler som spilles fra kringkasterens egne direktesendinger i stedet for fra IPTV-leverandøren (eierens valg 1.11:
// NRK1, NRK2, NRK3 og NRK Super fra NRK; «IPTV skal være reserve»). Leverandørens varianter av hver (HD, FHD,
// «NRK 3/SUPER») blir én kanal i lista, med logoen, guiden og arkivet fra den beste varianten; bare strømmen kommer
// herfra. Leverandørens adresser står etter, og brukes bare hvis denne ikke virker.

import 'models.dart';

const _nrk = 'https://cdn0-47115-liveedge0.dna.contentdelivery.net/47115-liveedge0';

/// Nøkkelen (fra kanalnavnet, se [publicStreamKeys]) → adressen.
const publicStreams = <String, String>{
  'nrk1': '$_nrk/nrk1/muxed.m3u8',
  'nrk2': '$_nrk/nrk2/muxed.m3u8',
  'nrk3': '$_nrk/nrk3/muxed.m3u8',
  'nrksuper': '$_nrk/nrksuper/muxed.m3u8',
};

/// Navnet en sammenslått kanal får.
const publicNames = <String, String>{
  'nrk1': 'NRK1',
  'nrk2': 'NRK2',
  'nrk3': 'NRK3',
  'nrksuper': 'NRK Super',
};

/// NRK3 og NRK Super deler kanal hos mange leverandører («NRK 3/SUPER»): den blir til begge.
const _shared = {'nrk3super', 'nrk3nrksuper', 'nrksupernrk3', 'nrksuper3'};

/// Land foran navnet: «NO: », «NO | », «NOR - », «[NO] ».
final _countryBefore = RegExp(r'^\s*(\[\s*(no|nor|norge|norway)\s*\]\s*[:|\-–]?\s*|(no|nor|norge|norway)\s*[:|\-–]\s*)');

/// Land bak navnet: « NO», « [NO]», « (NO)».
final _countryAfter = RegExp(r'[\[\(]?\s*\b(no|nor|norge|norway)\b\s*[\]\)]?\s*$');

/// Kvalitet og slikt, også i klammer: «HD», «FHD», «(1080i)», «[HEVC]», «50fps».
final _qualityWords = RegExp(r'\b(fhd|uhd|hd|sd|4k|hevc|h\.?26[45]|\d{3,4}[pi]|50 ?fps)\b');

/// Kanalnavnet uten land, kvalitet og tegn: «NO: NRK 1 FHD» og «NRK 1 HD NO» → «nrk1».
String _clean(String name) {
  var n = name.toLowerCase().replaceFirst(_countryBefore, '');
  n = n.replaceAll(_qualityWords, ' ').replaceFirst(_countryAfter, '').replaceAll(RegExp(r'[^a-z0-9]'), '');
  // det som er igjen av «|NO| NRK1» og «NRK1HD»
  return n.replaceFirst(RegExp(r'^(norway|norge|nor|no)(?=nrk)'), '').replaceFirst(RegExp(r'(fhd|uhd|hd|sd|4k)$'), '');
}

/// «NRK1 HD», «NRK 1 FHD NO», «NO: NRK Super» → [«nrk1»] / [«nrksuper»]; «NRK 3/SUPER HD NO» → [«nrk3», «nrksuper»];
/// ellers ingen. Regionale NRK1 («NRK1 Rogaland», «NRK Rogaland 24»), «NRK 2 Lydtekst» og andre kanaler med NRK i
/// navnet («NRK Tegnspråk») får ikke NRK sin strøm og slås ikke sammen.
List<String> publicStreamKeys(String name) {
  final n = _clean(name);
  if (publicStreams.containsKey(n)) return [n];
  if (_shared.contains(n)) return const ['nrk3', 'nrksuper'];
  return const [];
}

/// Nøkkelen når navnet er én av kanalene (ikke den delte «NRK 3/SUPER»), ellers null.
String? publicStreamKey(String name) {
  final keys = publicStreamKeys(name);
  return keys.length == 1 ? keys.single : null;
}

/// Kringkasterens egen strøm for kanalen [name], eller null.
String? publicStreamFor(String name) {
  final key = publicStreamKey(name);
  return key == null ? null : publicStreams[key];
}

/// Kommer [url] fra en av strømmene over (vises i infoen i spilleren)?
bool isPublicStream(String url) => url.startsWith(_nrk);

/// Id-en hos leverandøren. En kanal som er laget av en annen (NRK Super av den eneste «NRK 3/SUPER») har
/// «<id>~nrksuper».
String providerChannelId(String id) {
  final i = id.indexOf('~');
  return i < 0 ? id : id.substring(0, i);
}

/// FHD foran HD foran resten foran SD; en delt kanal («NRK 3/SUPER») sist.
int _rank(Channel c) {
  final n = c.name.toLowerCase();
  var r = RegExp(r'\b(fhd|uhd|4k|2160[pi]?)\b').hasMatch(n)
      ? 3
      : RegExp(r'\b(hd|1080[pi]?|720p)\b').hasMatch(n)
          ? 2
          : RegExp(r'\bsd\b').hasMatch(n)
              ? 0
              : 1;
  if (publicStreamKeys(c.name).length > 1) r -= 10;
  return r;
}

/// Leverandørens varianter av NRK1, NRK2, NRK3 og NRK Super blir én kanal hver, der den første varianten sto
/// (NRK Super rett etter NRK3). Den beste varianten gir id, logo, guide og arkiv, slik at favoritter og
/// «sist sett» på den beholdes. Er det bare én, og den ikke er delt, står den som den er. Kan kjøres flere ganger.
List<Channel> mergePublicChannels(List<Channel> channels) {
  final groups = <String, List<Channel>>{};
  for (final c in channels) {
    for (final k in publicStreamKeys(c.name)) {
      (groups[k] ??= []).add(c);
    }
  }
  if (groups.isEmpty) return channels;
  final used = <String>{};
  final done = <String>{};
  final out = <Channel>[];
  for (final c in channels) {
    final keys = publicStreamKeys(c.name);
    if (keys.isEmpty) {
      out.add(c);
      continue;
    }
    for (final k in keys) {
      if (done.add(k)) out.add(_merge(k, groups[k]!, used));
    }
  }
  return out;
}

Channel _merge(String key, List<Channel> variants, Set<String> used) {
  int order(Channel a, Channel b) {
    final d = _rank(b).compareTo(_rank(a));
    return d != 0 ? d : variants.indexOf(a).compareTo(variants.indexOf(b));
  }

  final ranked = [...variants]..sort(order);
  final best = ranked.first;
  if (variants.length == 1 && publicStreamKeys(best.name).length == 1 && used.add(best.id)) return best;
  // id-en til den beste varianten som ikke er tatt (NRK3 og NRK Super deler variantene av «NRK 3/SUPER»)
  final pick = ranked.firstWhere((c) => !used.contains(c.id), orElse: () => best);
  final id = used.contains(pick.id) ? '${best.id}~$key' : pick.id;
  used.add(id);
  int numberOf(Channel c) => int.tryParse(c.number ?? '') ?? 1 << 30;
  final first = [...variants]..sort((a, b) => numberOf(a).compareTo(numberOf(b)));
  return Channel(
    id: id,
    name: publicNames[key]!,
    categoryId: variants.first.categoryId,
    icon: pick.icon ?? best.icon,
    number: first.first.number,
    hasEpg: pick.hasEpg,
    archiveDays: pick.archiveDays,
  );
}
