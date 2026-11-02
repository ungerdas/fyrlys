import 'dart:io';

/// Adressen Chromecasten på [host] kan hente fra mellomstasjonen på: den av maskinens adresser som har flest bits felles
/// med Chromecastens (hjemme: samme nett, 192.168.1.x og 192.168.1.y), ikke VPN eller mobilnettet.
///
/// Dart sin `Socket.address` er adressen det ble koblet *til* for en socket vi åpner selv, altså Chromecastens egen.
/// Fram til 2.1.32 fikk mellomstasjonen den, så Chromecasten prøvde å hente strømmen fra seg selv og fikk aldri noe.
Future<InternetAddress?> localAddressFor(String host) async {
  final target = InternetAddress.tryParse(host);
  if (target == null) return null;
  // på samme maskin (testene)
  if (target.isLoopback) return target;
  final List<NetworkInterface> interfaces;
  try {
    interfaces = await NetworkInterface.list(type: target.type);
  } on Object {
    return null;
  }
  return pickLocalAddress(target, [for (final i in interfaces) ...i.addresses]);
}

/// Den av [candidates] som har flest bits felles med [target]: samme slag (IPv4/IPv6), ikke loopback, og link-local
/// (169.254.x.x, fe80::) bare når [target] også er det. Null når ingen passer.
InternetAddress? pickLocalAddress(InternetAddress target, List<InternetAddress> candidates) {
  InternetAddress? best;
  var bestBits = -1;
  for (final a in candidates) {
    if (a.type != target.type || a.isLoopback) continue;
    if (a.isLinkLocal && !target.isLinkLocal) continue;
    final bits = commonPrefixBits(a, target);
    if (bits > bestBits) {
      best = a;
      bestBits = bits;
    }
  }
  return best;
}

/// Hvor mange bits fra starten [a] og [b] har felles (24 for 192.168.1.20 og 192.168.1.35).
int commonPrefixBits(InternetAddress a, InternetAddress b) {
  final x = a.rawAddress;
  final y = b.rawAddress;
  if (x.length != y.length) return 0;
  var bits = 0;
  for (var i = 0; i < x.length; i++) {
    final d = x[i] ^ y[i];
    if (d == 0) {
      bits += 8;
      continue;
    }
    for (var m = 0x80; m > 0 && (d & m) == 0; m >>= 1) {
      bits++;
    }
    break;
  }
  return bits;
}
