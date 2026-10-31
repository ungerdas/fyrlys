import 'dart:async';

import 'package:flutter/material.dart';

import '../core/cast/caster.dart';
import '../core/names.dart';
import '../l10n/tr.dart';

/// Velg en Chromecast: de som svarer, vises etter hvert. Null når du avbryter.
Future<CastDevice?> pickCastDevice(BuildContext context, {Caster? caster}) => showDialog<CastDevice>(
      context: context,
      builder: (_) => _CastPicker(caster: caster ?? appCaster),
    );

class _CastPicker extends StatefulWidget {
  const _CastPicker({required this.caster});

  final Caster caster;

  @override
  State<_CastPicker> createState() => _CastPickerState();
}

class _CastPickerState extends State<_CastPicker> {
  final List<CastDevice> _found = [];
  StreamSubscription<CastDevice>? _sub;
  bool _searching = true;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  void _search() {
    unawaited(_sub?.cancel());
    setState(() {
      _found.clear();
      _searching = true;
    });
    _sub = widget.caster.discover().listen(
      (d) {
        if (mounted) setState(() => _found.add(d));
      },
      onDone: () {
        if (mounted) setState(() => _searching = false);
      },
      onError: (Object _) {
        if (mounted) setState(() => _searching = false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(tr('Cast til TV')),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final d in _found)
              ListTile(
                key: ValueKey('cast-device-${d.id}'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.tv),
                title: Text(d.name),
                subtitle: d.model.isEmpty ? null : Text(d.model),
                onTap: () => Navigator.of(context).pop(d),
              ),
            if (_searching)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Row(
                  children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 14),
                    Text(tr('Leter etter Chromecast …'), style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                ),
              )
            else if (_found.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Text(
                  tr('Fant ingen Chromecast. Den må være på samme nettverk som PC-en, og Windows-brannmuren må slippe '
                      'Fyrlys gjennom på private nettverk.'),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            if (_found.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                child: Text(
                  tr('PC-en sender strømmen videre til TV-en, så den må stå på mens du caster.'),
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (!_searching) TextButton(onPressed: _search, child: Text(tr('Let igjen'))),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Avbryt'))),
      ],
    );
  }
}

/// Tilstanden til Chromecasten i ord, eller null når det bare spiller.
String? castStateText(Caster caster) => switch (caster.state) {
      CastState.connecting => tr('Kobler til …'),
      CastState.ready || CastState.loading || CastState.buffering => tr('Laster …'),
      CastState.paused => tr('Pauset'),
      CastState.ended => tr('Ferdig'),
      CastState.failed => caster.error ?? tr('Chromecasten kunne ikke spille dette.'),
      CastState.playing || CastState.off => null,
    };

bool castIsPlaying(Caster caster) => caster.state == CastState.playing || caster.state == CastState.buffering;

/// Det spilleren viser i stedet for bildet mens det castes: hvor det spilles, hva, og knapper for pause, volumet på
/// TV-en og «Stopp casting». [leading] (f.eks. forrige/neste kanal) står før pauseknappen, [progress] (tidslinja for
/// en film) over knappene.
class CastPanel extends StatefulWidget {
  const CastPanel({
    super.key,
    required this.caster,
    required this.title,
    this.subtitle = '',
    this.leading = const [],
    this.progress,
    this.compact = false,
    required this.onStop,
  });

  final Caster caster;
  final String title;
  final String subtitle;
  final List<Widget> leading;
  final Widget? progress;
  final bool compact;
  final VoidCallback onStop;

  @override
  State<CastPanel> createState() => _CastPanelState();
}

class _CastPanelState extends State<CastPanel> {
  /// volumet mens du drar (sendes når du slipper)
  double? _volume;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.caster,
      builder: (context, _) {
        final c = widget.caster;
        final state = castStateText(c);
        final failed = c.state == CastState.failed;
        final busy = c.state == CastState.connecting ||
            c.state == CastState.ready ||
            c.state == CastState.loading ||
            c.state == CastState.buffering;
        final volume = _volume ?? (c.muted ? 0.0 : c.volume);
        final compact = widget.compact;
        return DecoratedBox(
          key: const ValueKey('cast-panel'),
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.3),
              radius: 1.1,
              colors: [Color(0xFF15304A), Color(0xFF050B12)],
            ),
          ),
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 24, vertical: 16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cast_connected, size: compact ? 34 : 48, color: scheme.primary),
                    const SizedBox(height: 10),
                    Text(
                      tr('Spilles på {name}', {'name': c.device?.name ?? ''}),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFF9FB0BB), fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 19 : 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (widget.subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          widget.subtitle,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFFDFE6EA), fontSize: 15),
                        ),
                      ),
                    if (state != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (busy) ...[
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Flexible(
                              child: Text(
                                state,
                                key: const ValueKey('cast-state'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: failed ? const Color(0xFFFF8A80) : Colors.white70, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (widget.progress != null)
                      Padding(padding: const EdgeInsets.only(top: 12), child: widget.progress),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 2,
                      runSpacing: 4,
                      children: [
                        ...widget.leading,
                        IconButton(
                          key: const ValueKey('cast-play'),
                          tooltip: castIsPlaying(c) ? tr('Pause (mellomrom)') : tr('Spill av (mellomrom)'),
                          iconSize: 34,
                          color: Colors.white,
                          icon: Icon(castIsPlaying(c) ? Icons.pause_circle_filled : Icons.play_circle_filled),
                          onPressed: c.state == CastState.connecting
                              ? null
                              : () => unawaited(castIsPlaying(c) ? c.pause() : c.play()),
                        ),
                        IconButton(
                          tooltip: c.muted ? tr('Lyd på (M)') : tr('Lyd av (M)'),
                          color: Colors.white,
                          icon: Icon(volume == 0 ? Icons.volume_off : Icons.volume_up),
                          onPressed: () => unawaited(c.setMuted(!c.muted)),
                        ),
                        SizedBox(
                          width: 120,
                          child: Slider(
                            key: const ValueKey('cast-volume'),
                            value: volume.clamp(0.0, 1.0).toDouble(),
                            semanticFormatterCallback: (v) => tr('Volum på TV-en {n} %', {'n': (v * 100).round()}),
                            onChanged: (v) => setState(() => _volume = v),
                            onChangeEnd: (v) {
                              setState(() => _volume = null);
                              unawaited(c.setVolume(v));
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        OutlinedButton.icon(
                          key: const ValueKey('cast-stop'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Colors.white38),
                          ),
                          onPressed: widget.onStop,
                          icon: const Icon(Icons.cancel_presentation),
                          label: Text(tr('Stopp casting')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Tidslinja for en film eller et program på TV-en: hvor langt den har kommet (oppdateres hvert sekund), og du kan
/// dra for å spole.
class CastProgress extends StatefulWidget {
  const CastProgress({super.key, required this.position, required this.duration, required this.onSeek});

  /// hvor langt den har kommet (spørres hvert sekund)
  final Duration Function() position;
  final Duration duration;
  final ValueChanged<Duration> onSeek;

  @override
  State<CastProgress> createState() => _CastProgressState();
}

class _CastProgressState extends State<CastProgress> {
  Timer? _tick;
  double? _drag;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _drag == null) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inMilliseconds / 1000;
    if (total <= 0) return const SizedBox.shrink();
    final at = _drag ?? (widget.position().inMilliseconds / 1000).clamp(0.0, total).toDouble();
    const style = TextStyle(color: Colors.white, fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]);
    return Row(
      children: [
        Text(formatDuration(Duration(milliseconds: (at * 1000).round())), style: style),
        Expanded(
          child: Slider(
            key: const ValueKey('cast-timeline'),
            value: at,
            max: total,
            onChanged: (v) => setState(() => _drag = v),
            onChangeEnd: (v) {
              setState(() => _drag = null);
              widget.onSeek(Duration(milliseconds: (v * 1000).round()));
            },
          ),
        ),
        Text(formatDuration(widget.duration), style: style),
      ],
    );
  }
}

/// Linja nederst på forsiden mens det castes (spilleren er lukket): hva som spilles hvor, pause og stopp.
class CastBar extends StatelessWidget {
  const CastBar({super.key, Caster? caster}) : _caster = caster;

  final Caster? _caster;

  @override
  Widget build(BuildContext context) {
    final c = _caster ?? appCaster;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final device = c.device;
        if (device == null) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        final title = c.item?.title ?? '';
        final state = castStateText(c);
        return Material(
          key: const ValueKey('cast-bar'),
          color: scheme.surfaceContainerHigh,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Row(
                children: [
                  Icon(Icons.cast_connected, color: scheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      [
                        title.isEmpty ? tr('Castes til {name}', {'name': device.name}) : '$title · ${device.name}',
                        if (state != null) state,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: castIsPlaying(c) ? tr('Pause') : tr('Spill av'),
                    icon: Icon(castIsPlaying(c) ? Icons.pause : Icons.play_arrow),
                    onPressed: () => unawaited(castIsPlaying(c) ? c.pause() : c.play()),
                  ),
                  IconButton(
                    key: const ValueKey('cast-bar-stop'),
                    tooltip: tr('Stopp casting'),
                    icon: const Icon(Icons.cancel_presentation),
                    onPressed: () => unawaited(c.stop()),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
