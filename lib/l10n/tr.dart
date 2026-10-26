// Språket i appen. Teksten i koden er norsk, og den er også nøkkelen til oversettelsen: tr('Logg ut') gir «Log out»
// på engelsk. {navn} i teksten byttes med verdiene i args: tr('Byttet til {name}', {'name': login.name}).
// Det som mangler i oversettelsen, vises på norsk (testen i test/l10n_test.dart sier fra om det).

import 'en.dart';

/// 'no' (norsk) eller 'en' (engelsk). Settes av Session; norsk til da (og i testene).
String appLanguage = 'no';

/// [no] på språket appen vises på, med {navn} byttet ut med verdiene i [args].
String tr(String no, [Map<String, Object?> args = const {}]) {
  var text = appLanguage == 'en' ? (english[no] ?? no) : no;
  args.forEach((key, value) => text = text.replaceAll('{$key}', '$value'));
  return text;
}

/// Språket Windows bruker: norsk for nb, nn og no, ellers engelsk.
String languageOfLocale(String languageCode) =>
    const {'nb', 'nn', 'no'}.contains(languageCode.toLowerCase()) ? 'no' : 'en';
