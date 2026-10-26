import 'dart:async';

import 'package:flutter/material.dart';

import '../build_info.dart';
import '../core/models.dart';
import '../core/report.dart';
import '../core/session.dart';
import '../core/source.dart';
import '../core/updater.dart';
import '../l10n/tr.dart';
import 'language_dialog.dart';
import 'login_page.dart';
import 'motion.dart';

/// «Logg ut av …?» (true: ja)
Future<bool> confirmLogout(BuildContext context, SavedLogin login) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Logg ut av ${login.name}?'),
      content: const Text(
        'Innloggingen slettes fra Fyrlys på denne PC-en. Favorittene og det du har sett, kommer tilbake hvis du logger '
        'inn igjen.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Avbryt')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Logg ut')),
      ],
    ),
  );
  return yes ?? false;
}

/// «aktiv til 12.03.2027 · 1 tilkobling» (det leverandøren sier om abonnementet), eller tomt
String accountLine(Account a) {
  String two(int n) => n.toString().padLeft(2, '0');
  final e = a.expires;
  final n = a.maxConnections;
  return [
    if (a.status.isNotEmpty && a.status.toLowerCase() != 'active') a.status,
    if (e != null) 'aktiv til ${two(e.day)}.${two(e.month)}.${e.year}',
    if (n > 0) '$n ${n == 1 ? 'tilkobling' : 'tilkoblinger'}',
  ].join(' · ');
}

