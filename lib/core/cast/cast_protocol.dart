import 'dart:convert';
import 'dart:typed_data';

// Google Cast (CASTV2): TLS til port 8009, og meldinger som er protobuf-meldingen CastMessage med JSON som tekst.
// Hver melding har fire byte med lengden foran.

const nsConnection = 'urn:x-cast:com.google.cast.tp.connection';
const nsHeartbeat = 'urn:x-cast:com.google.cast.tp.heartbeat';
const nsReceiver = 'urn:x-cast:com.google.cast.receiver';
const nsMedia = 'urn:x-cast:com.google.cast.media';

/// Googles egen avspiller på Chromecasten (Default Media Receiver): krever ingen registrering.
const defaultMediaReceiver = 'CC1AD845';

/// Én melding: fra hvem, til hvem, i hvilket navnerom, og JSON-teksten.
class CastMessage {
  CastMessage({required this.source, required this.destination, required this.namespace, required this.payload});

  final String source;
  final String destination;
  final String namespace;
  final String payload;

  /// JSON-en (tom når teksten ikke er et JSON-objekt)
  late final Map<String, Object?> json = _decode(payload);

  /// f.eks. «RECEIVER_STATUS» eller «MEDIA_STATUS»
  String get type => json['type'] is String ? json['type'] as String : '';

  /// requestId i svaret (0 når det ikke er et svar på noe)
  int get requestId => json['requestId'] is int ? json['requestId'] as int : 0;

  static Map<String, Object?> _decode(String text) {
    try {
      final value = jsonDecode(text);
      if (value is Map) return Map<String, Object?>.from(value);
    } on FormatException {
      // ikke JSON: tomt
    }
    return const {};
  }

  /// Protobuf-meldingen (uten lengden foran).
  Uint8List encode() {
    final b = BytesBuilder();
    // 1: protocol_version = CASTV2_1_0 (0)
    b
      ..addByte(0x08)
      ..addByte(0);
    _string(b, 2, source);
    _string(b, 3, destination);
    _string(b, 4, namespace);
    // 5: payload_type = STRING (0)
    b
      ..addByte(0x28)
      ..addByte(0);
    _string(b, 6, payload);
    return b.toBytes();
  }

  /// Leser protobuf-meldingen; null når den ikke er en CastMessage med tekst.
  static CastMessage? decode(List<int> bytes) {
    var i = 0;
    int varint() {
      var value = 0;
      var shift = 0;
      while (true) {
        if (i >= bytes.length || shift > 63) throw const FormatException('ufullstendig tall');
        final byte = bytes[i++];
        value |= (byte & 0x7f) << shift;
        if (byte < 0x80) return value;
        shift += 7;
      }
    }

    String? source;
    String? destination;
    String? namespace;
    var payload = '';
    try {
      while (i < bytes.length) {
        final key = varint();
        final field = key >> 3;
        switch (key & 7) {
          case 0:
            varint();
          case 1:
            i += 8;
          case 5:
            i += 4;
          case 2:
            final length = varint();
            if (length < 0 || i + length > bytes.length) throw const FormatException('for kort');
            final text = utf8.decode(bytes.sublist(i, i + length), allowMalformed: true);
            i += length;
            switch (field) {
              case 2:
                source = text;
              case 3:
                destination = text;
              case 4:
                namespace = text;
              case 6:
                payload = text;
            }
          default:
            return null;
        }
      }
    } on FormatException {
      return null;
    }
    if (source == null || destination == null || namespace == null) return null;
    return CastMessage(source: source, destination: destination, namespace: namespace, payload: payload);
  }

  static void _varint(BytesBuilder b, int value) {
    var v = value;
    while (v >= 0x80) {
      b.addByte((v & 0x7f) | 0x80);
      v >>= 7;
    }
    b.addByte(v);
  }

  static void _string(BytesBuilder b, int field, String text) {
    final bytes = utf8.encode(text);
    b.addByte((field << 3) | 2);
    _varint(b, bytes.length);
    b.add(bytes);
  }

  @override
  String toString() => '$namespace $source→$destination $payload';
}

/// Meldingen med lengden (fire byte, stor ende først) foran, slik den sendes.
Uint8List frameMessage(CastMessage message) {
  final body = message.encode();
  final out = Uint8List(4 + body.length);
  ByteData.view(out.buffer).setUint32(0, body.length);
  out.setRange(4, out.length, body);
  return out;
}

/// Samler bytene fra forbindelsen og gir hele meldinger etter hvert som de kommer (en melding kan komme i flere
/// biter, og flere meldinger i én bit).
class CastFrameReader {
  final List<int> _pending = [];

  /// Største melding som godtas (Chromecasten sender små JSON-meldinger).
  static const maxMessage = 1 << 20;

  List<CastMessage> add(List<int> chunk) {
    _pending.addAll(chunk);
    final out = <CastMessage>[];
    while (_pending.length >= 4) {
      final length = (_pending[0] << 24) | (_pending[1] << 16) | (_pending[2] << 8) | _pending[3];
      if (length > maxMessage) {
        _pending.clear();
        throw const FormatException('for stor melding fra Chromecasten');
      }
      if (_pending.length < 4 + length) break;
      final message = CastMessage.decode(_pending.sublist(4, 4 + length));
      _pending.removeRange(0, 4 + length);
      if (message != null) out.add(message);
    }
    return out;
  }
}
