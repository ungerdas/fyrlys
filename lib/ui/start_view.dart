import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/names.dart';
import '../core/session.dart';
import '../core/vod.dart';
import 'channel_card.dart';
import 'motion.dart';
import 'vod_browser.dart';
import 'vod_detail_page.dart';

/// Spiller kanal nummer [index] i [list]; [title] er navnet på lista i spilleren.
typedef PlayChannels = void Function(List<Channel> list, int index, String title, bool fromFavorites);

const _weekdays = ['mandag', 'tirsdag', 'onsdag', 'torsdag', 'fredag', 'lørdag', 'søndag'];
const _months = [
  'januar',
  'februar',
  'mars',
  'april',
  'mai',
  'juni',
  'juli',
  'august',
  'september',
  'oktober',
  'november',
  'desember',
];

/// «God kveld» etter tiden på døgnet.
String greetingAt(DateTime t) => switch (t.hour) {
      < 5 => 'God natt',
      < 10 => 'God morgen',
      < 18 => 'God dag',
      < 23 => 'God kveld',
      _ => 'God natt',
    };

/// «Mandag 26. oktober»
String dateLine(DateTime t) {
  final day = _weekdays[t.weekday - 1];
  return '${day[0].toUpperCase()}${day.substring(1)} ${t.day}. ${_months[t.month - 1]}';
}

/// Startsiden på TV-fanen («Hjem»): hilsen og klokke, kanalen du så sist (med programmet nå og etterpå),
/// favorittene med det som går nå og etterpå, de andre kanalene du har sett, kategoriene dine, og nederst filmen
/// eller serien du holder på med, når det finnes.
class StartView extends StatefulWidget {
  const StartView({super.key, required this.session, required this.onPlay, required this.onShow});

  final Session session;
  final PlayChannels onPlay;

  /// gå til en liste i sidemenyen: 'all', 'fav', 'recent' eller en kategori-id
  final ValueChanged<String> onShow;

  /// så mange favoritter vises her; resten under «Favoritter»
  static const favoritesShown = 12;

  @override
  State<StartView> createState() => _StartViewState();
}

