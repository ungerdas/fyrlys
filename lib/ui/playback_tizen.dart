// Avspilleren på en Samsung-TV (Tizen): TV-ens egen avspiller (AVPlay) via video_player_avplay.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player_avplay/video_player.dart' as av;
import 'package:video_player_avplay/video_player_platform_interface.dart' as avp;

import '../core/languages.dart';
import '../core/names.dart';
import '../core/picture.dart';
import '../core/play_info.dart';
import '../l10n/tr.dart';
import 'playback.dart';

/// En undertekst fra en egen fil (Plex): når den vises, og teksten.
class SubtitleCue {
  const SubtitleCue(this.start, this.end, this.text);

  final Duration start;
  final Duration end;
  final String text;
}

final _cueTime =
    RegExp(r'(?:(\d+):)?(\d{1,2}):(\d{2})[,.](\d{1,3})\s*-->\s*(?:(\d+):)?(\d{1,2}):(\d{2})[,.](\d{1,3})');
final _markup = RegExp(r'<[^>]*>|\{\\[^}]*\}');

/// Undertekstene i en SubRip- (.srt) eller WebVTT-fil (.vtt), i tidsrekkefølge og uten formatering (<i>, {\an8}).
List<SubtitleCue> parseSubtitleCues(String text) {
  final cues = <SubtitleCue>[];
  final blocks = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split(RegExp(r'\n[ \t]*\n'));
  for (final block in blocks) {
    final lines = block.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final m = _cueTime.firstMatch(lines[i]);
      if (m == null) continue;
      final body = [
        for (final l in lines.skip(i + 1))
          if (l.replaceAll(_markup, '').trim().isNotEmpty) l.replaceAll(_markup, '').trim(),
      ].join('\n');
      if (body.isNotEmpty) cues.add(SubtitleCue(_cueAt(m, 1), _cueAt(m, 5), body));
      break;
    }
  }
  cues.sort((a, b) => a.start.compareTo(b.start));
  return cues;
}

Duration _cueAt(RegExpMatch m, int i) => Duration(
      hours: int.tryParse(m.group(i) ?? '') ?? 0,
      minutes: int.parse(m.group(i + 1)!),
      seconds: int.parse(m.group(i + 2)!),
      milliseconds: int.parse(m.group(i + 3)!.padRight(3, '0')),
    );

