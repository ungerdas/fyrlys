import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../l10n/tr.dart';
import 'cast_protocol.dart';
import 'cast_proxy.dart';
import 'caster.dart';
import 'mdns.dart';

class _Pending {
  _Pending(this.namespace, this.id, this.until, this.completer);

  final String namespace;
  final int id;
  final bool Function(CastMessage message)? until;
  final Completer<CastMessage> completer;
  Timer? timer;

  bool matches(CastMessage m) =>
      m.namespace == namespace && (until != null ? until!(m) : m.requestId == id);
}

/// Åpner forbindelsen til en Chromecast (testene bruker en vanlig socket).
typedef CastSocketFactory = Future<Socket> Function(String host, int port);

/// TLS til Chromecasten: den har et selvsignert sertifikat.
Future<Socket> chromecastSocket(String host, int port) =>
    SecureSocket.connect(host, port, onBadCertificate: (_) => true, timeout: const Duration(seconds: 8));

/// Forbindelsen til én Chromecast: TLS til port 8009 (Chromecasten har et selvsignert sertifikat), meldinger fram
/// og tilbake, og hjerteslag hvert femte sekund. Kommer det ingenting på 20 sekunder, regnes den som borte.
class CastConnection {
  CastConnection._(this._socket) {
    _socket.listen(_onData, onDone: _onDone, onError: (Object _) => _onDone(), cancelOnError: true);
    // skriving til en forbindelse Chromecasten har brutt, feiler her (og ellers som en uventet feil i appen)
    unawaited(_socket.done.then<void>((_) {}, onError: (Object _) => _onDone()));
    _ping = Timer.periodic(const Duration(seconds: 5), (_) {
      if (DateTime.now().difference(_heard) > const Duration(seconds: 20)) {
        debugPrint('Chromecast: ingen svar på 20 s');
        _onDone();
        return;
      }
      send(nsHeartbeat, {'type': 'PING'});
    });
  }

  static Future<CastConnection> open(String host, int port, {CastSocketFactory? connect}) async =>
      CastConnection._(await (connect ?? chromecastSocket)(host, port));

  /// avsenderen i meldingene våre
  static const sender = 'sender-fyrlys';

  final Socket _socket;
  final CastFrameReader _reader = CastFrameReader();
  final List<_Pending> _pending = [];
  Timer? _ping;
  DateTime _heard = DateTime.now();
  int _nextId = 1;
  bool _closed = false;

  /// alle meldinger (unntatt hjerteslagene)
  void Function(CastMessage message)? onMessage;

  /// forbindelsen ble brutt (ikke når [close] kalles)
  void Function()? onLost;

  /// PC-ens adresse slik Chromecasten ser den (der mellomstasjonen lytter)
  InternetAddress get localAddress => _socket.address;

  bool get closed => _closed;

  void _onData(List<int> data) {
    final List<CastMessage> messages;
    try {
      messages = _reader.add(data);
    } on FormatException catch (e) {
      debugPrint('Chromecast: $e');
      _onDone();
      return;
    }
    for (final m in messages) {
      _heard = DateTime.now();
      if (m.namespace == nsHeartbeat) {
        if (m.type == 'PING') send(nsHeartbeat, {'type': 'PONG'}, to: m.source);
        continue;
      }
      for (final p in List.of(_pending)) {
        if (p.matches(m)) {
          _pending.remove(p);
          p.timer?.cancel();
          if (!p.completer.isCompleted) p.completer.complete(m);
        }
      }
      onMessage?.call(m);
    }
  }

  void _onDone() {
    if (_closed) return;
    _shutdown();
    onLost?.call();
  }

  void _shutdown() {
    _closed = true;
    _ping?.cancel();
    for (final p in _pending) {
      p.timer?.cancel();
      if (!p.completer.isCompleted) p.completer.completeError(const SocketException('Chromecasten koblet fra'));
    }
    _pending.clear();
    _socket.destroy();
  }

  void send(String namespace, Map<String, Object?> json, {String to = 'receiver-0'}) {
    if (_closed) return;
    try {
      _socket.add(frameMessage(
        CastMessage(source: sender, destination: to, namespace: namespace, payload: jsonEncode(json)),
      ));
    } on Object catch (e) {
      debugPrint('Chromecast: sending feilet ($e)');
    }
  }

  /// Sender [json] med et nytt requestId uten å vente på svaret.
  void notify(String namespace, Map<String, Object?> json, {String to = 'receiver-0'}) =>
      send(namespace, {...json, 'requestId': _nextId++}, to: to);

