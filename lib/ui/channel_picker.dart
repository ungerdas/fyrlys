import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/cache.dart' show SavedLists;
import '../core/models.dart';
import '../core/names.dart';
import '../core/source.dart';
import '../l10n/tr.dart';
import 'channel_card.dart';

/// Så mange treff i søket vises om gangen (skriv mer for å finne færre).
const pickerSearchLimit = 300;

/// Velg en kanal i et abonnement, ordnet som kanallista: favorittene, sist sett, alle kanalene, kategoriene du har
/// lagt øverst og resten av kategoriene som mapper, og søk i alle kanalene. Bare mappen som er åpen, vises, så en
/// liste med titusenvis av kanaler er like rask som en liten.
class ChannelPicker extends StatefulWidget {
  const ChannelPicker({
    super.key,
    required this.title,
    required this.lists,
    required this.favorites,
    required this.recent,
    required this.pinned,
    required this.logoUrl,
  });

  final String title;

  /// kategoriene og kanalene i abonnementet
  final Future<SavedLists> lists;
  final List<Channel> favorites;
  final List<Channel> recent;

  /// kategoriene du har lagt øverst (id-ene, i din rekkefølge)
  final List<String> pinned;
  final String? Function(String? icon) logoUrl;

  @override
  State<ChannelPicker> createState() => _ChannelPickerState();
}

/// Kanalene ordnet etter kategori, og navnene med små bokstaver til søket (lages én gang).
class _Index {
  _Index(SavedLists lists) : channels = lists.channels {
    for (final c in channels) {
      (byCategory[c.categoryId] ??= <Channel>[]).add(c);
    }
    final seen = <String>{};
    categories = [
      for (final c in lists.categories)
        if (byCategory.containsKey(c.id) && seen.add(c.id)) c,
    ];
  }

  final List<Channel> channels;
  final Map<String, List<Channel>> byCategory = {};
  late final List<Category> categories;
  late final List<String> _lower = [for (final c in channels) c.name.toLowerCase()];

  /// Kanalene der alle ordene i [query] står i navnet, høyst [limit].
  List<Channel> search(String query, int limit) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return const [];
    final hits = <Channel>[];
    for (var i = 0; i < channels.length && hits.length < limit; i++) {
      final name = _lower[i];
      if (words.every(name.contains)) hits.add(channels[i]);
    }
    return hits;
  }
}

class _ChannelPickerState extends State<ChannelPicker> {
  final _search = TextEditingController();
  String _query = '';

  /// mappen du har åpnet: 'fav', 'recent', 'all' eller en kategori-id (null: den første, eller mappene i et smalt
  /// vindu)
  String? _folder;
  _Index? _index;

  /// treffene for [_hitsFor] (søket kjøres én gang per tekst)
  String? _hitsFor;
  List<Channel> _hits = const [];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Mappen som åpnes først: favorittene, sist sett, den første du har lagt øverst, ellers den første kategorien.
  String _firstFolder(_Index index) {
    if (widget.favorites.isNotEmpty) return 'fav';
    if (widget.recent.isNotEmpty) return 'recent';
    for (final id in widget.pinned) {
      if (index.byCategory.containsKey(id)) return id;
    }
    return index.categories.isEmpty ? 'all' : index.categories.first.id;
  }

  List<Channel> _channelsIn(_Index index, String folder) => switch (folder) {
        'fav' => widget.favorites,
        'recent' => widget.recent,
        'all' => index.channels,
        _ => index.byCategory[folder] ?? const [],
      };

