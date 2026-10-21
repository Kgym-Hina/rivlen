import 'package:flutter/material.dart';

class RivlenColors {
  static const canvas = Color(0xFFF7F5F3);
  static const surface = Color(0xFFFFFEFC);
  static const ink = Color(0xFF282522);
  static const muted = Color(0xFF89837D);
  static const line = Color(0xFFE8E3DE);
  static const wine = Color(0xFF8B2549);
  static const coral = Color(0xFFEA725F);
  static const green = Color(0xFF4E8C67);
  static const amber = Color(0xFFC58B45);
  static const blue = Color(0xFF4D82A3);
  static const purple = Color(0xFF8266A3);
}

ThemeData buildRivlenTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: RivlenColors.wine,
    primary: RivlenColors.wine,
    surface: RivlenColors.surface,
    error: const Color(0xFFB63838),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: RivlenColors.canvas,
    fontFamily: 'SF Pro Text',
    appBarTheme: const AppBarTheme(
      backgroundColor: RivlenColors.canvas,
      foregroundColor: RivlenColors.ink,
      elevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: RivlenColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: RivlenColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: RivlenColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: RivlenColors.wine, width: 1.5),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: RivlenColors.ink,
      contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