  /// Sender [json] med et nytt requestId og venter på svaret (eller på en melding [until] godtar).
  Future<CastMessage> request(
    String namespace,
    Map<String, Object?> json, {
    String to = 'receiver-0',
    bool Function(CastMessage message)? until,
    Duration timeout = const Duration(seconds: 15),
  }) {
    if (_closed) return Future.error(const SocketException('Chromecasten koblet fra'));
    final id = _nextId++;
    final pending = _Pending(namespace, id, until, Completer<CastMessage>());
    pending.timer = Timer(timeout, () {
      _pending.remove(pending);
      if (!pending.completer.isCompleted) pending.completer.completeError(TimeoutException('Chromecast', timeout));
    });
    _pending.add(pending);
    send(namespace, {...json, 'requestId': id}, to: to);
    return pending.completer.future;
  }

  /// Lukker forbindelsen (sier fra til Chromecasten først).
  Future<void> close() async {
    if (_closed) return;
    send(nsConnection, {'type': 'CLOSE'});
    try {
      await _socket.flush().timeout(const Duration(seconds: 1));
    } on Object {
      // lukkes uansett
    }
    _shutdown();
  }
}

/// Avspilleren på TV-en (appen [defaultMediaReceiver]) i en melding om Chromecasten.
({String transportId, String sessionId})? receiverApp(CastMessage m) {
  final status = m.json['status'];
  if (status is! Map) return null;
  final apps = status['applications'];
  if (apps is! List) return null;
  for (final app in apps) {
    if (app is Map && app['appId'] == defaultMediaReceiver && app['transportId'] is String) {
      return (transportId: app['transportId'] as String, sessionId: '${app['sessionId'] ?? ''}');
    }
  }
  return null;
}

/// Google Cast til en Chromecast, med Googles egen avspiller og mellomstasjonen på PC-en.
class ChromecastCaster extends Caster {
  ChromecastCaster({Stream<CastDevice> Function()? discovery, CastSocketFactory? socket})
      : _discovery = discovery ?? discoverCastDevices,
        _socket = socket ?? chromecastSocket;

  final Stream<CastDevice> Function() _discovery;
  final CastSocketFactory _socket;

  CastConnection? _conn;
  CastProxy? _proxy;
  String? _transportId;
  String? _sessionId;
  int? _mediaSessionId;

  /// øker for hver tilkobling og hver ny avspilling, så svar på det gamle ikke blandes inn
  int _connectSeq = 0;
  int _loadSeq = 0;

  CastDevice? _device;
  CastState _state = CastState.off;
  String? _error;
  CastItem? _item;
  Duration _position = Duration.zero;
  DateTime _positionAt = DateTime.now();
  Duration? _duration;
  double _volume = 1;
  bool _muted = false;

  @override
  CastDevice? get device => _device;

  @override
  CastState get state => _state;

  @override
  String? get error => _error;

  @override
  CastItem? get item => _item;

  @override
  Duration get position {
    if (_state != CastState.playing) return _position;
    final p = _position + DateTime.now().difference(_positionAt);
    final d = _duration;
    return d != null && p > d ? d : p;
  }

  @override
  Duration? get duration => _duration;

  @override
  double get volume => _volume;

  @override
  bool get muted => _muted;

  @override
  Stream<CastDevice> discover() => _discovery();

  void _set(CastState state, {String? error}) {
    _state = state;
    _error = error;
    notifyListeners();
  }

  @override
  Future<void> connect(CastDevice device) async {
    await _disconnect(stopApp: false);
    final seq = ++_connectSeq;
    _device = device;
    _item = null;
    _set(CastState.connecting);
    try {
      final conn = await CastConnection.open(device.host, device.port, connect: _socket);
      if (seq != _connectSeq) {
        await conn.close();
        return;
      }
      _conn = conn;
      conn
        ..onMessage = _onMessage
        ..onLost = _onLost;
      conn.send(nsConnection, {'type': 'CONNECT'});
      final reply = await conn.request(
        nsReceiver,
        {'type': 'LAUNCH', 'appId': defaultMediaReceiver},
        until: (m) => receiverApp(m) != null || (m.type == 'LAUNCH_ERROR' || m.type == 'INVALID_REQUEST'),
        timeout: const Duration(seconds: 20),
      );
      if (seq != _connectSeq) return;
      final app = receiverApp(reply);
      if (app == null) {
        throw StateError('${reply.type} ${reply.json['reason'] ?? ''}');
      }
      _readVolume(reply);
      _transportId = app.transportId;
      _sessionId = app.sessionId;
      conn.send(nsConnection, {'type': 'CONNECT'}, to: app.transportId);
      final proxy = CastProxy();
      await proxy.start(conn.localAddress.address);
      if (seq != _connectSeq) {
        await proxy.close();
        return;
      }
      _proxy = proxy;
      debugPrint('Chromecast: koblet til ${device.model} (mellomstasjon på port ${proxy.port})');
      _set(CastState.ready);
    } on Object catch (e) {
      if (seq != _connectSeq) return;
      debugPrint('Chromecast: kunne ikke koble til ($e)');
      await _disconnect(stopApp: false);
      _device = null;
      _set(CastState.off, error: tr('Fikk ikke kontakt med {name}. Er den på og på samme nettverk som PC-en?',
          {'name': device.name}));
      rethrow;
    }
  }

