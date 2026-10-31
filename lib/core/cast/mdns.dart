import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

/// En Chromecast (eller noe annet som tar imot Google Cast, f.eks. en TV med Google TV) på nettverket.
class CastDevice {
  const CastDevice({required this.id, required this.name, required this.host, this.port = 8009, this.model = ''});

  final String id;

  /// navnet den har fått, f.eks. «Stue»
  final String name;
  final String host;
  final int port;

  /// f.eks. «Chromecast» eller «Google TV Streamer»
  final String model;

  @override
  bool operator ==(Object other) => other is CastDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => '$name ($model, $host:$port)';
}

/// Tjenesten Chromecastene svarer på.
const castService = '_googlecast._tcp.local';

/// mDNS-spørsmålet etter [service] (PTR), med biten for «svar meg direkte».
Uint8List mdnsQuery(String service) {
  final b = BytesBuilder()
    // id 0, vanlig spørsmål, ett spørsmål
    ..add(const [0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0]);
  for (final label in service.split('.')) {
    final bytes = utf8.encode(label);
    b
      ..addByte(bytes.length)
      ..add(bytes);
  }
  b
    ..addByte(0)
    // PTR (12), klasse IN (1) med svar-direkte-biten
    ..add(const [0, 12, 0x80, 1]);
  return b.toBytes();
}

int _u16(Uint8List p, int i) {
  if (i + 1 >= p.length) throw const FormatException('for kort');
  return (p[i] << 8) | p[i + 1];
}

/// Et navn i DNS-pakken (med pekere til navn tidligere i pakken), og hvor det som står etter navnet begynner.
({String name, int next}) readDnsName(Uint8List p, int offset) {
  final labels = <String>[];
  var i = offset;
  // etter navnet (eller etter den første pekeren): -1 til det er kjent
  var next = -1;
  var jumps = 0;
  while (true) {
    if (i >= p.length) throw const FormatException('navnet går utenfor pakken');
    final length = p[i];
    if (length == 0) {
      if (next < 0) next = i + 1;
      break;
    }
    if ((length & 0xC0) == 0xC0) {
      if (i + 1 >= p.length) throw const FormatException('peker utenfor pakken');
      if (next < 0) next = i + 2;
      i = ((length & 0x3F) << 8) | p[i + 1];
      jumps++;
      if (jumps > 20) throw const FormatException('for mange pekere');
      continue;
    }
    if (i + 1 + length > p.length) throw const FormatException('navnet går utenfor pakken');
    labels.add(utf8.decode(p.sublist(i + 1, i + 1 + length), allowMalformed: true));
    i += 1 + length;
  }
  return (name: labels.join('.'), next: next);
}

/// Teksten i en TXT-post: «nøkkel=verdi»-par, hvert med lengden foran.
Map<String, String> _txt(Uint8List p, int start, int length) {
  final out = <String, String>{};
  var i = start;
  final end = start + length;
  while (i < end && i < p.length) {
    final n = p[i];
    if (i + 1 + n > end) break;
    final entry = utf8.decode(p.sublist(i + 1, i + 1 + n), allowMalformed: true);
    final eq = entry.indexOf('=');
    if (eq > 0) out[entry.substring(0, eq).toLowerCase()] = entry.substring(eq + 1);
    i += 1 + n;
  }
  return out;
}

