// Plex Home: hvem som ser på. Hver bruker har sin egen «Fortsett å se», det de har sett og (for administrerte
// brukere) bare det de får se. Brukere med PIN-kode må skrive den.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter, LengthLimitingTextInputFormatter;

import '../../core/plex/plex_account.dart';
import '../../core/plex/plex_api.dart';
import '../../core/plex/plex_models.dart';
import '../../l10n/tr.dart';
import '../net_image.dart';

/// «Hvem ser på?»: velg en bruker i Plex Home.
Future<void> showPlexUsers(BuildContext context, PlexAccount plex) =>
    showDialog<void>(context: context, builder: (_) => _PlexUsersDialog(plex: plex));

/// Bildet til en bruker i Plex Home (forbokstaven når det mangler).
class PlexAvatar extends StatelessWidget {
  const PlexAvatar({super.key, required this.user, this.name = '', this.size = 32, this.ring = false});

  final PlexHomeUser? user;

  /// navnet når brukeren ikke er kjent
  final String name;
  final double size;

  /// ring rundt (den som ser på nå)
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = (user?.title ?? name).trim();
    final initial = Center(
      child: Text(
        title.isEmpty ? '?' : title.characters.first.toUpperCase(),
        style: TextStyle(fontSize: size * 0.42, fontWeight: FontWeight.w700, color: scheme.onPrimaryContainer),
      ),
    );
    final thumb = user?.thumb ?? '';
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      foregroundDecoration: ring
          ? BoxDecoration(shape: BoxShape.circle, border: Border.all(color: scheme.primary, width: 3))
          : null,
      decoration: BoxDecoration(shape: BoxShape.circle, color: scheme.primaryContainer),
      child: thumb.isEmpty ? initial : NetImage(thumb, decodeWidth: size, fallback: initial),
    );
  }
}

class _PlexUsersDialog extends StatefulWidget {
  const _PlexUsersDialog({required this.plex});

  final PlexAccount plex;

  @override
  State<_PlexUsersDialog> createState() => _PlexUsersDialogState();
}

class _PlexUsersDialogState extends State<_PlexUsersDialog> {
  final _pin = TextEditingController();

  /// brukeren det skrives PIN-kode for
  PlexHomeUser? _pinFor;
  String? _error;
  bool _busy = false;

  /// brukerne hentes første gang (ellers står de fra sist, og hentes på nytt i bakgrunnen)
  late bool _loading = widget.plex.homeUsers.isEmpty;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await widget.plex.loadHomeUsers();
    if (mounted) setState(() => _loading = false);
  }

  void _choose(PlexHomeUser u) {
    if (u.uuid == widget.plex.currentHomeUser?.uuid) {
      Navigator.of(context).pop();
      return;
    }
    if (u.protected) {
      setState(() {
        _pinFor = u;
        _error = null;
        _pin.clear();
      });
      return;
    }
    unawaited(_switch(u, null));
  }

  Future<void> _switch(PlexHomeUser u, String? pin) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.plex.switchUser(u, pin: pin);
      if (mounted) Navigator.of(context).pop();
    } on PlexException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (e.pin) {
          // Plex vil ha PIN-kode også når brukeren ikke var merket med det: da uten feilmelding
          _pinFor = u;
          _pin.clear();
          _error = pin == null ? null : e.message;
        } else {
          _error = e.message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pinFor = _pinFor;
    return AlertDialog(
      title: Text(pinFor == null ? tr('Hvem ser på?') : tr('PIN-kode for {name}', {'name': pinFor.title})),
      content: SizedBox(
        width: 440,
        child: ListenableBuilder(
          listenable: widget.plex,
          builder: (context, _) => pinFor == null ? _users() : _pinField(pinFor),
        ),
      ),
      actions: [
        if (pinFor != null)
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _pinFor = null;
                      _error = null;
                    }),
            child: Text(tr('Tilbake')),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Avbryt'))),
      ],
    );
  }

  Widget _users() {
    final scheme = Theme.of(context).colorScheme;
    final plex = widget.plex;
    final current = plex.currentHomeUser;
    final error = _error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading || _busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error, style: TextStyle(color: scheme.error)),
          ),
        if (!_loading && plex.homeUsers.isEmpty && error == null) Text(tr('Fant ingen brukere i Plex Home.')),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 12,
          children: [
            for (final u in plex.homeUsers)
              _UserTile(
                user: u,
                current: u.uuid == current?.uuid,
                onTap: _busy ? null : () => _choose(u),
              ),
          ],
        ),
      ],
    );
  }

  Widget _pinField(PlexHomeUser u) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            PlexAvatar(user: u, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Text(tr('Skriv PIN-koden (4 siffer).'), style: TextStyle(color: scheme.onSurfaceVariant)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('plex-pin'),
          controller: _pin,
          autofocus: true,
          // ikke av mens det byttes, så feltet beholder fokus til neste forsøk
          readOnly: _busy,
          obscureText: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 12),
          decoration: InputDecoration(border: const OutlineInputBorder(), errorText: _error),
          // fire siffer: byttes med en gang
          onChanged: (v) {
            if (v.length == 4) unawaited(_switch(u, v));
          },
          onSubmitted: (v) {
            if (v.isNotEmpty) unawaited(_switch(u, v));
          },
        ),
        if (_busy) ...[const SizedBox(height: 12), const LinearProgressIndicator()],
      ],
    );
  }
}

/// En bruker i «Hvem ser på?»: bildet og navnet, med lås når brukeren har PIN-kode.
class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.current, required this.onTap});

  final PlexHomeUser user;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      key: ValueKey('plex-bruker:${user.uuid}'),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: SizedBox(
        width: 100,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  PlexAvatar(user: user, size: 64, ring: current),
                  if (user.protected)
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(color: scheme.surfaceContainerHighest, shape: BoxShape.circle),
                        child: Icon(Icons.lock, size: 14, color: scheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                user.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                  color: current ? scheme.primary : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
