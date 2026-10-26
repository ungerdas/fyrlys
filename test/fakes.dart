import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:fyrlys/core/languages.dart';
import 'package:fyrlys/core/models.dart';
import 'package:fyrlys/core/source.dart';
import 'package:fyrlys/core/vod.dart';
import 'package:fyrlys/ui/playback.dart';

/// En kilde uten nett, med tre kanaler i to kategorier. NRK 1 har program nå og etterpå.
class FakeSource implements TvSource {
  FakeSource({this.busy = const {}, this.timeshift = Duration.zero, this.window, this.direct = false});

  /// kanaler der alle tilkoblingene er i bruk, til man tar over
  final Set<String> busy;

  /// tilbakespoling i direktesendingen (som Fyrlys-serveren), og spillelista liveWindow gir
  final Duration timeshift;
  LiveWindow? window;
  final windowRequests = <String>[];

  /// som når noen andre tar over tilkoblingen mens du har pauset
  bool takenOver = false;

  /// som Fyrlys-serveren med direkte avspilling: strømmen uendret, appen spoler selv og sier fra hvert 10. sekund
  final bool direct;
  int beats = 0;
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
  Future<List<EpgEntry>> epg(String channelId, {int limit = 6}) async {
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
    return PlayTarget(
      ['http://example/${channel.id}.ts'],
      timeshift: timeshift,
      keepAlive: direct ? 'http://example/beat/${channel.id}' : null,
      localShift: direct,
    );
  }

  @override
  Future<void> stillWatching(PlayTarget target) async {
    beats++;
    if (takenOver) throw const BusyException('Alle tilkoblingene er i bruk.', ['Stua']);
  }

  @override
  String redact(String text) => text.replaceAll('hemmelig', '***');

  @override
  Future<LiveWindow?> liveWindow(String url) async {
    windowRequests.add(url);
    if (takenOver) throw const BusyException('Alle tilkoblingene er i bruk.', ['Stua']);
    return window;
  }

  @override
  Future<void> close(Channel channel) async => closed.add(channel.id);

  @override
  Future<Favorites?> loadFavorites() async => null;

  @override
  Future<Favorites?> changeFavorites(Map<String, Object?> change) async => null;

  // ── filmer og serier ──

  static const movieCategories = [VodCategory(id: '11', name: 'Action'), VodCategory(id: '12', name: 'Komedie')];
  static const movies = [
    VodItem(id: '201', name: 'Fyrlyset', categoryId: '11', ext: 'mkv', rating: 7.5, year: '2024', added: 3),
    VodItem(id: '202', name: 'Nordlys', categoryId: '12', rating: 6, added: 5),
    VodItem(id: '203', name: 'Havet', categoryId: '11', added: 1),
  ];
  static const seriesCategories = [VodCategory(id: '21', name: 'Norske serier')];
  static const series = [VodItem(id: '301', name: 'Kystvakten', categoryId: '21', year: '2023', rating: 8)];

  final pageRequests = <String>[];

  @override
  Future<VodCatalog> vodCatalog(VodKind kind, {bool force = false}) async => kind == VodKind.movies
      ? catalogOf(movieCategories, movies)
      : catalogOf(seriesCategories, series);

  @override
  Future<VodPage> vodPage(VodKind kind,
      {String category = '', String query = '', VodSort sort = VodSort.provider, int start = 0}) async {
    pageRequests.add('${kind.api}:$category:$query:${sort.api}:$start');
    return pageOf(kind == VodKind.movies ? movies : series, category: category, query: query, sort: sort, start: start);
  }

  @override
  Future<MovieInfo> movieInfo(String id) async => const MovieInfo(
        plot: 'En film om et fyr.',
        genre: 'Drama',
        year: '2024',
        duration: '01:45:00',
        cast: 'Kari Nordmann',
        director: 'Ola Nordmann',
      );

  @override
  Future<SeriesInfo> seriesInfo(String id) async => const SeriesInfo(
        name: 'Kystvakten',
        plot: 'Livet langs kysten.',
        genre: 'Drama',
        year: '2023',
        seasons: [
          Season(number: '1', episodes: [
            Episode(id: '401', title: 'Første', number: 1, ext: 'mkv', plot: 'Det begynner.', duration: '00:45:00'),
            Episode(id: '402', title: 'Andre', number: 2),
          ]),
          Season(number: '2', episodes: [Episode(id: '403', title: 'Tredje', number: 1)]),
        ],
      );

  @override
  String movieUrl(VodItem movie) => 'http://example/movie/${movie.id}.${movie.ext}';

  @override
  String episodeUrl(Episode episode) => 'http://example/series/${episode.id}.${episode.ext}';

  @override
  Map<String, String> toPrefs() => const {'kind': 'fake'};

  @override
  void dispose() {}
}

/// En avspiller uten mpv: husker adressene og volumet, og «spiller» med en gang.
class FakePlayback implements Playback {
  /// sender posisjonen, som om filmen spiller
  void moveTo(Duration p) => _position.add(p);

  /// som når filmen er ferdig
  void finish() => _completed.add(true);

  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _error = StreamController<String>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _height = StreamController<int?>.broadcast();
  final _duration = StreamController<Duration>.broadcast();

  final urls = <String>[];
  final starts = <Duration?>[];
  final seeks = <Duration>[];

  /// hvor langt fra slutten hver direktesending ble åpnet (null: som vanlig)
  final liveFromEnds = <int?>[];

  /// lengden filene får (null: direktesending)
  Duration? length;
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
  Stream<Duration> get durationStream => _duration.stream;

  @override
  Duration get position => Duration.zero;

  @override
  Duration get duration => length ?? Duration.zero;

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  /// [setup] for TV (bufferet for pause og spoling)
  bool live = false;

  /// det avspilleren «har tatt vare på» i en direktesending, og hoppene i det
  LiveCache? cache;
  final relativeSeeks = <Duration>[];

  @override
  Future<void> setup({bool live = false}) async => this.live = live;

  @override
  Future<LiveCache?> liveCache() async => cache;

  @override
  Future<void> seekBy(Duration delta) async {
    relativeSeeks.add(delta);
    // som mpv: det som er bak og foran, flytter seg like mye
    final c = cache;
    if (c != null) cache = (back: c.back + delta, ahead: c.ahead - delta);
  }

  @override
  Future<void> open(String url, Map<String, String> headers, {Duration? start, int? liveFromEnd}) async {
    urls.add(url);
    starts.add(start);
    liveFromEnds.add(liveFromEnd);
    final l = length;
    if (l != null) _duration.add(l);
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

  /// sporene filen eller kanalen har
  List<TrackChoice> audio = const [];
  List<TrackChoice> subtitles = const [TrackChoice('Av', selected: true, value: 'no')];
  final selected = <TrackChoice>[];

  /// språkene spilleren har fått, og om de skulle gjelde med en gang
  final languages = <(LanguagePrefs, bool)>[];

  @override
  Future<TrackList> tracks() async => (audio: audio, subtitles: subtitles);

  @override
  Future<void> selectTrack(TrackChoice choice) async => selected.add(choice);

  @override
  Future<void> setLanguages(LanguagePrefs prefs, {bool now = false}) async => languages.add((prefs, now));

  @override
  Future<String> describe() async => 'H.264 · AAC stereo';

  @override
  Widget view() => const ColoredBox(color: Color(0xFF000000));

  @override
  Future<void> dispose() async {
    disposed = true;
    for (final c in [_playing, _buffering, _position, _error, _completed, _height, _duration]) {
      await c.close();
    }
  }
}
