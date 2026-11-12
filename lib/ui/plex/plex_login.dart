// Kobler Fyrlys til Plex: en kode fra plex.tv, du logger inn hos Plex i nettleseren og trykker Tillat, og Fyrlys
// venter på svaret. Og valget av server når kontoen har flere.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/plex/plex_account.dart';
import '../../core/plex/plex_api.dart';
import '../../core/plex/plex_models.dart';
import '../../core/report.dart' show copyText, openUrl;
import '../../l10n/tr.dart';
import '../../platform.dart';
import 'plex_widgets.dart' show plexMoveButton;

/// true når Fyrlys ble koblet til Plex.
Future<bool> showPlexLogin(BuildContext context, PlexAccount plex) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PlexLoginDialog(plex: plex),
  );
  return ok ?? false;
}

class _PlexLoginDialog extends StatefulWidget {
  const _PlexLoginDialog({required this.plex});

  final PlexAccount plex;

  @override
  State<_PlexLoginDialog> createState() => _PlexLoginDialogState();
}

class _PlexLoginDialogState extends State<_PlexLoginDialog> {
  PlexPin? _pin;
  String? _error;
  Timer? _timer;
  bool _checking = false;
  bool _done = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _timer?.cancel();
    setState(() {
      _error = null;
      _pin = null;
      _copied = false;
    });
    try {
      final pin = await widget.plex.startLogin();
      if (!mounted) return;
      setState(() => _pin = pin);
      // TV-en: koden skrives inn på plex.tv/link fra telefonen eller PC-en
      if (!isTizen) unawaited(openUrl(widget.plex.authUrl(pin)));
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => unawaited(_check(pin)));
    } on PlexException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _check(PlexPin pin) async {
    if (_checking || _done || pin != _pin) return;
    final expires = pin.expires;
    if (expires != null && DateTime.now().isAfter(expires)) {
      _timer?.cancel();
      if (mounted) setState(() => _error = tr('Koden gikk ut. Prøv igjen.'));
      return;
    }
    _checking = true;
    try {
      final ok = await widget.plex.finishLogin(pin);
      if (ok && mounted && !_done) {
        _done = true;
        _timer?.cancel();
        Navigator.of(context).pop(true);
      }
    } on PlexException catch (e) {
      // nettet hikket: prøver igjen om to sekunder
      if (!e.network) {
        _timer?.cancel();
        if (mounted) setState(() => _error = e.message);
      }
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pin = _pin;
    final error = _error;
    final Widget body;
    if (error != null) {
      body = Text(error, style: TextStyle(color: scheme.error));
    } else if (pin == null) {
      body = Row(
        children: [
          const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 14),
          Expanded(child: Text(tr('Henter en kode fra Plex …'))),
        ],
      );
    } else if (isTizen) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Gå til plex.tv/link på telefonen eller PC-en, logg inn og skriv inn koden:')),
          const SizedBox(height: 16),
          Center(
            child: SelectableText(
              pin.code,
              key: const ValueKey('plex-kode'),
              style: Theme.of(context).textTheme.displaySmall?.copyWith(letterSpacing: 6, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Expanded(child: Text(tr('Venter på Plex …'), style: TextStyle(color: scheme.onSurfaceVariant))),
            ],
          ),
        ],
      );
    } else {
      final url = widget.plex.authUrl(pin);
      body = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Logg inn hos Plex i nettleseren som åpnet seg, og trykk Tillat (Allow). Fyrlys kobler til av seg '
              'selv.')),
          const SizedBox(height: 16),
          Row(
            children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 12),
              Expanded(child: Text(tr('Venter på Plex …'), style: TextStyle(color: scheme.onSurfaceVariant))),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => unawaited(openUrl(url)),
                icon: const Icon(Icons.open_in_new, size: 18),
                label: Text(tr('Åpne siden igjen')),
              ),
              TextButton.icon(
                onPressed: () async {
                  await copyText(url);
                  if (mounted) setState(() => _copied = true);
                },
                icon: Icon(_copied ? Icons.check : Icons.copy, size: 18),
                label: Text(_copied ? tr('Kopiert') : tr('Kopier lenken')),
              ),
            ],
          ),
        ],
      );
    }
    return AlertDialog(
      title: Text(tr('Koble til Plex')),
      content: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 440), child: body),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(tr('Avbryt'))),
        if (error != null) FilledButton(onPressed: () => unawaited(_start()), child: Text(tr('Prøv igjen'))),
      ],
    );
  }
}