class _StartViewState extends State<StartView> {
  Session get s => widget.session;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final pad = box.maxWidth >= 700 ? 28.0 : 16.0;
      final recent = s.recent;
      final favorites = s.favorites;
      final shownFavorites = favorites.take(StartView.favoritesShown).toList();
      final others = recent.skip(1).toList();
      final continues = s.continueItems.take(10).toList();
      final scheme = Theme.of(context).colorScheme;
      Widget section(Widget child) => _section(pad, child);
      return DecoratedBox(
        // et svakt lys fra fyret øverst til venstre
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-1.1, -1.25),
            radius: 1.3,
            colors: [scheme.primary.withValues(alpha: 0.13), scheme.primary.withValues(alpha: 0)],
          ),
        ),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 24, pad, 18),
              sliver: SliverToBoxAdapter(child: _Greeting(now: DateTime.now())),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              sliver: SliverToBoxAdapter(
                child: recent.isNotEmpty
                    ? LastWatchedCard(
                        key: ValueKey('sist:${recent.first.id}'),
                        session: s,
                        channel: recent.first,
                        onTap: () => widget.onPlay(recent, 0, 'Sist sett', false),
                      )
                    : _Welcome(onAll: () => widget.onShow('all')),
              ),
            ),
            // favorittene, med det som går nå og etterpå
            section(_Heading(
              title: 'Favoritter',
              count: favorites.length,
              action: favorites.length > shownFavorites.length ? 'Alle favoritter' : null,
              onAction: () => widget.onShow('fav'),
            )),
            if (shownFavorites.isEmpty)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                sliver: const SliverToBoxAdapter(
                  child: _Hint(
                    icon: Icons.star_border,
                    text: 'Trykk ☆ på kanalene du ser mest, så samles de her med det som går nå og etterpå.',
                  ),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                sliver: SliverGrid.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 400,
                    mainAxisExtent: 102,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: shownFavorites.length,
                  itemBuilder: (context, i) => ChannelCard(
                    key: ValueKey('start-fav:${shownFavorites[i].id}'),
                    session: s,
                    channel: shownFavorites[i],
                    showNext: true,
                    onTap: () => widget.onPlay(favorites, i, 'Favoritter', true),
                  ),
                ),
              ),
            // de andre kanalene du har sett
            if (others.isNotEmpty) ...[
              section(_Heading(title: 'Sist sett', action: 'Vis alle', onAction: () => widget.onShow('recent'))),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: pad),
                    itemCount: others.length,
                    separatorBuilder: (context, i) => const SizedBox(width: 12),
                    itemBuilder: (context, i) => SizedBox(
                      width: 330,
                      child: ChannelCard(
                        key: ValueKey('start-recent:${others[i].id}'),
                        session: s,
                        channel: others[i],
                        onTap: () => widget.onPlay(recent, i + 1, 'Sist sett', false),
                      ),
                    ),
                  ),
                ),
              ),
            ],
            ..._categories(pad),
            // filmen eller serien du holder på med: liten, nederst
            if (continues.isNotEmpty) ...[
              section(const _Heading(title: 'Fortsett å se', small: true)),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 112,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: pad),
                    itemCount: continues.length,
                    separatorBuilder: (context, i) => const SizedBox(width: 12),
                    itemBuilder: (context, i) => ContinueCard(
                      key: ValueKey('start-continue:${continues[i].key}'),
                      session: s,
                      item: continues[i],
                      onTap: () => unawaited(_playContinue(continues[i])),
                      onRemove: () => setState(() => s.removeContinue(continues[i].key)),
                    ),
                  ),
                ),
              ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      );
    });
  }

  /// Overskriften over en del av siden.
  Widget _section(double pad, Widget child) =>
      SliverPadding(padding: EdgeInsets.fromLTRB(pad, 30, pad, 12), sliver: SliverToBoxAdapter(child: child));

  Future<void> _playContinue(ContinueItem item) async {
    await playContinue(context, s, item);
    // hvor du slapp, kan ha endret seg
    if (mounted) setState(() {});
  }

  /// Kategoriene du har lagt øverst, eller de første kategoriene hos leverandøren.
  List<Widget> _categories(double pad) {
    final byId = {for (final c in s.categories) c.id: c};
    final pinned = [for (final id in s.favoriteCategories) if (byId[id] case final c?) c];
    final shown = pinned.isNotEmpty ? pinned : s.categories.take(16).toList();
    if (shown.isEmpty) return const [];
    return [
      _section(pad, _Heading(
        title: pinned.isNotEmpty ? 'Dine kategorier' : 'Kategorier',
        action: 'Alle kanaler',
        onAction: () => widget.onShow('all'),
      )),
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        sliver: SliverToBoxAdapter(
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in shown)
                ActionChip(
                  label: Text('${c.name}  ${s.categoryCounts[c.id] ?? 0}'),
                  onPressed: () => widget.onShow(c.id),
                ),
            ],
          ),
        ),
      ),
    ];
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greetingAt(now),
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.6),
        ),
        const SizedBox(height: 2),
        Text(
          '${dateLine(now)}  ·  ${hhmm(now)}',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 15),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.title, this.count, this.action, this.onAction, this.small = false});

  final String title;
  final int? count;
  final String? action;
  final VoidCallback? onAction;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = action;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(title, style: TextStyle(fontSize: small ? 16 : 19, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
        if ((count ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text('${count!}', style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        const Spacer(),
        if (a != null) TextButton(onPressed: onAction, child: Text(a)),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4))),
        ],
      ),
    );
  }
}

/// Første gang: ingen kanaler sett ennå.
class _Welcome extends StatelessWidget {
  const _Welcome({required this.onAll});

  final VoidCallback onAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outline),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary.withValues(alpha: 0.16), scheme.surface],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Velkommen til Fyrlys', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Velg en kanal fra lista eller en kategori under. Kanalen du så sist, kommer hit, og stjernemerkede kanaler '
            'samles med det som går nå.',
            style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: onAll, icon: const Icon(Icons.live_tv), label: const Text('Se alle kanaler')),
        ],
      ),
    );
  }
}

