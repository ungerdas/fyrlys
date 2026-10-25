// Det appen vet om kategorier, kanaler, programmer, kontoen og favorittene.

class Category {
  const Category({required this.id, required this.name, this.count = 0});

  final String id;
  final String name;
  final int count;
}

class Channel {
  const Channel({
    required this.id,
    required this.name,
    this.categoryId = '',
    this.icon,
    this.number,
    this.hasEpg = true,
  });

  factory Channel.fromJson(Map<String, Object?> j) => Channel(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        categoryId: '${j['cat'] ?? ''}',
        icon: j['icon'] is String ? j['icon'] as String : null,
        number: j['num']?.toString(),
        hasEpg: j['epg'] != false,
      );

  final String id;
  final String name;
  final String categoryId;

  /// Logoen hos leverandøren. Kilden lager adressen som faktisk hentes (se TvSource.logoUrl).
  final String? icon;
  final String? number;
  final bool hasEpg;

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'cat': categoryId, 'icon': icon, 'num': number, 'epg': hasEpg};
}

class EpgEntry {
  const EpgEntry({required this.title, required this.start, required this.stop, this.description = ''});

  final String title;
  final String description;
  final DateTime start;
  final DateTime stop;

  bool isOnAt(DateTime t) => !start.isAfter(t) && stop.isAfter(t);

  /// Hvor langt programmet har kommet, fra 0 til 1.
  double progressAt(DateTime t) {
    final total = stop.difference(start).inSeconds;
    if (total <= 0) return 0;
    final done = t.difference(start).inSeconds / total;
    return done < 0 ? 0 : (done > 1 ? 1 : done);
  }
}

/// Programmet som går nå, og det som kommer etter.
({EpgEntry? now, EpgEntry? next}) nowAndNext(List<EpgEntry> list, DateTime t) {
  EpgEntry? now;
  EpgEntry? next;
  for (final e in list) {
    if (e.isOnAt(t)) {
      now = e;
    } else if (!e.start.isBefore(t) && (next == null || e.start.isBefore(next.start))) {
      next = e;
    }
  }
  return (now: now, next: next);
}

class Account {
  const Account({
    this.user = '',
    this.host = '',
    this.status = '',
    this.expires,
    this.maxConnections = 0,
    this.activeConnections = 0,
  });

  final String user;
  final String host;
  final String status;
  final DateTime? expires;
  final int maxConnections;
  final int activeConnections;
}

class Favorites {
  const Favorites({required this.channels, required this.categories});

  final List<Channel> channels;
  final List<String> categories;
}