/// Velg hvilken av serverne på kontoen Fyrlys skal bruke.
Future<void> showPlexServers(BuildContext context, PlexAccount plex) =>
    showDialog<void>(context: context, builder: (_) => _PlexServerDialog(plex: plex));

class _PlexServerDialog extends StatefulWidget {
  const _PlexServerDialog({required this.plex});

  final PlexAccount plex;

  @override
  State<_PlexServerDialog> createState() => _PlexServerDialogState();
}

class _PlexServerDialogState extends State<_PlexServerDialog> {
  late List<PlexServer> _servers = widget.plex.servers;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final list = await widget.plex.loadServers();
      if (mounted) setState(() => _servers = list);
    } on PlexException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = widget.plex.server?.id;
    final error = _error;
    return AlertDialog(
      title: Text(tr('Velg Plex-server')),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(error, style: TextStyle(color: scheme.error)),
              ),
            if (!_loading && _servers.isEmpty && error == null) Text(tr('Fant ingen servere på kontoen.')),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final s in _servers)
                    ListTile(
                      leading: Icon(
                        s.id == current ? Icons.radio_button_checked : Icons.radio_button_off,
                        color: s.id == current ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                      title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(s.owned ? tr('din server') : tr('delt med deg')),
                      onTap: () async {
                        final nav = Navigator.of(context);
                        if (s.id != current) await widget.plex.useServer(s);
                        nav.pop();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Lukk')))],
    );
  }
}

/// Velg hvilke biblioteker som vises i Plex-fanen (sidemenyen, Hjem og søket).
Future<void> showPlexLibraries(BuildContext context, PlexAccount plex) =>
    showDialog<void>(context: context, builder: (_) => _PlexLibrariesDialog(plex: plex));

class _PlexLibrariesDialog extends StatefulWidget {
  const _PlexLibrariesDialog({required this.plex});

  final PlexAccount plex;

  @override
  State<_PlexLibrariesDialog> createState() => _PlexLibrariesDialogState();
}

class _PlexLibrariesDialogState extends State<_PlexLibrariesDialog> {
  String? _error;

  /// bibliotekene hentes når Fyrlys kobler til serveren (første gang Plex-fanen åpnes)
  late bool _loading = widget.plex.libraries.isEmpty;

  @override
  void initState() {
    super.initState();
    if (_loading) unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await widget.plex.connect();
    } on PlexException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final plex = widget.plex;
    final error = _error;
    return AlertDialog(
      title: Text(tr('Biblioteker i Plex-fanen')),
      content: SizedBox(
        width: 440,
        child: ListenableBuilder(
          listenable: plex,
          builder: (context, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Det du slår av, vises ikke i sidemenyen, på Hjem eller i søket. Pilene endrer rekkefølgen.'),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              if (_loading) const LinearProgressIndicator(),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(error, style: TextStyle(color: scheme.error)),
                ),
              if (!_loading && error == null && plex.libraries.isEmpty)
                Text(tr('Ingen biblioteker med filmer eller serier.')),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (var i = 0; i < plex.libraries.length; i++) _library(plex.libraries, i),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Ferdig')))],
    );
  }

  /// Et bibliotek: vises eller ikke, og pilene for rekkefølgen (blant alle, også de skjulte).
  Widget _library(List<PlexLibrary> libs, int i) {
    final scheme = Theme.of(context).colorScheme;
    final plex = widget.plex;
    final l = libs[i];
    final shown = !plex.isHidden(l);
    void toggle() => plex.setHidden(l, shown);
    return ListTile(
      key: ValueKey('vis-bibliotek:${l.key}'),
      contentPadding: const EdgeInsetsDirectional.only(start: 4),
      leading: Checkbox(value: shown, onChanged: (_) => toggle()),
      title: Row(
        children: [
          Icon(l.shows ? Icons.tv_outlined : Icons.movie_outlined, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: shown ? null : scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
      trailing: libs.length < 2
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                plexMoveButton(
                  key: ValueKey('flytt-opp:${l.key}'),
                  up: true,
                  onPressed: i == 0 ? null : () => plex.moveLibrary(l, -1),
                ),
                plexMoveButton(
                  key: ValueKey('flytt-ned:${l.key}'),
                  up: false,
                  onPressed: i == libs.length - 1 ? null : () => plex.moveLibrary(l, 1),
                ),
              ],
            ),
      onTap: toggle,
    );
  }
}
