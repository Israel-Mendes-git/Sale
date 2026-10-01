import 'package:flutter/material.dart';

/// Os temas prontos do app.
///
/// Cada um descreve só o essencial — cor principal, cor de destaque do
/// Chamado, cor do "bora" e os três fundos — e o resto (textos, bordas,
/// estados) o Material deriva. Quem escolhe é cada pessoa, em
/// "Meu perfil → Aparência".
@immutable
class PaletteColors {
  const PaletteColors({
    required this.primary,
    required this.accent,
    required this.yes,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
  });

  /// Ações e navegação.
  final Color primary;

  /// Só o Chamado usa: é o que precisa saltar aos olhos.
  final Color accent;

  /// Confirmação ("Bora!", presença confirmada).
  final Color yes;

  final Color background;

  /// Cartões, barras e abas.
  final Color surface;

  /// Campos e chips sobre os cartões.
  final Color surfaceHigh;
}

@immutable
class Palette {
  const Palette({
    required this.id,
    required this.name,
    required this.description,
    required this.light,
    required this.dark,
  });

  /// Guardado no aparelho; não mude depois de publicado.
  final String id;
  final String name;
  final String description;
  final PaletteColors light;
  final PaletteColors dark;

  PaletteColors colors(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// Preto e branco com um laranja só, no Chamado.
const _tinta = Palette(
  id: 'tinta',
  name: 'Tinta',
  description: 'Preto e branco. A cor aparece só quando chamam você.',
  light: PaletteColors(
    primary: Color(0xFF0A0A0A),
    accent: Color(0xFFDC2626),
    yes: Color(0xFF15803D),
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF5F5F5),
    surfaceHigh: Color(0xFFEAEAEA),
  ),
  dark: PaletteColors(
    primary: Color(0xFFFAFAFA),
    accent: Color(0xFFFF4D4F),
    yes: Color(0xFF4ADE80),
    background: Color(0xFF0A0A0A),
    surface: Color(0xFF171717),
    surfaceHigh: Color(0xFF262626),
  ),
);

/// Azul para a rotina, laranja para o Chamado.
const _aco = Palette(
  id: 'aco',
  name: 'Aço',
  description: 'Azul no dia a dia, laranja quando chamam.',
  light: PaletteColors(
    primary: Color(0xFF1D4ED8),
    accent: Color(0xFFC2410C),
    yes: Color(0xFF15803D),
    background: Color(0xFFF7F9FC),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEAF0FA),
  ),
  dark: PaletteColors(
    primary: Color(0xFF60A5FA),
    accent: Color(0xFFFB923C),
    yes: Color(0xFF4ADE80),
    background: Color(0xFF0C1220),
    surface: Color(0xFF151E31),
    surfaceHigh: Color(0xFF1E2B44),
  ),
);

/// O amarelo de sinalização que o app usava antes.
const _sinal = Palette(
  id: 'sinal',
  name: 'Sinal',
  description: 'Amarelo de sinalização sobre noite.',
  light: PaletteColors(
    primary: Color(0xFF7A5200),
    accent: Color(0xFFB45309),
    yes: Color(0xFF15803D),
    background: Color(0xFFFBF9F5),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF1EDE6),
  ),
  dark: PaletteColors(
    primary: Color(0xFFFFC107),
    accent: Color(0xFFFFC107),
    yes: Color(0xFF4ADE80),
    background: Color(0xFF0B0D12),
    surface: Color(0xFF151922),
    surfaceHigh: Color(0xFF1E2330),
  ),
);

/// Laranja quente, fundos com um toque de marrom.
const _brasa = Palette(
  id: 'brasa',
  name: 'Brasa',
  description: 'Laranja quente, como sala à noite.',
  light: PaletteColors(
    primary: Color(0xFFC2410C),
    accent: Color(0xFFEA580C),
    yes: Color(0xFF2E9E54),
    background: Color(0xFFFDF7F3),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFF5EBE4),
  ),
  dark: PaletteColors(
    primary: Color(0xFFFF8A3D),
    accent: Color(0xFFFF8A3D),
    yes: Color(0xFF5BD17A),
    background: Color(0xFF120E0C),
    surface: Color(0xFF1E1816),
    surfaceHigh: Color(0xFF2C2420),
  ),
);

/// Roxo com verde na confirmação.
const _madrugada = Palette(
  id: 'madrugada',
  name: 'Madrugada',
  description: 'Roxo e verde, cara de aplicativo de conversa.',
  light: PaletteColors(
    primary: Color(0xFF5B47E0),
    accent: Color(0xFF7C3AED),
    yes: Color(0xFF1F9D55),
    background: Color(0xFFF8F8FC),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEEEDF8),
  ),
  dark: PaletteColors(
    primary: Color(0xFF8B7BFF),
    accent: Color(0xFFA78BFA),
    yes: Color(0xFF4ADE80),
    background: Color(0xFF0E1018),
    surface: Color(0xFF181C2A),
    surfaceHigh: Color(0xFF242941),
  ),
);

/// Neon de fliperama: ciano e magenta.
const _fliperama = Palette(
  id: 'fliperama',
  name: 'Fliperama',
  description: 'Ciano e magenta, neon de arcade.',
  light: PaletteColors(
    primary: Color(0xFF0E7490),
    accent: Color(0xFFBE185D),
    yes: Color(0xFF15803D),
    background: Color(0xFFF6F8FA),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFEAEFF4),
  ),
  dark: PaletteColors(
    primary: Color(0xFF22D3EE),
    accent: Color(0xFFF472B6),
    yes: Color(0xFF4ADE80),
    background: Color(0xFF0D1117),
    surface: Color(0xFF161C26),
    surfaceHigh: Color(0xFF1F2937),
  ),
);

/// Verde de monitor antigo sobre cinza-pedra.
const _caverna = Palette(
  id: 'caverna',
  name: 'Caverna',
  description: 'Verde sobre pedra, discreto à noite.',
  light: PaletteColors(
    primary: Color(0xFF15803D),
    accent: Color(0xFF4D7C0F),
    yes: Color(0xFF15803D),
    background: Color(0xFFF6F8F6),
    surface: Color(0xFFFFFFFF),
    surfaceHigh: Color(0xFFE9F0EA),
  ),
  dark: PaletteColors(
    primary: Color(0xFF4ADE80),
    accent: Color(0xFFA3E635),
    yes: Color(0xFF4ADE80),
    background: Color(0xFF101311),
    surface: Color(0xFF1A1F1C),
    surfaceHigh: Color(0xFF232A25),
  ),
);

/// Na ordem em que aparecem na escolha; a primeira é o padrão.
const palettes = <Palette>[
  _aco,
  _tinta,
  _sinal,
  _brasa,
  _madrugada,
  _fliperama,
  _caverna,
];

const defaultPaletteId = 'aco';

Palette paletteById(String id) =>
    palettes.firstWhere((p) => p.id == id, orElse: () => palettes.first);
