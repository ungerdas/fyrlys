import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Bare én Fyrlys om gangen. Den første lytter på en lokal port (bare på denne maskinen); starter du Fyrlys en gang
/// til, ber den nye den første om å vise vinduet sitt og avslutter selv. Svarer noe annet enn Fyrlys på porten,
/// starter appen som vanlig.
class SingleInstance {
  SingleInstance._();

  static const defaultPort = 47853;
  static const _hello = 'fyrlys:vis';
  static const _ok = 'fyrlys:ok';

  static ServerSocket? _server;

  /// true: en annen Fyrlys kjører og er bedt om å vise seg, så denne skal avslutte. Ellers lytter denne (eller
  /// porten er tatt av noe annet), og [onShow] kalles når en ny start ber om det.
  static Future<bool> isSecond({required void Function() onShow, int port = defaultPort}) async {
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      _server = server;
      server.listen((socket) {
        socket.listen(
          (data) {
            if (!utf8.decode(data, allowMalformed: true).contains(_hello)) return;
            socket.write('$_ok\n');
            unawaited(socket.flush().then((_) => socket.close(), onError: (Object _) => socket.destroy()));
            onShow();
          },
          onError: (Object _) => socket.destroy(),
          cancelOnError: true,
        );
      });
      return false;
    } on SocketException {
      return _askOther(port);
    }
  }

  /// Svarer Fyrlys på porten? Da har den fått beskjed om å vise seg.
  static Future<bool> _askOther(int port) async {
    Socket? socket;
    try {
      socket = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(seconds: 2));
      socket.write('$_hello\n');
      await socket.flush();
      final reply = await socket
          .timeout(const Duration(seconds: 2))
          .map((data) => utf8.decode(data, allowMalformed: true))
          .firstWhere((text) => text.contains(_ok), orElse: () => '');
      return reply.contains(_ok);
    } on Object {
      return false;
    } finally {
      socket?.destroy();
    }
  }

  /// Slutter å lytte (testene).
  static Future<void> release() async {
    await _server?.close();
    _server = null;
  }
}