/// Chromecastene i et mDNS-svar. [from] (avsenderen) brukes når svaret mangler adressen (A-posten).
List<CastDevice> parseCastResponse(Uint8List p, {InternetAddress? from}) {
  try {
    if (p.length < 12) return const [];
    // bare svar
    if ((_u16(p, 2) & 0x8000) == 0) return const [];
    final questions = _u16(p, 4);
    final records = _u16(p, 6) + _u16(p, 8) + _u16(p, 10);
    var i = 12;
    for (var q = 0; q < questions; q++) {
      i = readDnsName(p, i).next + 4;
    }
    final instances = <String, String>{};
    final srv = <String, ({String target, int port})>{};
    final txt = <String, Map<String, String>>{};
    final addresses = <String, String>{};
    for (var r = 0; r < records; r++) {
      final owner = readDnsName(p, i);
      i = owner.next;
      if (i + 10 > p.length) break;
      final type = _u16(p, i);
      final length = _u16(p, i + 8);
      final data = i + 10;
      i = data + length;
      if (i > p.length) break;
      final key = owner.name.toLowerCase();
      switch (type) {
        case 12 when key == castService:
          final name = readDnsName(p, data).name;
          instances[name.toLowerCase()] = name;
        case 33 when length >= 6:
          srv[key] = (target: readDnsName(p, data + 6).name.toLowerCase(), port: _u16(p, data + 4));
        case 16:
          txt[key] = _txt(p, data, length);
        case 1 when length == 4:
          addresses[key] = '${p[data]}.${p[data + 1]}.${p[data + 2]}.${p[data + 3]}';
      }
    }
    // svar uten PTR-posten, men med SRV for en Chromecast, gjelder også
    for (final key in srv.keys) {
      if (key.endsWith('.$castService')) instances.putIfAbsent(key, () => key);
    }
    final devices = <CastDevice>[];
    instances.forEach((key, original) {
      final s = srv[key];
      final t = txt[key] ?? const <String, String>{};
      final host = (s != null ? addresses[s.target] : null) ?? from?.address;
      if (host == null) return;
      final fallback = original.length > castService.length + 1
          ? original.substring(0, original.length - castService.length - 1)
          : original;
      devices.add(CastDevice(
        id: t['id'] ?? key,
        name: (t['fn'] ?? '').trim().isNotEmpty ? t['fn']!.trim() : fallback,
        host: host,
        port: s?.port ?? 8009,
        model: t['md'] ?? '',
      ));
    });
    return devices;
  } on FormatException {
    return const [];
  } on RangeError {
    return const [];
  }
}

/// Leter etter Chromecaster på nettverket i [timeout] og gir hver enkelt én gang, så snart den svarer.
///
/// Spørsmålet sendes ut på hvert nettverkskort fra en tilfeldig port (Chromecasten svarer da rett tilbake), og en
/// egen lytter på 5353 tar svarene som sendes til alle.
Stream<CastDevice> discoverCastDevices({Duration timeout = const Duration(seconds: 5)}) {
  late final StreamController<CastDevice> controller;
  final seen = <String>{};
  final sockets = <RawDatagramSocket>[];
  final query = mdnsQuery(castService);
  final group = InternetAddress('224.0.0.251');
  Timer? resend;
  Timer? end;
  var closed = false;

  Future<void> close() async {
    if (closed) return;
    closed = true;
    resend?.cancel();
    end?.cancel();
    for (final s in sockets) {
      s.close();
    }
    await controller.close();
  }

  void read(RawDatagramSocket socket) {
    while (true) {
      final d = socket.receive();
      if (d == null) break;
      for (final device in parseCastResponse(d.data, from: d.address)) {
        if (!closed && seen.add(device.id)) controller.add(device);
      }
    }
  }

  void watch(RawDatagramSocket socket) {
    sockets.add(socket);
    socket.listen((event) {
      if (event == RawSocketEvent.read) read(socket);
    }, onError: (Object _) {});
  }

  void send() {
    for (final s in sockets) {
      try {
        s.send(query, group, 5353);
      } on Object {
        // kortet er borte, eller Windows nekter: de andre prøves
      }
    }
  }

  Future<void> start() async {
    var interfaces = <NetworkInterface>[];
    try {
      interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    } on Object catch (e) {
      debugPrint('Chromecast: fant ikke nettverkskortene ($e)');
    }
    final local = [
      for (final ni in interfaces)
        for (final a in ni.addresses)
          if (!a.isLoopback) a,
    ];
    for (final address in [...local, InternetAddress.anyIPv4]) {
      if (closed) return;
      try {
        watch(await RawDatagramSocket.bind(address, 0, ttl: 255));
      } on Object {
        // ikke dette kortet
      }
    }
    try {
      final listener = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 5353, reuseAddress: true, ttl: 255);
      for (final ni in interfaces) {
        try {
          listener.joinMulticast(group, ni);
        } on Object {
          // ikke på dette kortet
        }
      }
      watch(listener);
    } on Object {
      // 5353 er opptatt: svarene rett tilbake holder
    }
    if (closed) return;
    send();
    resend = Timer.periodic(const Duration(seconds: 1), (_) => send());
    end = Timer(timeout, () => unawaited(close()));
  }

  controller = StreamController<CastDevice>(
    onListen: () => unawaited(start()),
    onCancel: close,
  );
  return controller.stream;
}
