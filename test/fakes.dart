import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:fyrlys/core/models.dart';
import 'package:fyrlys/core/source.dart';
import 'package:fyrlys/ui/playback.dart';

/// En kilde uten nett, med tre kanaler i to kategorier. NRK 1 har program nå og etterpå.
class FakeSource implements TvSource {
  FakeSource({this.busy = const {}});

  /// kanaler der alle tilkoblingene er i bruk, til man tar over
  final Set<String> busy;
  final opened = <String>[];
  final closed = <String>[];

  @override
  String get kind => 'fake';

  @override
  String get label => 'Test';

  @override
  Map<String, String> get httpHeaders => const {};

  @override
  bool get sharedFavorites => false;

  @override
  Future<void> prepare() async {}

  @override
  Future<Account> account() async => const Account();

  @override
  Future<List<Category>> categories({bool force = false}) async =>
      const [Category(id: '1', name: 'Norge'), Category(id: '2', name: 'Sport')];

  @override
  Future<List<Channel>> channels({bool force = false}) async => const [
        Channel(id: '101', name: 'NRK 1 HD', categoryId: '1', number: '1'),
        Channel(id: '102', name: 'TV 2 HD', categoryId: '1', number: '2'),
        Channel(id: '103', name: '15:00 Man United - Bournemouth | Premier League', categoryId: '2', hasEpg: false),
      ];

  @override
  Future<List<EpgEntry>> epg(String channelId) async {
    if (channelId != '101') return const [];
    final now = DateTime.now();
    return [
      EpgEntry(
        title: 'Dagsrevyen',
        start: now.subtract(const Duration(minutes: 10)),
        stop: now.add(const Duration(minutes: 20)),
        description: 'Nyheter fra inn- og utland.',
      ),
      EpgEntry(
        title: 'Sportsrevyen',
        start: now.add(const Duration(minutes: 20)),
        stop: now.add(const Duration(minutes: 45)),
      ),
    ];
  }

  @override
  String? logoUrl(String? icon) => null;

  @override
  Future<PlayTarget> open(Channel channel, {bool takeOver = false}) async {
    if (busy.contains(channel.id) && !takeOver) {
      throw const BusyException('Alle tilkoblingene er i bruk.', ['NRK 1 HD']);
    }
    opened.add(channel.id);
    return PlayTarget(['http://example/${channel.id}.ts']);
  }

  @override
  Future<void> close(Channel channel) async => closed.add(channel.id);

  @override
  Future<Favorites?> loadFavorites() async => null;

  @override
  Future<Favorites?> changeFavorites(Map<String, Object?> change) async => null;

  @override
  Map<String, String> toPrefs() => const {'kind': 'fake'};

  @override
  void dispose() {}
}

/// En avspiller uten mpv: husker adressene og volumet, og «spiller» med en gang.
class FakePlayback implements Playback {
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _error = StreamController<String>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _height = StreamController<int?>.broadcast();

  final urls = <String>[];
  double volume = 100;
  bool playing = false;
  bool disposed = false;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<bool> get bufferingStream => _buffering.stream;

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<String> get errorStream => _error.stream;

  @override
  Stream<bool> get completedStream => _completed.stream;

  @override
  Stream<int?> get heightStream => _height.stream;

  @override
  Duration get position => Duration.zero;

  @override
  Future<void> setup() async {}

  @override
  Future<void> open(String url, Map<String, String> headers) async {
    urls.add(url);
    playing = true;
    _buffering.add(false);
    _playing.add(true);
    _height.add(1080);
  }

  @override
  Future<void> stop() async {
    playing = false;
    _playing.add(false);
  }

  @override
  Future<void> playOrPause() async {
    playing = !playing;
    _playing.add(playing);
  }

  @override
  Future<void> setVolume(double v) async => volume = v;

  @override
  List<TrackChoice> audioTracks() => const [];

  @override
  List<TrackChoice> subtitleTracks() => const [TrackChoice('Av', selected: true, value: 'no')];

  @override
  Future<void> selectTrack(TrackChoice choice) async {}

  @override
  Future<String> describe() async => 'H.264 · AAC stereo';

  @override
  Widget view() => const ColoredBox(color: Color(0xFF000000));

  @override
  Future<void> dispose() async {
    disposed = true;
    for (final c in [_playing, _buffering, _position, _error, _completed, _height]) {
      await c.close();
    }
  }
}
