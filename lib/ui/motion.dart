import 'package:flutter/material.dart';

// Overgangene i appen: spillerne tones inn og ut, innholdet glir over når du bytter fane eller liste, og kortene
// løftes når fjernkontrollen eller musa er på dem.

/// Spillerne tones inn og ut, i stedet for å gli inn fra siden.
Route<T> fadeRoute<T>(WidgetBuilder builder) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) => builder(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut), child: child),
    );

/// Innhold som byttes (fane, kategori): det nye tones inn og glir litt opp.
class SmoothSwitch extends StatelessWidget {
  const SmoothSwitch({super.key, required this.child, this.slide = true});

  /// får en nøkkel som forteller når innholdet er et annet
  final Widget child;
  final bool slide;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: slide
              ? SlideTransition(
                  position: Tween(begin: const Offset(0, 0.015), end: Offset.zero).animate(animation),
                  child: child,
                )
              : child,
        ),
        child: child,
      );
}

/// Et kort som løftes litt (større, med skygge) når det har fokus eller musa over seg.
class Lift extends StatelessWidget {
  const Lift({super.key, required this.up, required this.child, this.scale = 1.03});

  final bool up;
  final Widget child;
  final double scale;

  @override
  Widget build(BuildContext context) => AnimatedScale(
        scale: up ? scale : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: child,
      );
}
