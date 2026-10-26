import 'package:flutter/material.dart';

/// Fargene: mørk «Fyrlys om natta» og lys «Nordisk lys».
class FyrlysColors {
  static const live = Color(0xFFFF5A4F);
  static const beam = Color(0xFFF2B544);
  static const logoBg = Color(0xFF1B2C3B);
}

ThemeData fyrlysTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final bg = dark ? const Color(0xFF07121C) : const Color(0xFFF5F3EE);
  final surface = dark ? const Color(0xFF0C1B29) : const Color(0xFFFFFFFF);
  final surface2 = dark ? const Color(0xFF12263A) : const Color(0xFFE9EEF2);
  final line = dark ? const Color(0xFF1D3449) : const Color(0xFFD8DFE5);
  final ink = dark ? const Color(0xFFEDF1F4) : const Color(0xFF0F1F2D);
  final muted = dark ? const Color(0xFF8597A8) : const Color(0xFF566A7C);
  final signal = dark ? const Color(0xFFF2B544) : const Color(0xFF1F5F8B);
  final signalInk = dark ? const Color(0xFF1B1305) : const Color(0xFFFFFFFF);
  final focus = dark ? const Color(0xFF8CC8FF) : const Color(0xFF1F5F8B);
  final scheme = ColorScheme(
    brightness: brightness,
    primary: signal,
    onPrimary: signalInk,
    secondary: signal,
    onSecondary: signalInk,
    tertiary: focus,
    onTertiary: bg,
    error: FyrlysColors.live,
    onError: Colors.white,
    surface: surface,
    onSurface: ink,
    onSurfaceVariant: muted,
    surfaceContainerLowest: bg,
    surfaceContainerLow: bg,
    surfaceContainer: surface,
    surfaceContainerHigh: surface2,
    surfaceContainerHighest: surface2,
    outline: line,
    outlineVariant: line,
  );
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: line));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: bg,
    canvasColor: bg,
    dividerColor: line,
    appBarTheme: AppBarTheme(
      backgroundColor: bg,
      foregroundColor: ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: BorderSide(color: signal, width: 2)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: surface2,
      contentTextStyle: TextStyle(color: ink),
    ),
  );
}
