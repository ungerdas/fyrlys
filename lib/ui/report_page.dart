import 'dart:async';

import 'package:flutter/material.dart';

import '../core/report.dart';
import '../core/session.dart';
import '../core/updater.dart';
import '../l10n/tr.dart';
import '../platform.dart';

/// Feilrapporten slik den sendes: hele teksten (kan markeres), og knapper for å kopiere den og for å dele den
/// (telefonen) eller lagre den som fil (PC-en). Kopier er det sikre på telefonen: noen apper tar bare med
/// begynnelsen av en lang tekst som deles.
class ReportPage extends StatefulWidget {
  const ReportPage({super.key, required this.session, this.updater});

  final Session session;
  final Updater? updater;

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  String? _text;
  Object? _error;

  /// deler eller lagrer
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_make());
  }

  Future<void> _make() async {
    try {
      final text = await buildReport(widget.session, updater: widget.updater);
      if (mounted) setState(() => _text = text);
    } on Object catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 4)));

  Future<void> _copy(String text) async {
    try {
      await copyText(text);
      if (mounted) _snack(tr('Feilrapporten er kopiert. Lim den inn der du melder fra om feilen.'));
    } on Object catch (e) {
      if (mounted) _snack(tr('Fikk ikke kopiert feilrapporten ({error}).', {'error': e}));
    }
  }

  Future<void> _share(String text) async {
    setState(() => _busy = true);
    try {
      await shareReport(text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(String text) async {
    setState(() => _busy = true);
    try {
      final file = await saveReport(text);
      if (!mounted) return;
      _snack(tr('Feilrapporten er lagret: {name}', {'name': file.uri.pathSegments.last}));
      unawaited(showInExplorer(file.path));
    } on Object catch (e) {
      if (mounted) _snack(tr('Fikk ikke lagret feilrapporten ({error}).', {'error': e}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = _text;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Feilrapport'))),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: text == null ? _waiting() : _report(text),
        ),
      ),
    );
  }

  Widget _waiting() {
    final error = _error;
    if (error == null) return const Center(child: CircularProgressIndicator());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(tr('Fikk ikke laget feilrapporten ({error}).', {'error': error}), textAlign: TextAlign.center),
      ),
    );
  }

  Widget _report(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Text(
            tr('Dette er hele rapporten. Passord, brukernavn, adresser og navnet på leverandøren er tatt bort.'),
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 12),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outline),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: SelectableText(
                text,
                key: const ValueKey('report-text'),
                style: const TextStyle(
                  fontFamily: 'Consolas',
                  fontFamilyFallback: ['monospace', 'Menlo'],
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('report-copy'),
                  onPressed: () => unawaited(_copy(text)),
                  icon: const Icon(Icons.copy),
                  label: Text(tr('Kopier')),
                ),
                if (isAndroid)
                  FilledButton.icon(
                    key: const ValueKey('report-share'),
                    onPressed: _busy ? null : () => unawaited(_share(text)),
                    icon: const Icon(Icons.share),
                    label: Text(tr('Del feilrapport')),
                  )
                // TV-en: rapporten står på skjermen (ta et bilde av den)
                else if (isPc)
                  FilledButton.icon(
                    key: const ValueKey('report-save'),
                    onPressed: _busy ? null : () => unawaited(_save(text)),
                    icon: const Icon(Icons.save_alt),
                    label: Text(tr('Lagre feilrapport')),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
