// Kanalnavn fra leverandøren, som i nettversjonen.

class NameParts {
  const NameParts({required this.time, required this.main, required this.sub});

  /// klokkeslett for eventkanaler, f.eks. «12:45»
  final String time;

  /// kanalnavnet eller kampen
  final String main;

  /// resten, f.eks. liga og land
  final String sub;
}

final _startTime = RegExp(r'^(\d{1,2}[:.]\d{2})\s*[-–|:]?\s+(.+)$');

/// «12:45 Aston Villa - Man City | Premier League 10/24 [Viaplay NO]» → klokkeslett, kamp og resten.
NameParts nameParts(String name) {
  var n = name.trim();
  var time = '';
  final m = _startTime.firstMatch(n);
  if (m != null) {
    time = m.group(1)!.replaceFirst('.', ':');
    n = m.group(2)!;
  }
  final i = n.indexOf(' | ');
  return NameParts(
    time: time,
    main: i > 0 ? n.substring(0, i).trim() : n,
    sub: i > 0 ? n.substring(i + 3).trim() : '',
  );
}

/// «1:02:03» eller «12:34»
String formatDuration(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = s ~/ 3600;
  final m = (s ~/ 60) % 60;
  final sec = (s % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
}

/// «20:30»
String hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Kodeknavn fra mpv/ffmpeg slik de vanligvis skrives: «h264» → «H.264», «eac3» → «E-AC3».
String codecName(String codec) => switch (codec.trim().toLowerCase()) {
      'h264' || 'avc' => 'H.264',
      'hevc' || 'h265' => 'H.265',
      'mpeg2video' => 'MPEG-2',
      'av1' => 'AV1',
      'vp9' => 'VP9',
      'aac' || 'aac_latm' => 'AAC',
      'ac3' => 'AC3',
      'eac3' => 'E-AC3',
      'mp2' => 'MP2',
      'mp3' || 'mp3float' => 'MP3',
      'dts' => 'DTS',
      'truehd' => 'TrueHD',
      'opus' => 'Opus',
      'flac' => 'FLAC',
      final other => other.toUpperCase(),
    };

/// Kanaloppsettet fra mpv: «5.1(side)» → «5.1», «stereo» → «stereo».
String channelLayout(String layout) => layout.replaceAll(RegExp(r'\(.*?\)'), '').trim();
