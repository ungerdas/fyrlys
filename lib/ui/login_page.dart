import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/source.dart';

enum _Mode { fyrlys, xtream }

/// Innlogging: mot Fyrlys-serveren (Docker-versjonen) eller rett mot IPTV-leverandøren.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.session});

  final Session session;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _address = TextEditingController();
  final _server = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();
  _Mode _mode = _Mode.fyrlys;
  bool _busy = false;
  String? _message;

  @override
  void dispose() {
    _address.dispose();
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
      if (_mode == _Mode.fyrlys) {
        await widget.session.loginFyrlys(_address.text);
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
                      ButtonSegment(value: _Mode.fyrlys, label: Text('Fyrlys-server'), icon: Icon(Icons.dns_outlined)),
                      ButtonSegment(value: _Mode.xtream, label: Text('IPTV-leverandør'), icon: Icon(Icons.live_tv_outlined)),
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
                  if (_mode == _Mode.fyrlys) ...[
                    Text(
                      'Adressen til Fyrlys på serveren din. Innloggingen hos leverandøren, favorittene og «Ta over» deles da med nettsiden.',
                      style: hint,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _address,
                      enabled: !_busy,
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.go,
                      decoration: const InputDecoration(labelText: 'Adresse', hintText: 'http://192.168.1.10:8766'),
                      onSubmitted: (_) => _submit(),
                    ),
                  ] else ...[
                    Text(
                      'Innloggingen du har fått fra IPTV-leverandøren (Xtream Codes). Du kan også lime inn hele M3U-lenken i serverfeltet.',
                      style: hint,
                    ),
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
