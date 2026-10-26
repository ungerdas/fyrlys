// Hvordan bildet vises i spillerne.

/// [deinterlace]: bilder som sendes interlacet (1080i, vanlig på TV-kanaler), gjøres om så de ikke får striper i
/// bevegelse; progressive bilder røres ikke. [smooth]: bildet tilpasses skjermens frekvens (25/50 fps på en
/// 60 Hz-skjerm), så panorering og sport hakker mindre. Det siste er en prøve: virker ikke alltid i media_kit.
class PicturePrefs {
  const PicturePrefs({this.deinterlace = true, this.smooth = false});

  final bool deinterlace;
  final bool smooth;

  PicturePrefs copyWith({bool? deinterlace, bool? smooth}) =>
      PicturePrefs(deinterlace: deinterlace ?? this.deinterlace, smooth: smooth ?? this.smooth);

  @override
  bool operator ==(Object other) =>
      other is PicturePrefs && other.deinterlace == deinterlace && other.smooth == smooth;

  @override
  int get hashCode => Object.hash(deinterlace, smooth);
}

/// Bildeformatet i spillerne: som det sendes, fylt (kantene skjæres bort), strukket, eller tvunget til 16:9 eller 4:3
/// (for kanaler som sender feil format).
enum PictureFormat {
  original,
  zoom,
  stretch,
  wide,
  classic;

  static PictureFormat parse(String? name) =>
      values.firstWhere((f) => f.name == name, orElse: () => PictureFormat.original);

  /// den neste (Z i spillerne)
  PictureFormat get next => values[(index + 1) % values.length];

  /// forholdet bildet tvinges til (null: det strømmen sier)
  double? get aspectRatio => switch (this) {
        PictureFormat.wide => 16 / 9,
        PictureFormat.classic => 4 / 3,
        _ => null,
      };
}

/// Hvor mye lyden flyttes i forhold til bildet: fra −2 til +2 sekunder, i steg på 50 ms. Positivt: lyden kommer senere.
const audioDelayStep = Duration(milliseconds: 50);
const audioDelayMax = Duration(seconds: 2);

Duration clampAudioDelay(Duration d) {
  final ms = (d.inMilliseconds / audioDelayStep.inMilliseconds).round() * audioDelayStep.inMilliseconds;
  return Duration(milliseconds: ms.clamp(-audioDelayMax.inMilliseconds, audioDelayMax.inMilliseconds));
}

/// Det som huskes for én kanal: bildeformatet og lydforsinkelsen.
class ChannelView {
  const ChannelView({this.format = PictureFormat.original, this.audioDelay = Duration.zero});

  final PictureFormat format;
  final Duration audioDelay;

  bool get isDefault => format == PictureFormat.original && audioDelay == Duration.zero;

  ChannelView copyWith({PictureFormat? format, Duration? audioDelay}) =>
      ChannelView(format: format ?? this.format, audioDelay: audioDelay ?? this.audioDelay);

  Map<String, Object> toJson() => {
        if (format != PictureFormat.original) 'f': format.name,
        if (audioDelay != Duration.zero) 'd': audioDelay.inMilliseconds,
      };

  static ChannelView fromJson(Object? json) {
    if (json is! Map) return const ChannelView();
    final d = json['d'];
    final f = json['f'];
    return ChannelView(
      format: PictureFormat.parse(f is String ? f : null),
      audioDelay: clampAudioDelay(Duration(milliseconds: d is num ? d.round() : 0)),
    );
  }

  @override
  bool operator ==(Object other) => other is ChannelView && other.format == format && other.audioDelay == audioDelay;

  @override
  int get hashCode => Object.hash(format, audioDelay);
}