  String _folderName(_Index index, String folder) {
    switch (folder) {
      case 'fav':
        return tr('Favoritter');
      case 'recent':
        return tr('Sist sett');
      case 'all':
        return tr('Alle kanaler');
    }
    for (final c in index.categories) {
      if (c.id == folder) return c.name;
    }
    return tr('Kanaler');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    final width = math.max(280.0, math.min(920.0, size.width - 96));
    final height = math.max(260.0, math.min(640.0, size.height - 200));
    final wide = width >= 640;
    return AlertDialog(
      title: Text(widget.title),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: width,
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: tr('Søk etter kanal'),
              ),
              onChanged: (v) => setState(() => _query = v.trim()),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: FutureBuilder<SavedLists>(
                future: widget.lists,
                builder: (context, snap) {
                  if (snap.hasError) {
                    final e = snap.error;
                    return Center(
                      child: Text(
                        e is SourceException ? e.message : tr('Fikk ikke hentet kanalene.'),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.error),
                      ),
                    );
                  }
                  final lists = snap.data;
                  if (lists == null) return const Center(child: CircularProgressIndicator());
                  final index = _index ??= _Index(lists);
                  if (_query.isNotEmpty) return _results(index);
                  if (wide) {
                    final folder = _folder ?? _firstFolder(index);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 260, child: _folders(index, folder)),
                        const VerticalDivider(width: 17),
                        Expanded(child: _list(_channelsIn(index, folder))),
                      ],
                    );
                  }
                  // smalt: mappene, så kanalene i den du åpner
                  final folder = _folder;
                  if (folder == null) return _folders(index, null);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            key: const ValueKey('til-mappene'),
                            tooltip: tr('Tilbake'),
                            icon: const Icon(Icons.arrow_back),
                            onPressed: () => setState(() => _folder = null),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              _folderName(index, folder),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      Expanded(child: _list(_channelsIn(index, folder))),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Avbryt')))],
    );
  }

  /// Mappene, som i sidemenyen på TV-siden.
  Widget _folders(_Index index, String? selected) {
    final scheme = Theme.of(context).colorScheme;
    final byId = {for (final c in index.categories) c.id: c};
    final pinned = [
      for (final id in widget.pinned)
        if (byId[id] case final c?) c,
    ];
    final pinnedIds = {for (final c in pinned) c.id};
    Widget head(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 8, 6),
          child: Text(
            text.toUpperCase(),
            style: TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
          ),
        );
    return ListView(
      children: [
        if (widget.favorites.isNotEmpty)
          _folderTile('fav', tr('Favoritter'), widget.favorites.length, selected, icon: Icons.star_outline),
        if (widget.recent.isNotEmpty)
          _folderTile('recent', tr('Sist sett'), widget.recent.length, selected, icon: Icons.history),
        _folderTile('all', tr('Alle kanaler'), index.channels.length, selected, icon: Icons.apps),
        if (pinned.isNotEmpty) head(tr('Dine kategorier')),
        for (final c in pinned) _folderTile(c.id, c.name, index.byCategory[c.id]?.length ?? 0, selected),
        if (index.categories.length > pinned.length) head(pinned.isEmpty ? tr('Kategorier') : tr('Alle kategorier')),
        for (final c in index.categories)
          if (!pinnedIds.contains(c.id)) _folderTile(c.id, c.name, index.byCategory[c.id]?.length ?? 0, selected),
      ],
    );
  }

  Widget _folderTile(String id, String name, int count, String? selected, {IconData? icon}) {
    final scheme = Theme.of(context).colorScheme;
    final on = id == selected;
    return Material(
      color: on ? scheme.surfaceContainerHighest : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey('mappe:$id'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _folder = id),
        child: SizedBox(
          height: 40,
          child: Row(
            children: [
              const SizedBox(width: 12),
              if (icon != null) ...[
                Icon(icon, size: 20, color: on ? scheme.primary : scheme.onSurfaceVariant),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? scheme.primary : null),
                ),
              ),
              Text('$count', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Søket i alle kanalene, høyst [pickerSearchLimit] treff.
  Widget _results(_Index index) {
    if (_hitsFor != _query) {
      _hitsFor = _query;
      _hits = index.search(_query, pickerSearchLimit + 1);
    }
    final capped = _hits.length > pickerSearchLimit;
    final list = capped ? _hits.sublist(0, pickerSearchLimit) : _hits;
    if (list.isEmpty) {
      return Center(
        child: Text(tr('Fant ingenting.'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return _list(
      list,
      note: capped ? tr('Viser de {n} første treffene. Skriv mer for å finne færre.', {'n': pickerSearchLimit}) : null,
    );
  }

  /// Kanalene i en mappe eller treffene i søket (bare de som vises, bygges).
  Widget _list(List<Channel> list, {String? note}) {
    final scheme = Theme.of(context).colorScheme;
    if (list.isEmpty) {
      return Center(child: Text(tr('Ingen kanaler her.'), style: TextStyle(color: scheme.onSurfaceVariant)));
    }
    final extra = note == null ? 0 : 1;
    return ListView.builder(
      itemCount: list.length + extra,
      itemBuilder: (context, i) {
        if (note != null && i == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
            child: Text(note, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          );
        }
        final c = list[i - extra];
        final parts = nameParts(c.name);
        final sub = parts.sub.isNotEmpty ? parts.sub : (c.number == null ? null : tr('Kanal {n}', {'n': c.number}));
        return ListTile(
          key: ValueKey('kanal:${c.id}'),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          leading: ChannelLogo(url: widget.logoUrl(c.icon), name: c.name, width: 46, height: 32),
          title: Text(
            parts.time.isEmpty ? parts.main : '${parts.time}  ${parts.main}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: sub == null ? null : Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => Navigator.of(context).pop(c),
        );
      },
    );
  }
}
