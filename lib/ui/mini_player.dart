import 'package:flutter/material.dart';

import '../l10n/tr.dart';

/// Kontrollene i minispilleren, over bildet når musa er der: tittelen, stort vindu og lukk øverst, pause i midten og
/// lyd nederst. Resten av bildet flytter vinduet når det dras (se spillerne).
class MiniControls extends StatelessWidget {
  const MiniControls({
    super.key,
    required this.title,
    required this.playing,
    required this.muted,
    required this.onPlayPause,
    required this.onMute,
    required this.onExpand,
    required this.onClose,
  });

  final String title;
  final bool playing;
  final bool muted;
  final VoidCallback onPlayPause;
  final VoidCallback onMute;
  final VoidCallback onExpand;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    Widget button(IconData icon, String tooltip, VoidCallback onPressed, {double size = 20}) => IconButton(
          tooltip: tooltip,
          icon: Icon(icon, size: size),
          color: Colors.white,
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
        );
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xC0000000), Color(0x00000000)],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  button(Icons.open_in_full, tr('Stort vindu (I)'), onExpand, size: 18),
                  button(Icons.close, tr('Lukk'), onClose),
                ],
              ),
            ),
          ),
        ),
        Center(
          child: Material(
            color: const Color(0x8C000000),
            shape: const CircleBorder(),
            child: button(playing ? Icons.pause : Icons.play_arrow,
                playing ? tr('Pause (mellomrom)') : tr('Spill av (mellomrom)'), onPlayPause,
                size: 30),
          ),
        ),
        Positioned(
          right: 4,
          bottom: 4,
          child: Material(
            color: const Color(0x8C000000),
            shape: const CircleBorder(),
            child: button(muted ? Icons.volume_off : Icons.volume_up, muted ? tr('Lyd på (M)') : tr('Lyd av (M)'), onMute),
          ),
        ),
      ],
    );
  }
}
