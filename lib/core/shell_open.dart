// Windows: åpner en nettadresse slik Windows selv gjør når du klikker en lenke (ShellExecuteW, som url_launcher).
// Ikke med explorer.exe: den åpnet mappen Dokumenter i stedet for innloggingssiden hos Plex, som har «#?» og «&» i
// adressen.

import 'dart:ffi';

import 'package:ffi/ffi.dart';

typedef _ShellExecuteNative = IntPtr Function(
  IntPtr hwnd,
  Pointer<Utf16> verb,
  Pointer<Utf16> file,
  Pointer<Utf16> parameters,
  Pointer<Utf16> directory,
  Int32 cmdShow,
);
typedef _ShellExecuteDart = int Function(
  int hwnd,
  Pointer<Utf16> verb,
  Pointer<Utf16> file,
  Pointer<Utf16> parameters,
  Pointer<Utf16> directory,
  int cmdShow,
);
typedef _CoInitializeExNative = Int32 Function(Pointer<Void> reserved, Uint32 flags);
typedef _CoInitializeExDart = int Function(Pointer<Void> reserved, int flags);
typedef _CoUninitializeNative = Void Function();
typedef _CoUninitializeDart = void Function();

/// SW_SHOWNORMAL
const _showNormal = 1;

/// COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE, som Microsoft anbefaler før ShellExecute
const _apartment = 0x2 | 0x4;

/// Åpner [target] (en nettadresse) med ShellExecuteW og «open». Gir svaret derfra: over 32 har det gått bra.
int shellOpen(String target) {
  final shell32 = DynamicLibrary.open('shell32.dll');
  final ole32 = DynamicLibrary.open('ole32.dll');
  final execute = shell32.lookupFunction<_ShellExecuteNative, _ShellExecuteDart>('ShellExecuteW');
  final init = ole32.lookupFunction<_CoInitializeExNative, _CoInitializeExDart>('CoInitializeEx');
  final uninit = ole32.lookupFunction<_CoUninitializeNative, _CoUninitializeDart>('CoUninitialize');
  final verb = 'open'.toNativeUtf16();
  final file = target.toNativeUtf16();
  // nettleseren kan bli startet via COM; er tråden alt satt opp, svarer CoInitializeEx S_FALSE (1), og hvert svar som
  // ikke er en feil, skal ha sin CoUninitialize
  final hr = init(nullptr, _apartment);
  try {
    return execute(0, verb, file, nullptr, nullptr, _showNormal);
  } finally {
    if (hr >= 0) uninit();
    malloc.free(verb);
    malloc.free(file);
  }
}
