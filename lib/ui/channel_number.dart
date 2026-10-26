import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final _digitKeys = <LogicalKeyboardKey, String>{
  LogicalKeyboardKey.digit0: '0',
  LogicalKeyboardKey.digit1: '1',
  LogicalKeyboardKey.digit2: '2',
  LogicalKeyboardKey.digit3: '3',
  LogicalKeyboardKey.digit4: '4',
  LogicalKeyboardKey.digit5: '5',
  LogicalKeyboardKey.digit6: '6',
  LogicalKeyboardKey.digit7: '7',
  LogicalKeyboardKey.digit8: '8',
  LogicalKeyboardKey.digit9: '9',
  LogicalKeyboardKey.numpad0: '0',
  LogicalKeyboardKey.numpad1: '1',
  LogicalKeyboardKey.numpad2: '2',
  LogicalKeyboardKey.numpad3: '3',
  LogicalKeyboardKey.numpad4: '4',
  LogicalKeyboardKey.numpad5: '5',
  LogicalKeyboardKey.numpad6: '6',
  LogicalKeyboardKey.numpad7: '7',
  LogicalKeyboardKey.numpad8: '8',
  LogicalKeyboardKey.numpad9: '9',
};

/// Tallet på en tast (tallrekka, talltastaturet eller tallene på fjernkontrollen), ellers null.
String? digitOf(LogicalKeyboardKey key) => _digitKeys[key];

/// Kanalnummeret du taster, stort i hjørnet til det er tastet ferdig.
class NumberBadge extends StatelessWidget {
  const NumberBadge({super.key, required this.digits});

  final String digits;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('channel-number'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xCC000000),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x2EFFFFFF)),
      ),
      child: Text(
        digits,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 40,
          fontWeight: FontWeight.w800,
          height: 1.1,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