  @override
  Future<void> load(CastItem item) async {
    final conn = _conn;
    final proxy = _proxy;
    final transport = _transportId;
    if (conn == null || proxy == null || transport == null) {
      throw StateError('ikke koblet til en Chromecast');
    }
    final seq = ++_loadSeq;
    _item = item;
    _mediaSessionId = null;
    _position = item.start;
    _positionAt = DateTime.now();
    _duration = null;
    _set(CastState.loading);
    final before = proxy.requests;
    final local = proxy.add(item.url, item.headers);
    final image = item.image;
    final media = <String, Object?>{
      'contentId': local,
      'contentUrl': local,
      'streamType': item.live ? 'LIVE' : 'BUFFERED',
      'contentType': item.contentType,
      'metadata': {
        'metadataType': 0,
        'title': item.title,
        if (item.subtitle.isNotEmpty) 'subtitle': item.subtitle,
        if (image != null && image.isNotEmpty)
          'images': [
            {'url': image},
          ],
      },
      // IPTV-leverandørene sender HLS med MPEG-TS-segmenter
      if (item.isHls) 'hlsSegmentFormat': 'ts',
      if (item.isHls) 'hlsVideoSegmentFormat': 'mpeg2_ts',
    };
    final CastMessage reply;
    try {
      reply = await conn.request(
        nsMedia,
        {
          'type': 'LOAD',
          'sessionId': _sessionId,
          'media': media,
          'autoplay': true,
          'currentTime': item.start.inMilliseconds / 1000,
        },
        to: transport,
        timeout: const Duration(seconds: 45),
      );
    } on Object catch (e) {
      if (seq != _loadSeq || !active) return;
      debugPrint('Chromecast: LOAD svarte ikke ($e)');
      _set(CastState.failed, error: _loadError(proxy, before));
      return;
    }
    if (seq != _loadSeq) return;
    if (reply.type == 'MEDIA_STATUS') {
      _onMediaStatus(reply);
      return;
    }
    // LOAD_FAILED, LOAD_CANCELLED eller INVALID_REQUEST
    if (reply.type == 'LOAD_CANCELLED') return;
    debugPrint('Chromecast: ${reply.type} ${reply.json['reason'] ?? ''} ${reply.json['detailedErrorCode'] ?? ''}');
    _set(CastState.failed, error: _loadError(proxy, before));
  }

  String _loadError(CastProxy proxy, int before) {
    if (proxy.requests == before) {
      return tr('Chromecasten fikk ikke hentet strømmen fra PC-en. Har Windows-brannmuren stoppet Fyrlys? '
          'Tillat Fyrlys på private nettverk, og prøv igjen.');
    }
    return tr('Chromecasten kunne ikke spille dette. Den spiller HLS med H.264 og AAC; noen kanaler sendes på en måte '
        'den ikke støtter.');
  }

  void _media(String type, [Map<String, Object?> extra = const {}]) {
    final conn = _conn;
    final transport = _transportId;
    final id = _mediaSessionId;
    if (conn == null || transport == null || id == null) return;
    unawaited(conn
        .request(nsMedia, {'type': type, 'mediaSessionId': id, ...extra}, to: transport)
        .then<void>((_) {}, onError: (Object e) => debugPrint('Chromecast: $type svarte ikke ($e)')));
  }

  @override
  Future<void> play() async => _media('PLAY');

  @override
  Future<void> pause() async => _media('PAUSE');

