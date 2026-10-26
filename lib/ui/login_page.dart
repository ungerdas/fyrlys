import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/source.dart';

enum _Mode { m3u, xtream }

/// Innlogging hos IPTV-leverandøren: med M3U-lenken (og en EPG-lenke om du vil), eller med Xtream Codes.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.session});

  final Session session;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _m3u = TextEditingController();
  final _epg = TextEditingController();
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  _Mode _mode = _Mode.m3u;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _m3u.dispose();
    _epg.dispose();
    _server.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (_mode == _Mode.m3u) {
        await widget.session.loginM3u(_m3u.text, epg: _epg.text);
      } else {
        await widget.session.loginXtream(_server.text, _user.text, _password.text);
      }
    } on SourceException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = e.message;
        });
      }
    } on Object {
      // noe uventet (f.eks. en adresse som ikke lar seg tolke): ikke bli stående på «Kobler til …»
      if (mounted) {
        setState(() {
          _busy = false;
          _message = 'Kunne ikke koble til. Sjekk lenken eller adressen.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hint = TextStyle(color: scheme.onSurfaceVariant);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset('assets/fyrlys.png', width: 72, height: 72),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Fyrlys',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<_Mode>(
                    segments: const [
                      ButtonSegment(value: _Mode.m3u, label: Text('M3U-lenke'), icon: Icon(Icons.playlist_play)),
                      ButtonSegment(value: _Mode.xtream, label: Text('Xtream Codes'), icon: Icon(Icons.live_tv_outlined)),
                    ],
                    selected: {_mode},
                    onSelectionChanged: _busy
                        ? null
                        : (selected) => setState(() {
                              _mode = selected.first;
                              _message = null;
                            }),
                  ),
                  const SizedBox(height: 16),
                  if (_mode == _Mode.m3u) ...[
                    Text(
                      'Lenken til kanallista fra leverandøren. Er det en Xtream-lenke (get.php med brukernavn og passord), '
                      'får du også filmer og serier.',
                      style: hint,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _m3u,
                      enabled: !_busy,
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: 'M3U-lenke', hintText: 'http://server.no:8080/get.php?…'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _epg,
                      enabled: !_busy,
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      decoration: const InputDecoration(
                        labelText: 'EPG-lenke (valgfri)',
                        hintText: 'XMLTV, .xml eller .xml.gz',
                        helperText: 'Står den tom, brukes EPG-lenken i lista',
                      ),
                      onSubmitted: (_) => _submit(),
                    ),
                  ] else ...[
                    Text('Innloggingen du har fått fra IPTV-leverandøren (Xtream Codes).', style: hint),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _server,
                      enabled: !_busy,
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: 'Server', hintText: 'http://server.no:8080'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _user,
                      enabled: !_busy,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(labelText: 'Brukernavn'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: true,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.go,
                      decoration: const InputDecoration(labelText: 'Passord'),
                      onSubmitted: (_) => _submit(),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_busy ? 'Kobler til …' : 'Logg inn'),
                    ),
                  ),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_message!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
