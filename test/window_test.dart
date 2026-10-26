import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fyrlys/core/single_instance.dart';
import 'package:fyrlys/ui/window_memory.dart';

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
