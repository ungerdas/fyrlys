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
