import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

/// Krypterer det som lagres om innloggingen (Xtream-passordet, eller M3U-lenken med brukernavn og passord i), så
/// bare din Windows-bruker på denne PC-en kan lese det. Kan den ikke kryptere, gir den null, og innloggingen lagres
/// som før.
abstract class SecretCodec {
  const SecretCodec();

  /// DPAPI på Windows; ellers (testene) ingen kryptering
  factory SecretCodec.platform() => Platform.isWindows ? const DpapiCodec() : const NoSecretCodec();

  /// teksten kryptert (base64), eller null når det ikke går
  String? protect(String text);

  /// teksten igjen, eller null når den ikke kan leses (f.eks. en annen bruker eller en annen PC)
  String? unprotect(String protected);
}

/// Ingen kryptering: innloggingen lagres som den er.
class NoSecretCodec extends SecretCodec {
  const NoSecretCodec();

  @override
  String? protect(String text) => null;

  @override
  String? unprotect(String protected) => null;
}

/// DATA_BLOB i crypt32
final class _Blob extends Struct {
  @Uint32()
  external int size;

  external Pointer<Uint8> data;
}

// CryptProtectData og CryptUnprotectData har samme form; beskrivelsen (2. argument) brukes ikke (nullptr).
typedef _CryptNative = Int32 Function(Pointer<_Blob> input, Pointer<Void> description, Pointer<_Blob> entropy,
    Pointer<Void> reserved, Pointer<Void> prompt, Uint32 flags, Pointer<_Blob> output);
typedef _CryptDart = int Function(Pointer<_Blob> input, Pointer<Void> description, Pointer<_Blob> entropy,
    Pointer<Void> reserved, Pointer<Void> prompt, int flags, Pointer<_Blob> output);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> memory);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> memory);

/// Windows' egen kryptering for brukerdata (DPAPI, CryptProtectData), knyttet til Windows-brukeren.
class DpapiCodec extends SecretCodec {
  const DpapiCodec();

  /// CRYPTPROTECT_UI_FORBIDDEN: aldri spør brukeren om noe
  static const _uiForbidden = 0x1;

  Uint8List? _run(String function, List<int> bytes) {
    final crypt32 = DynamicLibrary.open('crypt32.dll');
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final call = crypt32.lookupFunction<_CryptNative, _CryptDart>(function);
    final localFree = kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');
    final data = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
    final input = calloc<_Blob>();
    final output = calloc<_Blob>();
    try {
      data.asTypedList(bytes.length).setAll(0, bytes);
      input.ref
        ..size = bytes.length
        ..data = data;
      if (call(input, nullptr, nullptr, nullptr, nullptr, _uiForbidden, output) == 0) return null;
      final result = Uint8List.fromList(output.ref.data.asTypedList(output.ref.size));
      localFree(output.ref.data.cast());
      return result;
    } finally {
      calloc.free(data);
      calloc.free(input);
      calloc.free(output);
    }
  }

  @override
  String? protect(String text) {
    try {
      final bytes = _run('CryptProtectData', utf8.encode(text));
      return bytes == null ? null : base64Encode(bytes);
    } on Object {
      return null;
    }
  }

  @override
  String? unprotect(String protected) {
    try {
      final bytes = _run('CryptUnprotectData', base64Decode(protected));
      return bytes == null ? null : utf8.decode(bytes);
    } on Object {
      return null;
    }
  }
}
