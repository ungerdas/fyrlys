import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/languages.dart';
import '../core/names.dart';
import '../platform.dart';

/// Et lydspor eller en undertekst man kan velge i spilleren.
class TrackChoice {
  const TrackChoice(this.label, {required this.selected, required this.value});

  final String label;
  final bool selected;

  /// sporet slik avspilleren kjenner det
  final Object value;
}

/// Lydsporene og undertekstene i det som spilles nå.
typedef TrackList = ({List<TrackChoice> audio, List<TrackChoice> subtitles});

/// Det avspilleren har tatt vare på av en direktesending: så langt tilbake fra der du er, og så mye foran (som er
/// hentet, men ikke vist ennå).
typedef LiveCache = ({Duration back, Duration ahead});

/// Avspilleren bak spilleren: mpv via media_kit i appen, en falsk i testene (mpv finnes ikke der).
abstract class Playback {
  Stream<bool> get playingStream;
  Stream<bool> get bufferingStream;
  Stream<Duration> get positionStream;
  Stream<String> get errorStream;
  Stream<bool> get completedStream;

  /// bildets høyde i piksler, når den er kjent
  Stream<int?> get heightStream;

  /// lengden på filmen (null/0 for direktesendinger)
  Stream<Duration> get durationStream;

  Duration get position;

  Duration get duration;

  Future<void> seek(Duration position);

  /// Innstillinger før første fil eller kanal åpnes. [live]: TV, der avspilleren tar vare på det siste (på
  /// disken når det går), så du kan pause og spole tilbake i direktesendingen.
  Future<void> setup({bool live = false});

  /// hvor mye av direktesendingen avspilleren har tatt vare på, rundt der du er (null: vet ikke)
  Future<LiveCache?> liveCache();

  /// hopp så langt fram (eller tilbake, negativt) i det avspilleren har tatt vare på
  Future<void> seekBy(Duration delta);

  /// [start]: hvor filmen skal begynne (fortsett der du slapp). [liveFromEnd]: direktesending, så mange
  /// segmenter fra slutten av spillelista (3 er direkte; flere er tilbake i tid).
  Future<void> open(String url, Map<String, String> headers, {Duration? start, int? liveFromEnd});

  Future<void> stop();

  Future<void> playOrPause();

  /// 0–100
  Future<void> setVolume(double volume);

  /// Sporene, med det som spilles nå huket av.
  Future<TrackList> tracks();

  Future<void> selectTrack(TrackChoice choice);

  /// Språkene du foretrekker. Gjelder neste fil eller kanal som åpnes, og med [now] også det som spilles nå.
  Future<void> setLanguages(LanguagePrefs prefs, {bool now = false});

  /// for feilsøking: kodek, dekoding og lyd, f.eks. «H.264 · maskinvaredekoding (d3d11va) · AC3 5.1»
  Future<String> describe();

  Widget view();

  Future<void> dispose();
}

/// Avspilleren appen bruker. Testene setter en falsk her (mpv finnes ikke i testene).
Playback Function() playbackFactory = MpvPlayback.new;

/// mpv via media_kit.
class MpvPlayback implements Playback {
  MpvPlayback() {
    _video = VideoController(_player);
  }

  final Player _player = Player();
  late final VideoController _video;

  @override
  Stream<bool> get playingStream => _player.stream.playing;

  @override
  Stream<bool> get bufferingStream => _player.stream.buffering;

  @override
  Stream<Duration> get positionStream => _player.stream.position;

  @override
  Stream<String> get errorStream => _player.stream.error;

  @override
  Stream<bool> get completedStream => _player.stream.completed;

  @override
  Stream<int?> get heightStream => _player.stream.height;

  @override
  Stream<Duration> get durationStream => _player.stream.duration;

  @override
  Duration get position => _player.state.position;

  @override
  Duration get duration => _player.state.duration;

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  /// mappen avspilleren kan legge bufferet for direktesendinger i (settes i main.dart; null: i minnet)
  static String? cacheDir;

