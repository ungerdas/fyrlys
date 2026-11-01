// Kanaler som spilles fra kringkasterens egne direktesendinger i stedet for fra IPTV-leverandøren (eierens valg 1.11:
// NRK1, NRK2, NRK3 og NRK Super fra NRK). Kanalen beholder navnet, logoen, guiden og arkivet fra leverandøren; bare
// strømmen kommer herfra. Leverandørens adresser står etter, og brukes bare hvis denne ikke virker.

const _nrk = 'https://cdn0-47115-liveedge0.dna.contentdelivery.net/47115-liveedge0';

/// Nøkkelen (fra kanalnavnet, se [publicStreamKey]) → adressen.
const publicStreams = <String, String>{
  'nrk1': '$_nrk/nrk1/muxed.m3u8',
  'nrk2': '$_nrk/nrk2/muxed.m3u8',
  'nrk3': '$_nrk/nrk3/muxed.m3u8',
  'nrksuper': '$_nrk/nrksuper/muxed.m3u8',
};

/// Land foran navnet: «NO: », «NO | », «NOR - », «[NO] ».
final _country = RegExp(r'^\s*(\[\s*(no|nor|norge|norway)\s*\]\s*[:|\-–]?\s*|(no|nor|norge|norway)\s*[:|\-–]\s*)');

/// Kvalitet og slikt bak eller i klammer: «HD», «FHD», «(1080i)», «[HEVC]», «50fps».
final _quality = RegExp(r'\b(fhd|uhd|hd|sd|4k|hevc|h\.?26[45]|\d{3,4}[pi]|50 ?fps)\b');

/// «NRK1 HD», «NO: NRK 1 FHD», «NRK Super (1080i)» → «nrk1», «nrksuper»; ellers null. Regionale NRK1 («NRK1
/// Rogaland», «NRK 1 (Agder)») og andre kanaler med NRK i navnet («NRK Tegnspråk») får ikke en egen strøm.
String? publicStreamKey(String name) {
  var n = name.toLowerCase().replaceFirst(_country, '');
  n = n.replaceAll(_quality, ' ').replaceAll(RegExp(r'[^a-z0-9]'), '');
  // det som er igjen av «|NO| NRK1» og «NRK1HD»
  n = n.replaceFirst(RegExp(r'^(norway|norge|nor|no)(?=nrk)'), '').replaceFirst(RegExp(r'(fhd|uhd|hd|sd|4k)$'), '');
  return publicStreams.containsKey(n) ? n : null;
}

/// Kringkasterens egen strøm for kanalen [name], eller null.
String? publicStreamFor(String name) {
  final key = publicStreamKey(name);
  return key == null ? null : publicStreams[key];
}

/// Kommer [url] fra en av strømmene over (vises i infoen i spilleren)?
bool isPublicStream(String url) => url.startsWith(_nrk);