/// Innstillingene (tannhjulet øverst): innloggingene, utseende, avspilling, listene og oppdateringer.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.session, this.updater});

  final Session session;

  /// oppdateringer fra GitHub; null i testene og der appen ikke oppdaterer seg selv
  final Updater? updater;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// det leverandøren sier om abonnementet til innloggingen i bruk
  Future<Account>? _account;
  TvSource? _accountFor;

  Session get s => widget.session;

  @override
  void initState() {
    super.initState();
    s.addListener(_onSession);
  }

  @override
  void dispose() {
    s.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (!mounted) return;
    // den siste innloggingen er borte: innloggingen vises
    if (s.source == null && !s.restoring) {
      final nav = Navigator.of(context);
      if (nav.canPop()) nav.pop();
      return;
    }
    setState(() {});
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));

  Future<Account>? _accountOf(TvSource? src) {
    if (src == null) return null;
    if (!identical(src, _accountFor)) {
      _accountFor = src;
      _account = src.account();
    }
    return _account;
  }

  // ── innlogginger ──

  Future<void> _switch(SavedLogin login) async {
    try {
      await s.switchLogin(login.id);
      if (mounted) _snack('Byttet til ${login.name}');
    } on SourceException catch (e) {
      if (mounted) _snack(e.message);
    }
  }

  Future<void> _rename(SavedLogin login) async {
    final name = await showDialog<String>(context: context, builder: (_) => _RenameDialog(name: login.name));
    if (name != null) await s.renameLogin(login.id, name);
  }

  Future<void> _remove(SavedLogin login) async {
    if (await confirmLogout(context, login)) await s.removeLogin(login.id);
  }

  void _add() => unawaited(Navigator.of(context).push(fadeRoute<void>((_) => LoginPage(session: s, adding: true))));

  // ── lister og oppdateringer ──

  Future<void> _reload() async {
    await s.load(force: true);
    if (!mounted) return;
    final error = s.error;
    _snack(error ?? 'Listene er hentet på nytt (${s.channels.length} kanaler).');
  }

  Future<void> _checkUpdates(Updater u) async {
    try {
      final info = await u.check(manual: true);
      if (!mounted) return;
      _snack(info == null
          ? 'Du har siste versjon ($appBuildLabel).'
          : u.state == UpdateState.ready
              ? '${info.label} er lastet ned og legges inn når du lukker Fyrlys.'
              : 'Fant ${info.label}. Den lastes ned nå.');
    } on UpdateException catch (e) {
      if (mounted) _snack('Fikk ikke sjekket oppdateringer: ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.updater;
    return Scaffold(
      appBar: AppBar(title: const Text('Innstillinger')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _Section(title: 'Innlogging', children: _logins()),
              _Section(title: 'Utseende', children: [_theme()]),
              _Section(title: 'Avspilling', children: _playback()),
              _Section(title: 'Kanaler og TV-guide', children: [_lists()]),
              if (u != null && u.enabled)
                _Section(
                  title: 'Oppdateringer',
                  children: [ListenableBuilder(listenable: u, builder: (context, _) => _updates(u))],
                ),
              _Section(title: tr('Hjelp'), children: _help()),
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  appBuildLabel,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _logins() {
    final scheme = Theme.of(context).colorScheme;
    final current = s.currentLogin;
    return [
      for (final l in s.logins)
        if (l.id == s.activeLogin)
          FutureBuilder<Account>(
            key: ValueKey('innlogging:${l.id}'),
            future: _accountOf(s.source),
            builder: (context, snap) {
              final extra = snap.hasData ? accountLine(snap.data!) : '';
              return ListTile(
                leading: Icon(Icons.check_circle, color: scheme.primary),
                title: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text([l.kindName, 'i bruk', if (extra.isNotEmpty) extra].join(' · ')),
                trailing: _loginMenu(l),
              );
            },
          )
        else
          ListTile(
            key: ValueKey('innlogging:${l.id}'),
            leading: Icon(Icons.circle_outlined, color: scheme.onSurfaceVariant),
            title: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${l.kindName} · trykk for å bytte'),
            onTap: () => unawaited(_switch(l)),
            trailing: _loginMenu(l),
          ),
      ListTile(
        leading: const Icon(Icons.add),
        title: const Text('Legg til innlogging'),
        subtitle: const Text('En annen leverandør eller et annet abonnement'),
        onTap: _add,
      ),
      if (current != null)
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text('Logg ut av ${current.name}'),
          onTap: () => unawaited(_remove(current)),
        ),
    ];
  }

  Widget _loginMenu(SavedLogin l) => PopupMenuButton<String>(
        tooltip: 'Mer om ${l.name}',
        onSelected: (v) {
          if (v == 'rename') unawaited(_rename(l));
          if (v == 'remove') unawaited(_remove(l));
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'rename', child: Text('Gi nytt navn')),
          PopupMenuItem(value: 'remove', child: Text('Logg ut og fjern')),
        ],
      );

  Widget _theme() => ListTile(
        leading: const Icon(Icons.brightness_6_outlined),
        title: const Text('Tema'),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('Som Windows')),
                ButtonSegment(value: ThemeMode.dark, label: Text('Mørkt')),
                ButtonSegment(value: ThemeMode.light, label: Text('Lyst')),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => s.setThemeMode(v.first),
            ),
          ),
        ),
      );

  List<Widget> _playback() {
    final languages = s.languages;
    final picture = s.picture;
    return [
      ListTile(
        leading: const Icon(Icons.translate),
        title: const Text('Språk for lyd og undertekster'),
        subtitle: Text(languages.isEmpty ? 'Som filmen eller kanalen har dem' : languages.summary),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => unawaited(showLanguageDialog(context, s)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.deblur_outlined),
        title: const Text('Fjern striper (deinterlacing)'),
        subtitle: const Text('For TV-kanaler som sendes interlacet (1080i). Bør stå på.'),
        value: picture.deinterlace,
        onChanged: (v) => s.savePicture(picture.copyWith(deinterlace: v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.motion_photos_on_outlined),
        title: const Text('Jevn bevegelse (prøve)'),
        subtitle: const Text('Tilpasser bildet til skjermens frekvens, så sport og panorering hakker mindre. '
            'Virker ikke på alle PC-er.'),
        value: picture.smooth,
        onChanged: (v) => s.savePicture(picture.copyWith(smooth: v)),
      ),
    ];
  }

  Widget _lists() => ListTile(
        leading: const Icon(Icons.refresh),
        title: const Text('Hent listene på nytt'),
        subtitle: Text(s.loading ? 'Henter …' : 'Kanalene og kategoriene fra leverandøren (${s.channels.length} kanaler)'),
        trailing: s.loading
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : null,
        onTap: s.loading ? null : () => unawaited(_reload()),
      );

  // ── hjelp ──

  bool _reporting = false;

  Future<void> _saveReport() async {
    setState(() => _reporting = true);
    try {
      final file = await saveReport(await buildReport(s, updater: widget.updater));
      if (!mounted) return;
      _snack(tr('Feilrapporten er lagret: {name}', {'name': file.uri.pathSegments.last}));
      unawaited(showInExplorer(file.path));
    } on Object catch (e) {
      if (mounted) _snack(tr('Fikk ikke lagret feilrapporten ({error}).', {'error': e}));
    } finally {
      if (mounted) setState(() => _reporting = false);
    }
  }

  List<Widget> _help() => [
        ListTile(
          leading: const Icon(Icons.bug_report_outlined),
          title: Text(tr('Lagre feilrapport')),
          subtitle: Text(tr('Versjonen, innstillingene og loggen, uten passord og leverandør. Legg den ved når du '
              'melder fra om en feil.')),
          trailing: _reporting
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          onTap: _reporting ? null : () => unawaited(_saveReport()),
        ),
        ListTile(
          leading: const Icon(Icons.open_in_new),
          title: Text(tr('Meld fra om en feil')),
          subtitle: Text(tr('På GitHub (krever en konto der)')),
          onTap: () => unawaited(openUrl('https://github.com/$appRepo/issues/new/choose')),
        ),
      ];

  Widget _updates(Updater u) {
    final info = u.available;
    final subtitle = switch (u.state) {
      UpdateState.checking => 'Ser etter …',
      UpdateState.available => 'Ny versjon: ${info?.label ?? ''}',
      UpdateState.downloading => 'Laster ned ${info?.label ?? 'ny versjon'} … ${(u.progress * 100).round()} %',
      UpdateState.ready => '${info?.label ?? 'En ny versjon'} legges inn når du lukker Fyrlys',
      UpdateState.failed => u.error ?? 'Oppdateringen feilet',
      UpdateState.idle => 'Du har $appBuildLabel. Fyrlys ser selv etter nye versjoner.',
    };
    return ListTile(
      leading: const Icon(Icons.system_update_alt),
      title: const Text('Se etter oppdateringer'),
      subtitle: Text(subtitle),
      trailing: u.state == UpdateState.ready
          ? FilledButton(onPressed: () => unawaited(u.restartNow()), child: const Text('Start på nytt nå'))
          : null,
      onTap: u.state == UpdateState.checking || u.state == UpdateState.downloading
          ? null
          : () => unawaited(_checkUpdates(u)),
    );
  }
}

/// En gruppe innstillinger: overskrift og et kort med radene.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(fontSize: 12, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
          ),
        ),
        Material(
          color: scheme.surfaceContainer,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: scheme.outline),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.name});

  final String name;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _text = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _done() => Navigator.of(context).pop(_text.text.trim().isEmpty ? null : _text.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Gi nytt navn'),
      content: TextField(
        controller: _text,
        autofocus: true,
        maxLength: 40,
        decoration: const InputDecoration(labelText: 'Navn', hintText: 'F.eks. Hjemme eller Sport'),
        onSubmitted: (_) => _done(),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Avbryt')),
        FilledButton(onPressed: _done, child: const Text('Lagre')),
      ],
    );
  }
}