/// Kanalen du så sist, stort: logo, navn, programmet som går nå (med tid og fremdrift) og det som kommer etterpå.
class LastWatchedCard extends StatefulWidget {
  const LastWatchedCard({super.key, required this.session, required this.channel, required this.onTap});

  final Session session;
  final Channel channel;
  final VoidCallback onTap;

  @override
  State<LastWatchedCard> createState() => _LastWatchedCardState();
}

class _LastWatchedCardState extends State<LastWatchedCard> {
  Future<List<EpgEntry>>? _epg;
  bool _focused = false;
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    final ch = widget.channel;
    // eventkanaler har kampen i navnet, og ofte ingen EPG
    if (ch.hasEpg && nameParts(ch.name).sub.isEmpty) _epg = widget.session.epg(ch.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = widget.session;
    final ch = widget.channel;
    final parts = nameParts(ch.name);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 620;
      final logo = ChannelLogo(
        url: s.source?.logoUrl(ch.icon),
        name: ch.name,
        width: wide ? 132 : 84,
        height: wide ? 96 : 62,
      );
      final title = Text.rich(
        TextSpan(children: [
          if (ch.number != null)
            TextSpan(
              text: '${ch.number}  ',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: wide ? 17 : 14),
            ),
          if (parts.time.isNotEmpty) TextSpan(text: '${parts.time}  ', style: TextStyle(color: scheme.primary)),
          TextSpan(text: parts.main),
        ]),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: wide ? 26 : 20, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.2),
      );
      final program = _epg == null
          ? (parts.sub.isEmpty
              ? const SizedBox.shrink()
              : Text(parts.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: scheme.onSurfaceVariant)))
          : FutureBuilder<List<EpgEntry>>(
              future: _epg,
              builder: (context, snap) => _program(snap.data ?? const [], wide),
            );
      final watch = Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(24)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_arrow, color: scheme.onPrimary),
            const SizedBox(width: 6),
            Text('Se videre', style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w700)),
          ],
        ),
      );
      final label = Text(
        'SIST SETT',
        style: TextStyle(color: scheme.primary, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2),
      );
      final info = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [label, const SizedBox(height: 4), title, const SizedBox(height: 8), program],
      );
      return Lift(
        up: _focused || _hovered,
        scale: 1.012,
        child: Material(
          color: scheme.surface,
          clipBehavior: Clip.antiAlias,
          elevation: _focused || _hovered ? 8 : 0,
          shadowColor: Colors.black54,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: _focused ? scheme.tertiary : scheme.outline, width: _focused ? 2 : 1),
          ),
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (f) => setState(() => _focused = f),
            onHover: (h) => setState(() => _hovered = h),
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary.withValues(alpha: 0.18), scheme.surface],
                  stops: const [0, 0.75],
                ),
              ),
              padding: EdgeInsets.all(wide ? 22 : 16),
              child: wide
                  ? Row(
                      children: [
                        logo,
                        const SizedBox(width: 24),
                        Expanded(child: info),
                        const SizedBox(width: 16),
                        watch,
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            logo,
                            const SizedBox(width: 14),
                            Expanded(child: info),
                          ],
                        ),
                        const SizedBox(height: 14),
                        watch,
                      ],
                    ),
            ),
          ),
        ),
      );
    });
  }

  Widget _program(List<EpgEntry> epg, bool wide) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final nn = nowAndNext(epg, now);
    final cur = nn.now;
    final next = nn.next;
    if (cur == null) return const SizedBox.shrink();
    final left = cur.stop.difference(now);
    final dim = TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(cur.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: wide ? 17 : 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(
          '${hhmm(cur.start)}–${hhmm(cur.stop)}  ·  ${left.inMinutes >= 1 ? '${left.inMinutes} min igjen' : 'snart slutt'}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dim,
        ),
        const SizedBox(height: 7),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 360 : 240),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(value: cur.progressAt(now), minHeight: 4, backgroundColor: scheme.outline),
          ),
        ),
        if (next != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Deretter ${hhmm(next.start)}: ${next.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: dim,
            ),
          ),
      ],
    );
  }
}