/// Teksten som vises ved [position] (null: ingen).
String? cueAt(List<SubtitleCue> cues, Duration position) {
  // den siste som har begynt
  var lo = 0;
  var hi = cues.length - 1;
  var found = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (cues[mid].start <= position) {
      found = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  if (found < 0) return null;
  // to som overlapper: begge
  final lines = [
    for (var i = found; i >= 0 && i > found - 3; i--)
      if (cues[i].start <= position && position < cues[i].end) cues[i].text,
  ];
  return lines.isEmpty ? null : lines.reversed.join('\n');
}

/// Pakken for TV-en ut fra Tizen-versjonen (filnavnene i releasen): AVPlay-delen er bygget for én versjon av gangen.
String tizenPackageFor(String platformVersion) {
  final v = double.tryParse(platformVersion.trim()) ?? 0;
  if (v >= 10) return 'Fyrlys-tizen-2026.tpk';
  if (v >= 6.5) return 'Fyrlys-tizen-2022-2025.tpk';
  return 'Fyrlys-tizen-2021.tpk';
}

/// Feilen fra avspilleren, forklart der det går.
String avplayError(Object error) {
  final text = switch (error) {
    PlatformException(:final message?) => message,
    PlatformException(:final code) => code,
    _ => '$error'.replaceFirst(RegExp(r'^Exception:\s*'), ''),
  };
  // feil pakke for TV-en: video_player_avplay sier hvilken Tizen-versjon TV-en har
  final version = RegExp(r'current TizenOS version is ([0-9.]+)').firstMatch(text)?.group(1);
  if (version != null) {
    return tr('Denne Fyrlys-pakken er for en annen Samsung-TV. TV-en har Tizen {version}: installer {file}.',
        {'version': version, 'file': tizenPackageFor(version)});
  }
  return text;
}

/// Lydspor/undertekst slått av, og en undertekstfil (Plex), slik de står i [TrackChoice.value].
class _SubtitlesOff {
  const _SubtitlesOff();
}

class _ExternalChoice {
  const _ExternalChoice(this.index);

  final int index;
}

/// TV-ens egen avspiller (AVPlay). Den finnes bare én gang på TV-en, så en ny adresse lukker den forrige først.
/// Bildet tegnes av TV-en bak appen (et hull i det appen tegner). Pause og spoling i direktesendinger (mpv sitt
/// buffer på PC-en) finnes ikke her: [liveCache] er alltid null.
class AvplayPlayback implements Playback {
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _position = StreamController<Duration>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _completed = StreamController<bool>.broadcast();
  final _height = StreamController<int?>.broadcast();
  final _duration = StreamController<Duration>.broadcast();

  /// avspilleren for det som spilles nå (null før første adresse og etter [stop])
  final current = ValueNotifier<av.VideoPlayerController?>(null);

  /// undertekstene er endret (valgt, slått av, eller en fil er hentet)
  final subtitles = ValueNotifier<int>(0);

  av.VideoPlayerController? _controller;
  av.VideoPlayerValue? _last;

  /// en ny adresse eller stopp gjør det som er på vei, ugyldig
  int _gen = 0;

  /// lukkingen av forrige avspiller, i rekkefølge (TV-en har bare én)
  Future<void> _gate = Future.value();
  bool _disposed = false;

  /// første posisjon i en direktesending (AVPlay teller fra starten av sendingen, ikke fra der du kom inn)
  Duration? _origin;

  double _volume = 100;
  LanguagePrefs _langs = const LanguagePrefs();

  /// lydsporet du valgte (null: det avspilleren tok)
  int? _audioId;

  /// undertekstsporet i filen, eller undertekstfilen, som vises når [subtitlesOn]
  int? _textId;
  int? _externalIndex;
  bool subtitlesOn = false;

  List<ExternalSubtitle> _external = const [];
  final _cues = <int, List<SubtitleCue>>{};
  Map<String, String> _headers = const {};

  av.VideoPlayerController? get _ready {
    final c = _controller;
    return c != null && c.value.isInitialized && !_disposed ? c : null;
  }

  static void _add<T>(StreamController<T> s, T value) {
    if (!s.isClosed) s.add(value);
  }

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<bool> get bufferingStream => _buffering.stream;

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<String> get errorStream => _errors.stream;

  @override
  Stream<bool> get completedStream => _completed.stream;

  @override
  Stream<int?> get heightStream => _height.stream;

  @override
  Stream<Duration> get durationStream => _duration.stream;

  /// En direktesending: AVPlay gir et vindu (fra–til) i stedet for en lengde, eller ingen lengde.
  static bool _isLive(av.VideoPlayerValue v) =>
      v.duration.start > Duration.zero || (v.isInitialized && v.duration.end <= Duration.zero);

  Duration _durationOf(av.VideoPlayerValue v) => _isLive(v) ? Duration.zero : v.duration.end;

  /// posisjonen fra der du kom inn (direktesending) eller fra starten (filer)
  Duration _rebase(av.VideoPlayerValue v) {
    if (!_isLive(v)) return v.position;
    final origin = _origin ??= v.position;
    final p = v.position - origin;
    return p < Duration.zero ? Duration.zero : p;
  }

  @override
  Duration get position {
    final c = _controller;
    return c == null ? Duration.zero : _rebase(c.value);
  }

  @override
  Duration get duration {
    final c = _controller;
    return c == null ? Duration.zero : _durationOf(c.value);
  }

  void _onValue() {
    final c = _controller;
    if (c == null || _disposed) return;
    final v = c.value;
    final last = _last;
    _last = v;
    if (last == null || v.isPlaying != last.isPlaying) _add(_playing, v.isPlaying);
    if (last == null || v.isBuffering != last.isBuffering) _add(_buffering, v.isBuffering);
    if (v.isInitialized && (last == null || v.position != last.position)) _add(_position, _rebase(v));
    if (v.isCompleted && !(last?.isCompleted ?? false)) _add(_completed, true);
    final h = v.size.height.round();
    if (h > 0 && (last == null || last.size.height.round() != h)) _add(_height, h);
    final d = _durationOf(v);
    if (last == null || d != _durationOf(last)) _add(_duration, d);
    final err = v.errorDescription;
    if (err != null && err != last?.errorDescription) _error(err);
  }

  void _error(String text) {
    debugPrint('AVPlay: $text');
    _add(_errors, text);
  }

  /// Tar avspilleren ut av bruk (lukkes av den som tok den).
  av.VideoPlayerController? _take() {
    final c = _controller;
    c?.removeListener(_onValue);
    _controller = null;
    _last = null;
    _origin = null;
    _audioId = null;
    _textId = null;
    _externalIndex = null;
    subtitlesOn = false;
    _external = const [];
    _cues.clear();
    current.value = null;
    subtitles.value++;
    return c;
  }

  static Future<void> _close(av.VideoPlayerController? c) async {
    if (c == null) return;
    try {
      await c.dispose();
    } on Object catch (e) {
      debugPrint('AVPlay: kunne ikke lukkes ($e)');
    }
  }

  /// Lukker den som spilles, og venter til TV-en har gitt den fra seg.
  Future<void> _release() => _gate = _gate.then((_) => _close(_take()));

  @override
  Future<void> setup({bool live = false, bool tv = false}) async {}

  @override
  Future<LiveCache?> liveCache() async => null;

  @override
  Future<void> seek(Duration position) async {
    final c = _ready;
    if (c == null) return;
    final live = _isLive(c.value);
    try {
      await c.seekTo(live ? position + (_origin ?? Duration.zero) : position);
    } on Object catch (e) {
      debugPrint('AVPlay: kunne ikke spole ($e)');
    }
  }

  @override
  Future<void> seekBy(Duration delta) => seek(position + delta);

  /// AVPlay sender bare User-Agent og Cookie med. Plex tar resten (X-Plex-Token …) like gjerne i adressen.
  static String withHeadersInUrl(String url, Map<String, String> headers) {
    final extra = {
      for (final e in headers.entries)
        if (e.key.toLowerCase().startsWith('x-plex-')) e.key: e.value,
    };
    if (extra.isEmpty) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return uri.replace(queryParameters: {...uri.queryParameters, ...extra}).toString();
  }

  static String? _header(Map<String, String> headers, String name) {
    for (final e in headers.entries) {
      if (e.key.toLowerCase() == name && e.value.isNotEmpty) return e.value;
    }
    return null;
  }

  @override
  Future<void> open(String url, Map<String, String> headers, {Duration? start}) async {
    final my = ++_gen;
    await _release();
    if (my != _gen || _disposed) return;
    _headers = headers;
    final ua = _header(headers, 'user-agent');
    final cookie = _header(headers, 'cookie');
    final c = av.VideoPlayerController.network(
      withHeadersInUrl(url, headers),
      streamingProperty: {
        if (ua != null) avp.StreamingPropertyType.userAgent: ua,
        if (cookie != null) avp.StreamingPropertyType.cookie: cookie,
      },
      // sidene tar seg selv av hva som skjer når appen legges bort (som på telefonen)
      videoPlayerOptions: avp.VideoPlayerOptions(allowBackgroundPlayback: true),
    );
    _controller = c;
    c.addListener(_onValue);
    current.value = c;
    try {
      // en strøm som aldri svarer: TV-en gir ikke alltid beskjed selv
      await c.initialize().timeout(const Duration(seconds: 40));
    } on TimeoutException {
      if (my == _gen) _error(tr('Strømmen svarte ikke.'));
      return;
    } on Object catch (e) {
      if (my == _gen && c.value.errorDescription == null) _error(avplayError(e));
      return;
    }
    if (my != _gen || _disposed) return;
    try {
      await c.setVolume(_volume / 100);
      // fortsett der du slapp (startPosition i AVPlay tar bare store tall)
      if (start != null && start > Duration.zero) await c.seekTo(start);
      await c.play();
    } on Object catch (e) {
      if (my == _gen) _error(avplayError(e));
      return;
    }
    unawaited(_chooseTracks(c, my));
  }

  @override
  Future<void> stop() async {
    ++_gen;
    await _release();
    _add(_playing, false);
  }

  @override
  Future<void> playOrPause() async {
    final c = _ready;
    if (c == null) return;
    try {
      if (c.value.isPlaying) {
        await c.pause();
      } else {
        await c.play();
      }
    } on Object catch (e) {
      debugPrint('AVPlay: pause/spill feilet ($e)');
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0, 100).toDouble();
    try {
      await _ready?.setVolume(_volume / 100);
    } on Object {
      // ikke klar
    }
  }

  /// kodene du foretrekker («nor,nob,…,eng,en»), i rekkefølge
  static List<String> _codes(String joined) =>
      [for (final c in joined.split(',')) if (c.trim().isNotEmpty) c.trim().toLowerCase()];

  /// sporet med språket høyest på lista, ellers null
  static T? _best<T>(List<T> tracks, String Function(T) language, List<String> wanted) {
    T? best;
    var rank = wanted.length;
    for (final t in tracks) {
      final r = wanted.indexOf(language(t).trim().toLowerCase());
      if (r >= 0 && r < rank) {
        rank = r;
        best = t;
      }
    }
    return best;
  }

  static bool _sameLanguage(String a, String b) {
    final x = a.trim().toLowerCase();
    final y = b.trim().toLowerCase();
    if (x.isEmpty || y.isEmpty) return false;
    for (final l in languages) {
      if (l.codes.contains(x) && l.codes.contains(y)) return true;
    }
    return x == y;
  }

  /// Lydspor og undertekst etter språkene dine (som alang/slang i mpv).
  Future<void> _chooseTracks(av.VideoPlayerController c, int my) async {
    try {
      final audio = await c.audioTracks ?? const <av.AudioTrack>[];
      final text = await c.textTracks ?? const <av.TextTrack>[];
      if (my != _gen) return;
      final a = _best(audio, (t) => t.language, _codes(_langs.audioCodes));
      if (a != null && audio.isNotEmpty && a.trackId != audio.first.trackId && await c.setTrackSelection(a)) {
        _audioId = a.trackId;
      }
      final playing = a ?? (audio.isEmpty ? null : audio.first);
      final wanted = _codes(_langs.subtitleCodes);
      final s = _langs.subtitlesOff || wanted.isEmpty ? null : _best(text, (t) => t.language, wanted);
      // ikke undertekster på det språket lyden alt er på
      if (s != null && !(playing != null && _sameLanguage(playing.language, s.language))) {
        await c.setTrackSelection(s);
        _textId = s.trackId;
        subtitlesOn = true;
      }
    } on Object catch (e) {
      debugPrint('AVPlay: sporene kunne ikke velges ($e)');
    }
    subtitles.value++;
  }

  static String _languageName(String code) {
    final c = code.trim().toLowerCase();
    if (c.isEmpty || c == 'und') return '';
    for (final l in languages) {
      if (l.codes.contains(c)) return l.name;
    }
    return c.toUpperCase();
  }

  /// «audio/x-eac3» → E-AC3, «video/x-h265» → H.265
  static String mimeCodec(String mime) {
    final m = mime.toLowerCase();
    final sub = m.contains('/') ? m.substring(m.indexOf('/') + 1) : m;
    return codecName(switch (sub.replaceFirst('x-', '')) {
      'h264' => 'h264',
      'h265' || 'hevc' => 'hevc',
      'eac3' || 'ec-3' => 'eac3',
      'ac3' || 'ac-3' => 'ac3',
      'aac' || 'mpeg4-generic' => 'aac',
      'dts' => 'dts',
      'mpeg' when m.startsWith('video/') => 'mpeg2video',
      'mpeg' => 'mp2',
      final other => other,
    });
  }

  static String _channels(int n) => switch (n) {
        1 => 'mono',
        2 => tr('stereo'),
        6 => '5.1',
        8 => '7.1',
        _ => '',
      };

  static String _trackName(String language, String mime, {int channels = 0, required int id}) {
    final parts = [
      _languageName(language),
      if (mime.isNotEmpty) mimeCodec(mime),
      _channels(channels),
    ].where((s) => s.isNotEmpty).toList();
    return parts.isEmpty ? tr('Spor {id}', {'id': id}) : parts.join(' · ');
  }

  @override
  Future<TrackList> tracks() async {
    final c = _ready;
    var audio = const <av.AudioTrack>[];
    var text = const <av.TextTrack>[];
    if (c != null) {
      try {
        audio = await c.audioTracks ?? audio;
        text = await c.textTracks ?? text;
      } on Object {
        // ikke klar
      }
    }
    final aid = _audioId ?? (audio.isEmpty ? null : audio.first.trackId);
    return (
      audio: [
        for (final t in audio)
          TrackChoice(_trackName(t.language, t.mimetype, channels: t.channel, id: t.trackId),
              selected: t.trackId == aid, value: t),
      ],
      subtitles: [
        TrackChoice(tr('Av'), selected: !subtitlesOn, value: const _SubtitlesOff()),
        for (final t in text)
          TrackChoice(_trackName(t.language, '', id: t.trackId),
              selected: subtitlesOn && _externalIndex == null && _textId == t.trackId, value: t),
        for (var i = 0; i < _external.length; i++)
          TrackChoice(_external[i].title, selected: subtitlesOn && _externalIndex == i, value: _ExternalChoice(i)),
      ],
    );
  }

  @override
  Future<void> selectTrack(TrackChoice choice) async {
    final v = choice.value;
    if (v is _SubtitlesOff) {
      subtitlesOn = false;
    } else if (v is _ExternalChoice) {
      subtitlesOn = true;
      _externalIndex = v.index;
      unawaited(_loadCues(v.index, _gen));
    } else {
      final c = _ready;
      if (c == null) return;
      try {
        if (v is av.AudioTrack && await c.setTrackSelection(v)) _audioId = v.trackId;
        if (v is av.TextTrack) {
          await c.setTrackSelection(v);
          _textId = v.trackId;
          _externalIndex = null;
          subtitlesOn = true;
        }
      } on Object catch (e) {
        debugPrint('AVPlay: sporet kunne ikke velges ($e)');
      }
    }
    subtitles.value++;
  }

  /// bare tekst: bildeundertekster (.sup) kan ikke vises fra en egen fil her
  static bool _isText(ExternalSubtitle s) {
    final path = (Uri.tryParse(s.url)?.path ?? s.url).toLowerCase();
    return !path.endsWith('.sup') && !path.endsWith('.idx') && !path.endsWith('.sub');
  }

  @override
  Future<void> addSubtitles(List<ExternalSubtitle> subtitles) async {
    final my = _gen;
    _external = [for (final s in subtitles) if (_isText(s)) s];
    if (_external.isEmpty || subtitlesOn || _langs.subtitlesOff) {
      this.subtitles.value++;
      return;
    }
    // den som har språket høyest på lista di, når filen ikke alt har slått på en undertekst
    final i = _best(List.generate(_external.length, (i) => i), (i) => _external[i].language, _codes(_langs.subtitleCodes));
    if (i != null) {
      subtitlesOn = true;
      _externalIndex = i;
      await _loadCues(i, my);
    }
    this.subtitles.value++;
  }

  Future<void> _loadCues(int index, int my) async {
    if (_cues.containsKey(index) || index >= _external.length) return;
    final s = _external[index];
    try {
      final res = await http.get(Uri.parse(s.url), headers: {
        if (_header(_headers, 'user-agent') case final ua?) 'User-Agent': ua,
      }).timeout(const Duration(seconds: 20));
      if (res.statusCode >= 400) throw Exception('HTTP ${res.statusCode}');
      final cues = parseSubtitleCues(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (my != _gen) return;
      _cues[index] = cues;
    } on Object catch (e) {
      debugPrint('AVPlay: undertekstfilen kunne ikke hentes (${e.runtimeType})');
      if (my == _gen) _cues[index] = const [];
    }
    subtitles.value++;
  }

  /// teksten fra undertekstfilen som vises nå (null: ingen fil er valgt, eller ingen tekst nå)
  String? externalCue(Duration position) {
    final i = _externalIndex;
    if (!subtitlesOn || i == null) return null;
    final cues = _cues[i];
    return cues == null ? null : cueAt(cues, position);
  }

  /// en undertekstfil er valgt (da vises ikke filens egne)
  bool get externalChosen => subtitlesOn && _externalIndex != null;

  @override
  Future<void> setLanguages(LanguagePrefs prefs, {bool now = false}) async {
    _langs = prefs;
    final c = _ready;
    if (now && c != null) {
      _audioId = null;
      _textId = null;
      _externalIndex = null;
      subtitlesOn = false;
      await _chooseTracks(c, _gen);
    }
  }

  /// TV-en fjerner striper og tilpasser bevegelsen selv
  @override
  Future<void> setPicture(PicturePrefs prefs) async {}

  /// finnes ikke i AVPlay (valget vises ikke på TV-en)
  @override
  Future<void> setAudioDelay(Duration delay) async {}

  @override
  Future<String> describe() async {
    final c = _ready;
    if (c == null) return '';
    final parts = <String>[];
    try {
      final video = await c.videoTracks ?? const <av.VideoTrack>[];
      final audio = await c.audioTracks ?? const <av.AudioTrack>[];
      if (video.isNotEmpty && video.first.mimetype.isNotEmpty) parts.add(mimeCodec(video.first.mimetype));
      final bandwidth = double.tryParse(
          (await c.getStreamingProperty(avp.StreamingPropertyType.currentBandwidth)).trim());
      if (bandwidth != null && bandwidth > 0) parts.add(bitrateText(bandwidth));
      final aid = _audioId ?? (audio.isEmpty ? null : audio.first.trackId);
      for (final a in audio) {
        if (a.trackId != aid) continue;
        parts.add([mimeCodec(a.mimetype), _channels(a.channel)].where((s) => s.isNotEmpty).join(' '));
      }
    } on Object {
      // det TV-en ikke vil si
    }
    parts.add(tr('TV-ens avspiller'));
    return parts.join(' · ');
  }

  @override
  Widget view({PictureFormat format = PictureFormat.original}) => _AvplayView(playback: this, format: format);

  @override
  Future<void> dispose() async {
    _disposed = true;
    ++_gen;
    await _release();
    for (final s in [_playing, _buffering, _completed]) {
      await s.close();
    }
    await _position.close();
    await _errors.close();
    await _height.close();
    await _duration.close();
  }
}

/// Bildet: et hull i appen der TV-en viser videoen, og undertekstene over.
class _AvplayView extends StatelessWidget {
  const _AvplayView({required this.playback, required this.format});

  final AvplayPlayback playback;
  final PictureFormat format;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<av.VideoPlayerController?>(
        valueListenable: playback.current,
        builder: (context, c, _) => c == null
            ? const SizedBox.expand()
            : _AvplayPicture(key: ObjectKey(c), controller: c, playback: playback, format: format),
      );
}

class _AvplayPicture extends StatefulWidget {
  const _AvplayPicture({super.key, required this.controller, required this.playback, required this.format});

  final av.VideoPlayerController controller;
  final AvplayPlayback playback;
  final PictureFormat format;

  @override
  State<_AvplayPicture> createState() => _AvplayPictureState();
}

class _AvplayPictureState extends State<_AvplayPicture> {
  /// bildeformatet TV-en har fått (null: ikke ennå)
  PictureFormat? _applied;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onValue);
    _onValue();
  }

  @override
  void didUpdateWidget(_AvplayPicture old) {
    super.didUpdateWidget(old);
    if (old.format != widget.format) _onValue();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onValue);
    super.dispose();
  }

  void _onValue() {
    if (!widget.controller.value.isInitialized || _applied == widget.format) return;
    final format = _applied = widget.format;
    // innenfor hullet: hele bildet med svarte kanter, fylt ut (beskåret), eller strukket (også til 16:9 og 4:3)
    final mode = switch (format) {
      PictureFormat.original => avp.DisplayMode.letterBox,
      PictureFormat.zoom => avp.DisplayMode.croppedFull,
      _ => avp.DisplayMode.fullScreen,
    };
    unawaited(widget.controller.setDisplayMode(mode).catchError((Object _) => false));
  }

  @override
  Widget build(BuildContext context) {
    final ratio = widget.format.aspectRatio;
    Widget picture = av.VideoPlayer(widget.controller);
    if (ratio != null) picture = Center(child: AspectRatio(aspectRatio: ratio, child: picture));
    return Stack(
      fit: StackFit.expand,
      children: [
        picture,
        ListenableBuilder(
          listenable: Listenable.merge([widget.controller, widget.playback.subtitles]),
          builder: (context, _) {
            final p = widget.playback;
            if (!p.subtitlesOn) return const SizedBox.shrink();
            if (p.externalChosen) {
              final text = p.externalCue(p.position);
              return text == null ? const SizedBox.shrink() : _Caption(text: text);
            }
            return av.ClosedCaption(captions: widget.controller.value.captions);
          },
        ),
      ],
    );
  }
}

/// En undertekst fra en fil: hvit tekst på mørk bakgrunn nederst i bildet, størrelsen etter bildet.
class _Caption extends StatelessWidget {
  const _Caption({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) => Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(box.maxWidth * 0.08, 0, box.maxWidth * 0.08, box.maxHeight * 0.06),
            child: DecoratedBox(
              decoration: BoxDecoration(color: const Color(0xB8000000), borderRadius: BorderRadius.circular(4)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: (box.maxHeight / 18).clamp(14, 48).toDouble()),
                ),
              ),
            ),
          ),
        ),
      );
}
