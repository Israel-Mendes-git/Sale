import 'package:flutter/material.dart';

/// Amarelo do sinal sobre fundo noturno.
const signalYellow = Color(0xFFFFC107);

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: signalYellow,
    brightness: Brightness.dark,
    primary: signalYellow,
    onPrimary: Colors.black,
    surface: const Color(0xFF10131A),
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainer,
      centerTitle: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ),
  );
}
