import 'dart:async';

import 'package:flutter/material.dart';

import '../core/languages.dart';
import '../core/picture.dart';
import '../core/session.dart';
import '../l10n/tr.dart';
import 'picture_dialogs.dart';
import 'playback.dart';

/// Velg språkene du foretrekker for lydspor og undertekster. Lagres i [session]; svaret er om noe ble lagret.
Future<bool> showLanguageDialog(BuildContext context, Session session) async {
  final result = await showDialog<LanguagePrefs>(
    context: context,
    builder: (_) => _LanguageDialog(initial: session.languages),
  );
  if (result == null) return false;
  session.saveLanguages(result);
  return true;
}

class _LanguageDialog extends StatefulWidget {
  const _LanguageDialog({required this.initial});

  final LanguagePrefs initial;

  @override
  State<_LanguageDialog> createState() => _LanguageDialogState();
}

class _LanguageDialogState extends State<_LanguageDialog> {
  late final List<String> _audio = [...widget.initial.audio];
  late final List<String> _subs = [...widget.initial.subtitles];

  void _toggle(List<String> list, String id) {
    setState(() {
      if (!list.remove(id)) list.add(id);
      // et språk for undertekstene slår dem på igjen
      if (identical(list, _subs) && id != LanguagePrefs.off) list.remove(LanguagePrefs.off);
    });
  }

  Widget _chips(List<String> list) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final l in languages)
            FilterChip(
              showCheckmark: false,
              selected: list.contains(l.id),
              // nummeret viser rekkefølgen du valgte i
              label: Text(list.contains(l.id) ? '${list.indexOf(l.id) + 1}. ${l.name}' : l.name),
              onSelected: (_) => _toggle(list, l.id),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13, height: 1.35);
    final head = theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);
    final off = _subs.contains(LanguagePrefs.off);
    return AlertDialog(
      title: Text(tr('Språk for lyd og undertekster')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr('Lydspor'), style: head),
              const SizedBox(height: 4),
              Text(tr('Velg i den rekkefølgen du vil ha dem. Uten valg: det filmen eller kanalen selv har først.'), style: dim),
              const SizedBox(height: 10),
              _chips(_audio),
              const SizedBox(height: 22),
              Text(tr('Undertekster'), style: head),
              const SizedBox(height: 4),
              Text(
                tr('Slås på når lyden er på et annet språk. Uten valg: bare når filmen selv slår dem på.'),
                style: dim,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilterChip(
                    showCheckmark: false,
                    selected: off,
                    label: Text(tr('Av')),
                    onSelected: (_) => setState(() {
                      _subs.clear();
                      if (!off) _subs.add(LanguagePrefs.off);
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _chips(_subs),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Avbryt'))),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(LanguagePrefs(audio: _audio, subtitles: _subs)),
          child: Text(tr('Lagre')),
        ),
      ],
    );
  }
}

/// Lydspor og undertekster i spillerne: sporene i det som spilles (det som er valgt nå, er huket av), og
/// «Foretrukne språk …» nederst.
class TracksButton extends StatelessWidget {
  const TracksButton({
    super.key,
    required this.playback,
    required this.session,
    this.onOpen,
    this.onClose,
    this.format,
    this.onFormat,
    this.audioDelay,
    this.onAudioDelay,
    this.viewNote,
  });

  final Playback playback;
  final Session session;

  /// spilleren holder kontrollene framme så lenge menyen er åpen
  final VoidCallback? onOpen;
  final VoidCallback? onClose;

  /// bildeformatet og lydforsinkelsen i spilleren (valgene vises bare når de er med)
  final PictureFormat? format;
  final ValueChanged<PictureFormat>? onFormat;
  final Duration? audioDelay;
  final ValueChanged<Duration>? onAudioDelay;

  /// under lydforsinkelsen, f.eks. at den huskes for kanalen
  final String? viewNote;

  static const _languages = 'språk';
  static const _deinterlace = 'deinterlace';
  static const _smooth = 'jevn';
  static const _format = 'format';
  static const _delay = 'lydforsinkelse';

  Future<void> _show(BuildContext context) async {
    onOpen?.call();
    // hvor knappen er, som PopupMenuButton gjør det
    final button = context.findRenderObject()! as RenderBox;
    final overlay = Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final tracks = await playback.tracks();
    final picture = session.picture;
    if (!context.mounted) return;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset.zero, ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );
    final choice = await showMenu<Object>(
      context: context,
      position: position,
      items: [
        PopupMenuItem<Object>(enabled: false, child: Text(tr('Lydspor'))),
        if (tracks.audio.isEmpty) PopupMenuItem<Object>(enabled: false, child: Text(tr('Bare ett'))),
        for (final t in tracks.audio) CheckedPopupMenuItem<Object>(value: t, checked: t.selected, child: Text(t.label)),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(enabled: false, child: Text(tr('Undertekster'))),
        for (final t in tracks.subtitles)
          CheckedPopupMenuItem<Object>(value: t, checked: t.selected, child: Text(t.label)),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(value: _languages, child: Text(tr('Foretrukne språk …'))),
        const PopupMenuDivider(),
        PopupMenuItem<Object>(enabled: false, child: Text(tr('Bilde'))),
        CheckedPopupMenuItem<Object>(
          value: _deinterlace,
          checked: picture.deinterlace,
          child: Text(tr('Fjern striper (deinterlacing)')),
        ),
        CheckedPopupMenuItem<Object>(
          value: _smooth,
          checked: picture.smooth,
          child: Text(tr('Jevn bevegelse (prøve)')),
        ),
        if (format != null && onFormat != null)
          PopupMenuItem<Object>(
            value: _format,
            child: Text(tr('Bildeformat: {name} …', {'name': formatName(format!)})),
          ),
        if (audioDelay != null && onAudioDelay != null)
          PopupMenuItem<Object>(
            value: _delay,
            child: Text(tr('Lydforsinkelse: {value} …', {'value': audioDelayText(audioDelay!)})),
          ),
      ],
    );
    if (choice is TrackChoice) await playback.selectTrack(choice);
    if (choice == _deinterlace || choice == _smooth) {
      final next = choice == _deinterlace
          ? picture.copyWith(deinterlace: !picture.deinterlace)
          : picture.copyWith(smooth: !picture.smooth);
      session.savePicture(next);
      await playback.setPicture(next);
    }
    if (choice == _format && context.mounted) {
      final f = await showFormatDialog(context, format!);
      if (f != null) onFormat?.call(f);
    }
    if (choice == _delay && context.mounted) {
      await showAudioDelayDialog(context, audioDelay!, (d) => onAudioDelay?.call(d), note: viewNote);
    }
    if (choice == _languages) {
      if (!context.mounted) return;
      // nye språk: velg sporene på nytt i det som spilles nå også
      final changed = await showLanguageDialog(context, session);
      if (changed) await playback.setLanguages(session.languages, now: true);
    }
    onClose?.call();
  }

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tr('Lydspor og undertekster'),
        icon: const Icon(Icons.subtitles_outlined, color: Colors.white),
        onPressed: () => unawaited(_show(context)),
      );
}
