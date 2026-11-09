import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/tidy.dart';
import '../l10n/tr.dart';

/// «Land som vises»: landene i lista fra leverandøren (fra kategorinavnene: «NO: …», «Sweden - …») med avkrysning.
/// Kategoriene fra landene som ikke er krysset av, skjules fra kategoriene, «Alle kanaler», søket og TV-guiden.
Future<void> showCountryDialog(BuildContext context, Session s) async {
  final groups = s.countryGroupsInList;
  if (groups.isEmpty) return;
  final choice = await showDialog<({Set<String>? codes})>(
    context: context,
    builder: (_) => _CountryDialog(groups: groups, shown: s.shownCountries),
  );
  if (choice != null) await s.setShownCountries(choice.codes);
}

/// «Norge, Sverige og 2 til» / «Alle land».
String countriesSummary(Set<String>? shown) {
  if (shown == null) return tr('Alle land');
  final names = [for (final c in shown) countryLabel(c)]..sort();
  if (names.isEmpty) return tr('Alle land');
  if (names.length <= 3) return names.join(', ');
  return tr('{names} og {n} til', {'names': names.take(3).join(', '), 'n': names.length - 3});
}

class _CountryDialog extends StatefulWidget {
  const _CountryDialog({required this.groups, required this.shown});

  final List<CountryGroup> groups;
  final Set<String>? shown;

  @override
  State<_CountryDialog> createState() => _CountryDialogState();
}

class _CountryDialogState extends State<_CountryDialog> {
  late final Set<String> _on = widget.shown == null
      ? {for (final g in widget.groups) g.code}
      // bare de som finnes i lista
      : {for (final g in widget.groups) if (widget.shown!.contains(g.code)) g.code};

  bool get _all => _on.length == widget.groups.length;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = MediaQuery.sizeOf(context);
    return AlertDialog(
      title: Text(tr('Land som vises')),
      contentPadding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
      content: SizedBox(
        width: math.min(480.0, size.width - 64),
        height: math.max(240.0, math.min(560.0, size.height - 220)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                tr('Kategoriene fra landene du krysser av, vises. Favorittene og «Sist sett» står som før.'),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
              child: Row(
                children: [
                  TextButton(
                    key: const ValueKey('land-alle'),
                    onPressed: _all ? null : () => setState(() => _on.addAll([for (final g in widget.groups) g.code])),
                    child: Text(tr('Alle')),
                  ),
                  TextButton(
                    key: const ValueKey('land-ingen'),
                    onPressed: _on.isEmpty ? null : () => setState(_on.clear),
                    child: Text(tr('Ingen')),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: widget.groups.length,
                itemBuilder: (context, i) {
                  final g = widget.groups[i];
                  final name = countryLabel(g.code);
                  final known = g.code.isNotEmpty && name != g.code;
                  final counts = [
                    g.categories == 1 ? tr('1 kategori') : tr('{n} kategorier', {'n': g.categories}),
                    g.channels == 1 ? tr('1 kanal') : tr('{n} kanaler', {'n': g.channels}),
                  ].join(' · ');
                  return CheckboxListTile(
                    key: ValueKey('land:${g.code.isEmpty ? '-' : g.code}'),
                    value: _on.contains(g.code),
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(known ? '$name (${g.code})' : name),
                    // en kode som ikke er et kjent land («AS»), kjennes igjen på en av kategoriene
                    subtitle: Text(
                      known || g.example.isEmpty ? counts : '$counts · «${g.example}»',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onChanged: (v) => setState(() => v == true ? _on.add(g.code) : _on.remove(g.code)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Avbryt'))),
        FilledButton(
          key: const ValueKey('land-bruk'),
          // alle avkrysset: alle land, også de som kommer til senere
          onPressed: _on.isEmpty ? null : () => Navigator.of(context).pop((codes: _all ? null : {..._on})),
          child: Text(tr('Bruk')),
        ),
      ],
    );
  }
}