  @override
  Future<void> seek(Duration position) async {
    _position = position;
    _positionAt = DateTime.now();
    notifyListeners();
    _media('SEEK', {'currentTime': position.inMilliseconds / 1000});
  }

  @override
  Future<void> setVolume(double level) async {
    _volume = level.clamp(0.0, 1.0).toDouble();
    if (_volume > 0) _muted = false;
    notifyListeners();
    _conn?.notify(nsReceiver, {
      'type': 'SET_VOLUME',
      'volume': {'level': _volume},
    });
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    notifyListeners();
    _conn?.notify(nsReceiver, {
      'type': 'SET_VOLUME',
      'volume': {'muted': muted},
    });
  }

  @override
  Future<void> stop() async {
    _connectSeq++;
    _loadSeq++;
    await _disconnect(stopApp: true);
    final had = _device != null;
    _device = null;
    _item = null;
    if (had || _state != CastState.off) _set(CastState.off);
  }

  Future<void> _disconnect({required bool stopApp}) async {
    final conn = _conn;
    final proxy = _proxy;
    final session = _sessionId;
    _conn = null;
    _proxy = null;
    _transportId = null;
    _sessionId = null;
    _mediaSessionId = null;
    if (conn != null) {
      conn
        ..onMessage = null
        ..onLost = null;
      if (stopApp && session != null && session.isNotEmpty) {
        conn.notify(nsReceiver, {'type': 'STOP', 'sessionId': session});
      }
      await conn.close();
    }
    await proxy?.close();
  }

  void _onLost() {
    final name = _device?.name ?? '';
    unawaited(_disconnect(stopApp: false));
    _device = null;
    _item = null;
    _set(CastState.off, error: tr('Mistet kontakten med {name}.', {'name': name}));
  }

  void _readVolume(CastMessage m) {
    final status = m.json['status'];
    if (status is! Map) return;
    final volume = status['volume'];
    if (volume is! Map) return;
    final level = volume['level'];
    if (level is num) _volume = level.toDouble().clamp(0.0, 1.0).toDouble();
    if (volume['muted'] is bool) _muted = volume['muted'] as bool;
  }

  void _onMessage(CastMessage m) {
    switch (m.namespace) {
      case nsReceiver when m.type == 'RECEIVER_STATUS':
        _readVolume(m);
        final app = receiverApp(m);
        // avspilleren vår er borte fra TV-en (stoppet med fjernkontrollen, eller noen andre caster)
        if (_state != CastState.connecting && _sessionId != null && (app == null || app.sessionId != _sessionId)) {
          final name = _device?.name ?? '';
          unawaited(_disconnect(stopApp: false));
          _device = null;
          _item = null;
          _set(CastState.off, error: tr('Castingen til {name} ble stoppet.', {'name': name}));
          return;
        }
        notifyListeners();
      case nsMedia when m.type == 'MEDIA_STATUS':
        _onMediaStatus(m);
      case nsConnection when m.type == 'CLOSE' && m.source == _transportId:
        _onLost();
    }
  }

  void _onMediaStatus(CastMessage m) {
    final list = m.json['status'];
    if (list is! List || list.isEmpty || list.first is! Map) return;
    final status = Map<String, Object?>.from(list.first as Map);
    final id = status['mediaSessionId'];
    if (id is int) _mediaSessionId = id;
    final time = status['currentTime'];
    if (time is num) {
      _position = Duration(milliseconds: (time * 1000).round());
      _positionAt = DateTime.now();
    }
    final media = status['media'];
    if (media is Map && media['duration'] is num) {
      final d = (media['duration'] as num).toDouble();
      _duration = d > 0 ? Duration(milliseconds: (d * 1000).round()) : null;
    }
    final volume = status['volume'];
    if (volume is Map && volume['level'] is num) _volume = (volume['level'] as num).toDouble().clamp(0.0, 1.0).toDouble();
    switch (status['playerState']) {
      case 'PLAYING':
        _set(CastState.playing);
      case 'PAUSED':
        _set(CastState.paused);
      case 'BUFFERING':
      case 'LOADING':
        _set(_state == CastState.loading ? CastState.loading : CastState.buffering);
      case 'IDLE':
        switch (status['idleReason']) {
          case 'FINISHED':
            _set(CastState.ended);
          case 'ERROR':
            _set(CastState.failed, error: tr('Chromecasten stoppet avspillingen (feil i strømmen).'));
          default:
            // avbrutt av en ny avspilling, eller ingenting lastet ennå
            notifyListeners();
        }
      default:
        notifyListeners();
    }
  }
}
