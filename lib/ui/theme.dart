import 'package:flutter/material.dart';

import 'palettes.dart';

/// Monta o tema a partir da paleta escolhida.
///
/// As telas nunca escrevem uma cor na mão: pedem ao [ColorScheme]. Por isso
/// trocar de tema troca o app inteiro, sem mexer em tela nenhuma.
/// - `primary`: ações e navegação.
/// - `secondary`: o Chamado, e só ele.
/// - `tertiary`: confirmação ("Bora!", presença confirmada).
ThemeData saleTheme(Palette palette, Brightness brightness) {
  final colors = palette.colors(brightness);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: colors.primary,
        brightness: brightness,
      ).copyWith(
        primary: colors.primary,
        onPrimary: _sobre(colors.primary),
        secondary: colors.accent,
        onSecondary: _sobre(colors.accent),
        tertiary: colors.yes,
        onTertiary: _sobre(colors.yes),
        surface: colors.background,
        surfaceContainer: colors.surface,
        surfaceContainerHigh: colors.surface,
        surfaceContainerHighest: colors.surfaceHigh,
      );

  final radius = BorderRadius.circular(16);

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    // Cartões e barras se separam do fundo pela cor, não por sombra.
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(
        alpha: brightness == Brightness.dark ? 0.24 : 0.16,
      ),
      labelTextStyle: WidgetStateProperty.all(
        TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
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
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 1,
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
  );
}

/// Preto ou branco, o que ler melhor sobre a cor.
Color _sobre(Color color) =>
    color.computeLuminance() > 0.45 ? Colors.black : Colors.white;