  @override
  Future<void> setup({bool live = false}) async {
    final p = _player.platform;
    if (p is! NativePlayer) return;
    // Direktesending over nett: koble til igjen ved korte brudd, og ikke vent evig på en strøm som er død.
    await _try(() => p.setProperty('network-timeout', '20'));
    await _try(() => p.setProperty(
          'stream-lavf-o',
          'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,reconnect_delay_max=5',
        ));
    if (!live) return;
    // TV: det som er hentet, tas vare på (og det går an å hoppe i det, selv om strømmen selv ikke kan spoles).
    // På disken holder det til omtrent en halvtime på PC; ellers i minnet, og mindre.
    final dir = cacheDir;
    await _try(() => p.setProperty('cache', 'yes'));
    await _try(() => p.setProperty('demuxer-seekable-cache', 'yes'));
    if (dir != null) {
      await _try(() => p.setProperty('demuxer-cache-dir', dir));
      await _try(() => p.setProperty('cache-on-disk', 'yes'));
    }
    final disk = dir != null;
    await _try(() => p.setProperty('demuxer-max-back-bytes', disk ? (isDesktop ? '2000MiB' : '600MiB') : (isDesktop ? '400MiB' : '120MiB')));
    await _try(() => p.setProperty('demuxer-max-bytes', disk ? (isDesktop ? '1000MiB' : '300MiB') : (isDesktop ? '200MiB' : '60MiB')));
  }

  @override
  Future<LiveCache?> liveCache() async {
    final p = _player.platform;
    if (p is! NativePlayer) return null;
    try {
      // demuxer-cache-state er et JSON-kart: hvor langt det er hentet (cache-end), hvor avspilleren leser
      // (reader-pts) og hvilke deler det går an å hoppe i (seekable-ranges), alt i strømmens egen tid
      final j = jsonDecode(await p.getProperty('demuxer-cache-state'));
      if (j is! Map) return null;
      final end = j['cache-end'];
      final reader = j['reader-pts'];
      final ranges = j['seekable-ranges'];
      if (end is! num || reader is! num || ranges is! List) return null;
      for (final r in ranges) {
        if (r is! Map) continue;
        final start = r['start'];
        final stop = r['end'];
        if (start is! num || stop is! num || reader < start - 1 || reader > stop + 1) continue;
        return (back: _seconds(reader - start), ahead: _seconds(end - reader));
      }
    } on Object {
      // eldre mpv eller ingen strøm ennå
    }
    return null;
  }

  static Duration _seconds(num s) => Duration(milliseconds: (s.clamp(0, 1e7) * 1000).round());

  @override
  Future<void> seekBy(Duration delta) async {
    final p = _player.platform;
    if (p is! NativePlayer) return;
    await _try(() => p.command(['seek', (delta.inMilliseconds / 1000).toStringAsFixed(2), 'relative']));
  }

  /// segmentene fra slutten sist en direktesending ble åpnet tilbake i tid (null: som vanlig)
  int? _liveFromEnd;

  /// adressen som ble åpnet sist (samme adresse igjen, f.eks. etter spoling, beholder sporene du valgte)
  String? _lastUrl;
  LanguagePrefs _langs = const LanguagePrefs();

  static Future<void> _try(Future<void> Function() f) async {
    try {
      await f();
    } on Object {
      // eldre mpv uten innstillingen: spiller likevel
    }
  }

  @override
  Future<void> open(String url, Map<String, String> headers, {Duration? start, int? liveFromEnd}) async {
    final p = _player.platform;
    // Etter en spoling står valget i mpv til det endres: tilbake til ffmpegs vanlige 3 (direkte) neste gang.
    final want = liveFromEnd ?? (_liveFromEnd != null ? 3 : null);
    _liveFromEnd = liveFromEnd;
    if (want != null && p is NativePlayer) {
      // ffmpeg begynner en direktesending (HLS) så mange segmenter fra slutten. Legges til det media_kit har
      // satt i demuxer-lavf-o (protocol_whitelist osv.), og siste verdi gjelder.
      await _try(() => p.command(['change-list', 'demuxer-lavf-o', 'append', 'live_start_index=-$want']));
    }
    // Ny fil eller kanal: sporene velges etter språkene dine (et spor du valgte i forrige fil, står ellers i mpv).
    if (url != _lastUrl && p is NativePlayer) await _autoTracks(p);
    _lastUrl = url;
    await _player.open(Media(url, httpHeaders: headers, start: start));
  }

