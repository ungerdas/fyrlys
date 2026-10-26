import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;

import '../l10n/tr.dart';
import 'models.dart';
import 'source.dart';

/// HTTP-koden [client] får på [url] (null når ingen svarer). Bare svaret leses, ikke strømmen, og forbindelsen
/// lukkes med en gang.
Future<int?> httpStatus(http.Client client, String url, Map<String, String> headers) async {
  try {
    final req = http.Request('GET', Uri.parse(url))..headers.addAll(headers);
    final res = await client.send(req).timeout(const Duration(seconds: 8));
    unawaited(res.stream.listen(null).cancel());
    return res.statusCode;
  } on Object {
    return null;
  }
}

/// Feilmeldingen når leverandøren svarer [code] (400 og over); [channel]: en direktesending (ellers en film, en
/// episode eller et program i arkivet).
String refusedText(int code, {bool channel = true}) {
  final args = {'code': code};
  return switch (code) {
    404 when channel => tr('Kanalen finnes ikke hos leverandøren (HTTP 404). Hent listene på nytt i innstillingene, '
        'eller prøv en annen kanal.'),
    404 => tr('Finnes ikke hos leverandøren (HTTP 404). Hent listene på nytt i innstillingene.'),
    401 || 403 => tr('Leverandøren gir ikke tilgang (HTTP {code}). Sjekk at abonnementet er aktivt.', args),
    >= 500 => tr('Feil hos leverandøren (HTTP {code}). Prøv igjen om litt.', args),
    _ when channel => tr('Leverandøren avviser denne kanalen (HTTP {code}). Prøv en annen kanal, eller prøv igjen '
        'senere.', args),
    _ => tr('Leverandøren avviser avspillingen (HTTP {code}). Prøv igjen senere.', args),
  };
}

/// Hvorfor [url] ikke kunne spilles, så godt det lar seg si: alle tilkoblingene i abonnementet er i bruk, eller
/// leverandøren avviser den (med HTTP-koden). Ellers [fallback] (det avspilleren sa).
Future<String> explainFailure(TvSource src, String url, {required String fallback, bool channel = true}) async {
  try {
    final busy = busyText(await src.account(fresh: true).timeout(const Duration(seconds: 8)));
    if (busy != null) return busy;
  } on Object {
    // vet ikke: spør etter strømmen
  }
  final code = await src.streamStatus(url);
  debugPrint('Kunne ikke spilles: ${src.redact(url)} svarer ${code ?? 'ikke'}');
  if (code != null && code >= 400) return refusedText(code, channel: channel);
  return fallback;
}
