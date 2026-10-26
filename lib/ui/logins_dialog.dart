import 'dart:async';

import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/source.dart';
import 'login_page.dart';
import 'motion.dart';

/// Innloggingene dine: bytt mellom dem, gi dem navn, logg ut av en, eller legg til en ny.
Future<void> showLoginsDialog(BuildContext context, Session session) =>
    showDialog<void>(context: context, builder: (_) => _LoginsDialog(session: session));

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

class _LoginsDialog extends StatelessWidget {
  const _LoginsDialog({required this.session});

  final Session session;

  Future<void> _switch(BuildContext context, SavedLogin login) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await session.switchLogin(login.id);
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text('Byttet til ${login.name}'), duration: const Duration(seconds: 2)));
    } on SourceException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _add(BuildContext context) {
    final nav = Navigator.of(context);
    nav.pop();
    unawaited(nav.push(fadeRoute<void>((_) => LoginPage(session: session, adding: true))));
  }

  Future<void> _rename(BuildContext context, SavedLogin login) async {
    final name = await showDialog<String>(context: context, builder: (_) => _RenameDialog(name: login.name));
    if (name != null) await session.renameLogin(login.id, name);
  }

  Future<void> _remove(BuildContext context, SavedLogin login) async {
    final nav = Navigator.of(context);
    if (!await confirmLogout(context, login)) return;
    await session.removeLogin(login.id);
    // den siste er borte: innloggingen vises
    if (session.source == null && nav.canPop()) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Innlogginger'),
          contentPadding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final l in session.logins)
                    Builder(builder: (context) {
                      final active = l.id == session.activeLogin;
                      return ListTile(
                        key: ValueKey('innlogging:${l.id}'),
                        leading: Icon(
                          active ? Icons.check_circle : Icons.circle_outlined,
                          color: active ? scheme.primary : scheme.onSurfaceVariant,
                        ),
                        title: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(active ? '${l.kindName} · i bruk' : l.kindName),
                        selected: active,
                        onTap: active ? null : () => unawaited(_switch(context, l)),
                        trailing: PopupMenuButton<String>(
                          tooltip: 'Mer om ${l.name}',
                          onSelected: (v) {
                            if (v == 'rename') unawaited(_rename(context, l));
                            if (v == 'remove') unawaited(_remove(context, l));
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'rename', child: Text('Gi nytt navn')),
                            PopupMenuItem(value: 'remove', child: Text('Logg ut og fjern')),
                          ],
                        ),
                      );
                    }),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('Legg til innlogging'),
                    subtitle: const Text('En annen leverandør eller et annet abonnement'),
                    onTap: () => _add(context),
                  ),
                ],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Lukk'))],
        );
      },
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
