import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/single_instance.dart';
import 'package:fyrlys/ui/window_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('vinduet: det som er lagret, leses tilbake, og noe ødelagt eller for lite gir standardplassen', () {
    final saved = WindowMemory.read('{"x": 100, "y": 50, "w": 1280, "h": 800, "max": false}');
    expect(saved.bounds, const Rect.fromLTWH(100, 50, 1280, 800));
    expect(saved.maximized, isFalse);
    expect(WindowMemory.read('{"x": 100, "y": 50, "w": 1280, "h": 800, "max": true}').maximized, isTrue);
    // maksimert uten vanlig størrelse fra før
    final max = WindowMemory.read('{"max": true}');
    expect(max.bounds, isNull);
    expect(max.maximized, isTrue);
    expect(WindowMemory.read('{"x": 0, "y": 0, "w": 200, "h": 100}').bounds, isNull);
    expect(WindowMemory.read('ikke json').bounds, isNull);
    expect(WindowMemory.read(null).maximized, isFalse);
  });

  test('maksimert sist: vinduet maksimeres først når Windows har vist det', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('window_manager');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    var visible = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return switch (call.method) {
        'isVisible' => visible,
        'isMaximized' || 'isFullScreen' || 'isMinimized' => false,
        _ => null,
      };
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    SharedPreferences.setMockInitialValues({'window': '{"x": 100, "y": 50, "w": 1280, "h": 800, "max": true}'});
    final memory = await WindowMemory.restore(await SharedPreferences.getInstance(), poll: const Duration(milliseconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    // Windows viser vinduet som et vanlig vindu når det første bildet er tegnet: maksimert før det, blir det vanlig
    expect(calls, contains('isVisible'));
    expect(calls, isNot(contains('maximize')));
    visible = true;
    await memory.ready;
    expect(calls.last, 'maximize');
  });

  group('bare én Fyrlys', () {
    final port = 40000 + Random().nextInt(20000);
    tearDown(SingleInstance.release);

    test('den andre ber den første vise seg og avslutter', () async {
      var shown = 0;
      expect(await SingleInstance.isSecond(onShow: () => shown++, port: port), isFalse);
      expect(await SingleInstance.isSecond(onShow: () => fail('den andre skal ikke lytte'), port: port), isTrue);
      expect(shown, 1);
    });

    test('noe annet på porten: starter som vanlig', () async {
      final other = await ServerSocket.bind(InternetAddress.loopbackIPv4, port + 1);
      // svarer ikke som Fyrlys
      other.listen((socket) => socket.listen((_) {}));
      addTearDown(other.close);
      expect(await SingleInstance.isSecond(onShow: () {}, port: port + 1), isFalse);
    });
  });
}
