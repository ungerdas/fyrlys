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

/// «20:30»
String hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
