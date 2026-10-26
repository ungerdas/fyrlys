// Engelsk: norsk tekst → engelsk, delt i filer etter hvor teksten står (så flere kan oversette samtidig).
// Testen i test/l10n_test.dart sier fra om noe mangler.

import 'en_core.dart';
import 'en_home.dart';
import 'en_player.dart';
import 'en_settings.dart';
import 'en_vod.dart';

/// Alle oversettelsene.
final Map<String, String> english = {
  ...enCore,
  ...enHome,
  ...enPlayer,
  ...enSettings,
  ...enVod,
};
