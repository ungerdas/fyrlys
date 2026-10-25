import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:window_manager/window_manager.dart';

// Windows: animasjonene når vinduet maksimeres og gjenopprettes slås av mens Fyrlys går inn og ut av fullskjerm.
// Et maksimert vindu må gjøres vanlig før fullskjerm (se WindowFullscreen nederst), og uten dette krymper
// vinduet synlig og hopper så til fullskjerm.

typedef _FindWindowExNative = IntPtr Function(IntPtr parent, IntPtr after, Pointer<Utf16> cls, Pointer<Utf16> title);
typedef _FindWindowExDart = int Function(int parent, int after, Pointer<Utf16> cls, Pointer<Utf16> title);
typedef _ProcessIdNative = Uint32 Function(IntPtr hwnd, Pointer<Uint32> processId);
typedef _ProcessIdDart = int Function(int hwnd, Pointer<Uint32> processId);
typedef _DwmSetNative = Int32 Function(IntPtr hwnd, Uint32 attribute, Pointer<Int32> value, Uint32 size);
typedef _DwmSetDart = int Function(int hwnd, int attribute, Pointer<Int32> value, int size);

/// DWMWA_TRANSITIONS_FORCEDISABLED
const _transitionsForceDisabled = 3;

/// Flutter-vinduet til denne prosessen, eller 0.
int _mainWindow() {
  final user32 = DynamicLibrary.open('user32.dll');
  final findWindowEx = user32.lookupFunction<_FindWindowExNative, _FindWindowExDart>('FindWindowExW');
  final processIdOf = user32.lookupFunction<_ProcessIdNative, _ProcessIdDart>('GetWindowThreadProcessId');
  final cls = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
  final owner = calloc<Uint32>();
  try {
    var hwnd = 0;
    for (var i = 0; i < 64; i++) {
      hwnd = findWindowEx(0, hwnd, cls, nullptr);
      if (hwnd == 0) return 0;
      processIdOf(hwnd, owner);
      if (owner.value == pid) return hwnd;
    }
    return 0;
  } finally {
    malloc.free(cls);
    calloc.free(owner);
  }
}

void _setTransitions(int hwnd, {required bool disabled}) {
  final dwm = DynamicLibrary.open('dwmapi.dll');
  final setAttribute = dwm.lookupFunction<_DwmSetNative, _DwmSetDart>('DwmSetWindowAttribute');
  final value = calloc<Int32>()..value = disabled ? 1 : 0;
  try {
    setAttribute(hwnd, _transitionsForceDisabled, value, sizeOf<Int32>());
  } finally {
    calloc.free(value);
  }
}

/// Kjører [action] med vindusanimasjonene av (bare Windows; ellers kjøres den som den er).
Future<void> withoutWindowAnimations(Future<void> Function() action) async {
  var hwnd = 0;
  if (Platform.isWindows) {
    try {
      hwnd = _mainWindow();
      if (hwnd != 0) _setTransitions(hwnd, disabled: true);
    } on Object {
      hwnd = 0;
    }
  }
  try {
    await action();
  } finally {
    if (hwnd != 0) {
      // Windows gjør ferdig endringen etter at kallet har returnert; vent litt før animasjonene slås på igjen.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        _setTransitions(hwnd, disabled: false);
      } on Object {
        // animasjonene forblir av for dette vinduet
      }
    }
  }
}

/// Fullskjerm for vinduet på PC, felles for TV- og filmspilleren. window_manager (0.5.x) gjør et maksimert vindu
/// bare like stort som skjermen, med tittellinja igjen og bunnen bak oppgavelinja. Derfor gjøres vinduet vanlig
/// først, så fullskjerm, og det maksimeres igjen etterpå, uten animasjonene. Ett steg om gangen.
class WindowFullscreen {
  WindowFullscreen._();

  static final instance = WindowFullscreen._();

  bool _wasMaximized = false;
  Future<void> _queue = Future.value();

  Future<void> set(bool on) {
    Future<void> step() async {
      try {
        if (on) {
          _wasMaximized = await windowManager.isMaximized();
          if (_wasMaximized) await windowManager.unmaximize();
          await windowManager.setFullScreen(true);
        } else {
          await windowManager.setFullScreen(false);
          if (_wasMaximized) {
            _wasMaximized = false;
            await windowManager.maximize();
          }
        }
      } on Object {
        // ikke tilgjengelig her (f.eks. i testene)
      }
    }

    return _queue = _queue.then((_) => withoutWindowAnimations(step));
  }
}
