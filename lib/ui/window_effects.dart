import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:ui' show Offset, Rect, Size;

import 'package:ffi/ffi.dart';
import 'package:screen_retriever/screen_retriever.dart';
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

  /// det vinduet sist ble bedt om (to spillere kan be om det samme; da gjøres ingenting, og det husker fortsatt om
  /// vinduet var maksimert)
  bool _on = false;

  Future<void> set(bool on) {
    if (on == _on) return _queue;
    _on = on;
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

/// Minispilleren: vinduet blir lite, uten tittellinje, nederst til høyre på skjermen det står på, og alltid øverst.
/// Størrelsen og plassen fra før (og om det var maksimert) kommer tilbake etterpå. Ett steg om gangen.
class MiniWindow {
  MiniWindow._();

  static final instance = MiniWindow._();

  static const size = Size(480, 270);
  static const _margin = 24.0;

  /// det vinduet sist ble bedt om (WindowMemory lagrer ikke størrelsen så lenge det er lite)
  bool get active => _on;
  bool _on = false;

  Rect? _bounds;
  bool _wasMaximized = false;
  Future<void> _queue = Future.value();

  Future<void> set(bool on) {
    if (on == _on) return _queue;
    _on = on;
    Future<void> step() async {
      try {
        if (on) {
          await WindowFullscreen.instance.set(false);
          _wasMaximized = await windowManager.isMaximized();
          if (_wasMaximized) await windowManager.unmaximize();
          final bounds = await windowManager.getBounds();
          _bounds = bounds;
          final area = await _workArea(bounds);
          await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
          await windowManager.setBounds(Rect.fromLTWH(
            area.right - size.width - _margin,
            area.bottom - size.height - _margin,
            size.width,
            size.height,
          ));
          await windowManager.setAlwaysOnTop(true);
        } else {
          await windowManager.setAlwaysOnTop(false);
          await windowManager.setTitleBarStyle(TitleBarStyle.normal);
          final bounds = _bounds;
          if (bounds != null) await windowManager.setBounds(bounds);
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

  /// Skjermen der midten av vinduet er (uten oppgavelinja), ellers hovedskjermen.
  static Future<Rect> _workArea(Rect window) async {
    Rect area(Display d) => (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size);
    for (final d in await screenRetriever.getAllDisplays()) {
      final a = area(d);
      if (a.contains(window.center)) return a;
    }
    return area(await screenRetriever.getPrimaryDisplay());
  }
}

/// Flytter vinduet med musa (minispilleren har ingen tittellinje).
void dragWindow() {
  try {
    windowManager.startDragging().ignore();
  } on Object {
    // ikke tilgjengelig her
  }
}
