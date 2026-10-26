import 'package:flutter/material.dart';

import '../core/picture.dart';
import '../l10n/tr.dart';

/// «Original», «Fyll skjermen», «Strekk», «16:9», «4:3»
String formatName(PictureFormat f) => switch (f) {
      PictureFormat.original => tr('Original'),
      PictureFormat.zoom => tr('Fyll skjermen'),
      PictureFormat.stretch => tr('Strekk'),
      PictureFormat.wide => '16:9',
      PictureFormat.classic => '4:3',
    };

String _formatHint(PictureFormat f) => switch (f) {
      PictureFormat.original => tr('Som kanalen sender det'),
      PictureFormat.zoom => tr('Uten svarte kanter; litt av bildet skjæres bort'),
      PictureFormat.stretch => tr('Uten svarte kanter; bildet strekkes'),
      PictureFormat.wide => tr('For bilder som ser klemt ut'),
      PictureFormat.classic => tr('For bilder som ser strukket ut'),
    };

/// «0 ms», «+250 ms», «−1500 ms»
String audioDelayText(Duration d) {
  final ms = d.inMilliseconds;
  if (ms == 0) return '0 ms';
  return '${ms > 0 ? '+' : '−'}${ms.abs()} ms';
}

/// Velg bildeformat; null når dialogen lukkes uten valg.
Future<PictureFormat?> showFormatDialog(BuildContext context, PictureFormat current) => showDialog<PictureFormat>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(tr('Bildeformat')),
        children: [
          for (final f in PictureFormat.values)
            SimpleDialogOption(
              key: ValueKey('format-${f.name}'),
              onPressed: () => Navigator.pop(context, f),
              child: Row(
                children: [
                  SizedBox(width: 32, child: f == current ? const Icon(Icons.check, size: 20) : null),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(formatName(f)),
                        Text(_formatHint(f), style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

/// Lydforsinkelsen: endringene gjelder med en gang ([onChanged]), så du hører hva som stemmer. Gir det som ble valgt.
Future<Duration> showAudioDelayDialog(
  BuildContext context,
  Duration current,
  ValueChanged<Duration> onChanged, {
  String? note,
}) async {
  var value = current;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void change(Duration d) {
          final next = clampAudioDelay(d);
          if (next == value) return;
          setState(() => value = next);
          onChanged(next);
        }

        final ms = value.inMilliseconds;
        return AlertDialog(
          title: Text(tr('Lydforsinkelse')),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(audioDelayText(value),
                    key: const ValueKey('audio-delay-value'), style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  ms == 0
                      ? tr('Lyden og bildet som de sendes')
                      : ms > 0
                          ? tr('Lyden kommer senere')
                          : tr('Lyden kommer tidligere'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: tr('Tidligere'),
                      icon: const Icon(Icons.remove),
                      onPressed: () => change(value - audioDelayStep),
                    ),
                    Expanded(
                      child: Slider(
                        min: -audioDelayMax.inMilliseconds.toDouble(),
                        max: audioDelayMax.inMilliseconds.toDouble(),
                        divisions: audioDelayMax.inMilliseconds * 2 ~/ audioDelayStep.inMilliseconds,
                        value: ms.toDouble(),
                        label: audioDelayText(value),
                        onChanged: (v) => change(Duration(milliseconds: v.round())),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Senere'),
                      icon: const Icon(Icons.add),
                      onPressed: () => change(value + audioDelayStep),
                    ),
                  ],
                ),
                if (note != null) Text(note, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: ms == 0 ? null : () => change(Duration.zero), child: Text(tr('Nullstill'))),
            FilledButton(onPressed: () => Navigator.pop(context), child: Text(tr('Ferdig'))),
          ],
        );
      },
    ),
  );
  return value;
}