  Future<void> _autoTracks(NativePlayer p) async {
    await _try(() => p.setProperty('aid', 'auto'));
    await _try(() => p.setProperty('sid', _langs.subtitlesOff ? 'no' : 'auto'));
  }

  @override
  Future<void> setLanguages(LanguagePrefs prefs, {bool now = false}) async {
    _langs = prefs;
    final p = _player.platform;
    if (p is! NativePlayer) return;
    await _try(() => p.setProperty('alang', prefs.audioCodes));
    await _try(() => p.setProperty('slang', prefs.subtitleCodes));
    // Undertekster på språket du har valgt, men ikke når lyden alt er på det språket (mpv 0.36 og nyere).
    final matching = prefs.subtitleCodes.isEmpty ? 'yes' : 'no';
    await _try(() => p.setProperty('subs-with-matching-audio', matching));
    if (now) await _autoTracks(p);
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> playOrPause() => _player.playOrPause();

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  static String _name(String? title, String? language, String id) {
    final parts = [title, language].whereType<String>().where((s) => s.trim().isNotEmpty).toList();
    return parts.isEmpty ? 'Spor $id' : parts.join(' · ');
  }

  @override
  Future<TrackList> tracks() async {
    // media_kit vet bare om sporet du har valgt selv; mpv vet hva den valgte etter språkene
    var aid = _player.state.track.audio.id;
    var sid = _player.state.track.subtitle.id;
    final p = _player.platform;
    if (p is NativePlayer) {
      try {
        aid = (await p.getProperty('aid')).trim();
        sid = (await p.getProperty('sid')).trim();
      } on Object {
        // som media_kit har det
      }
    }
    final tracks = _player.state.tracks;
    return (
      audio: [
        for (final t in tracks.audio)
          if (t.id != 'auto' && t.id != 'no') TrackChoice(_name(t.title, t.language, t.id), selected: t.id == aid, value: t),
      ],
      subtitles: [
        TrackChoice('Av', selected: sid == 'no' || sid.isEmpty, value: SubtitleTrack.no()),
        for (final t in tracks.subtitle)
          if (t.id != 'auto' && t.id != 'no')
            TrackChoice(_name(t.title, t.language, t.id), selected: t.id == sid, value: t),
      ],
    );
  }

  @override
  Future<void> selectTrack(TrackChoice choice) async {
    final v = choice.value;
    if (v is AudioTrack) await _player.setAudioTrack(v);
    if (v is SubtitleTrack) await _player.setSubtitleTrack(v);
  }

  @override
  Future<String> describe() async {
    final p = _player.platform;
    if (p is! NativePlayer) return '';
    Future<String> prop(String name) async {
      try {
        return (await p.getProperty(name)).trim();
      } on Object {
        return '';
      }
    }

    final video = await prop('video-format');
    final hwdec = await prop('hwdec-current');
    final audio = await prop('audio-codec-name');
    final channels = await prop('audio-params/hr-channels');
    return [
      if (video.isNotEmpty) codecName(video),
      if (video.isNotEmpty && hwdec.isNotEmpty) hwdec == 'no' ? 'programvaredekoding' : 'maskinvaredekoding ($hwdec)',
      if (audio.isNotEmpty) [codecName(audio), if (channels.isNotEmpty) channelLayout(channels)].join(' '),
    ].join(' · ');
  }

  @override
  Widget view() => Video(
        controller: _video,
        controls: NoVideoControls,
        // spilleren gir selv fra seg kanalen når appen legges bort, og starter den igjen etterpå
        pauseUponEnteringBackgroundMode: false,
      );

  @override
  Future<void> dispose() => _player.dispose();
}
