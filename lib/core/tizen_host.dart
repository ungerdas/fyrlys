import 'package:device_info_plus_tizen/device_info_plus_tizen.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../platform.dart';

/// Samsung-TV-en til feilrapporten: «Tizen 8.0 · QE55Q80C» (versjonen avgjør hvilken Fyrlys-pakke som passer).
/// Null utenfor TV-en. Ikke DUID-en eller andre id-er.
Future<String?> tizenDevice() async {
  if (!isTizen) return null;
  try {
    final info = await DeviceInfoPluginTizen().tizenInfo;
    final version = info.platformVersion?.trim() ?? '';
    final model = info.modelName?.trim() ?? '';
    return [if (version.isNotEmpty) 'Tizen $version', if (model.isNotEmpty) model].join(' · ');
  } on Object catch (e) {
    debugPrint('Fant ikke TV-ens versjon (${e.runtimeType})');
    return null;
  }
}
