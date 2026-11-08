import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../l10n/tr.dart';

// Feilkodene fra operativsystemet når en tilkobling ikke kommer i stand (Linux, macOS/Android og Windows; på Windows
// gir Dart ofte de vanlige feilkodene, som 1225, i stedet for Winsock sine, som 10061).
const _refused = {111, 61, 10061, 1225};
const _timedOut = {110, 60, 10060, 121};
const _noRoute = {101, 51, 10051, 113, 65, 10065, 1231, 1232};
const _reset = {104, 54, 10054, 103, 53, 10053, 64, 1236};

/// Hvorfor serveren ikke ga noe svar (navnet finnes ikke, porten er stengt, https mot en port uten https …), som en
/// setning brukeren kan gjøre noe med. [error] er det http-klienten kastet. Uten vertsnavnet, så teksten kan stå i
/// loggen og feilrapporten.
String connectionProblem(Object error) {
  if (error is TimeoutException) {
    return tr('Serveren svarer ikke. Sjekk adressen og porten, eller prøv igjen senere.');
  }
  if (error is TlsException) {
    final text = '${error.message} ${error.osError?.message ?? ''}'.toUpperCase();
    if (text.contains('WRONG_VERSION_NUMBER') || text.contains('HTTP_REQUEST') || text.contains('PACKET_LENGTH')) {
      return tr('Serveren svarer ikke på https på denne porten. Prøv adressen med http:// foran.');
    }
    if (error is CertificateException || text.contains('CERTIFICATE')) {
      return tr('Sertifikatet til serveren godtas ikke, så den sikre tilkoblingen (https) ble stoppet. Har du fått en '
          'adresse med http:// fra leverandøren, bruk den.');
    }
    return tr('Den sikre tilkoblingen (https) til serveren feilet.');
  }
  if (error is SocketException) {
    final code = error.osError?.errorCode;
    // Dart skriver denne selv (på engelsk); det operativsystemet sier, kan være på norsk
    if (error.message.contains('host lookup')) {
      return tr('Fant ikke serveren. Sjekk at adressen er skrevet riktig.');
    }
    if (_refused.contains(code)) {
      return tr('Serveren tar ikke imot tilkoblinger på porten i adressen. Sjekk porten (tallet etter kolon).');
    }
    if (_timedOut.contains(code)) {
      return tr('Serveren svarer ikke. Sjekk adressen og porten, eller prøv igjen senere.');
    }
    if (_noRoute.contains(code)) return tr('Får ikke kontakt med serveren. Sjekk nettforbindelsen.');
    if (_reset.contains(code)) return tr('Serveren brøt forbindelsen. Prøv igjen om litt.');
  }
  if (error is http.ClientException) {
    final text = error.message.toLowerCase();
    if (text.contains('connection closed') || text.contains('reset')) {
      return tr('Serveren brøt forbindelsen. Prøv igjen om litt.');
    }
  }
  return tr('Får ikke kontakt med IPTV-serveren');
}

/// Serveren tok imot forespørselen, men lukket forbindelsen uten å svare. Noen servere gjør det med klienter de
/// stenger ute (nginx sin «444»), så ved innloggingen er det verdt å prøve igjen som en annen klient.
bool closedByServer(Object error) {
  if (error is SocketException) return _reset.contains(error.osError?.errorCode);
  if (error is http.ClientException) {
    final text = error.message.toLowerCase();
    return text.contains('connection closed') || text.contains('reset');
  }
  return false;
}

/// Hva slags feil [error] var, til loggen: typen og feilkoden, aldri adressen (den har brukernavn og passord).
String errorKind(Object error) {
  if (error is SocketException) return 'SocketException ${error.osError?.errorCode ?? ''}'.trim();
  if (error is TlsException) return '${error.runtimeType} ${error.osError?.message ?? ''}'.trim();
  if (error is TimeoutException) return 'TimeoutException';
  if (error is http.ClientException) return 'ClientException: ${error.message}';
  return '${error.runtimeType}';
}
