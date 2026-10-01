import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/settings.dart';
import '../palettes.dart';

/// Escolha do tema: cada pessoa deixa o app com a cara que quiser.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);
    final choice = ref.read(appearanceProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Aparência')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Claro ou escuro', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('Do celular'),
                icon: Icon(Icons.brightness_auto_outlined),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('Claro'),
                icon: Icon(Icons.light_mode_outlined),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('Escuro'),
                icon: Icon(Icons.dark_mode_outlined),
              ),
            ],
            selected: {appearance.mode},
            onSelectionChanged: (s) => choice.chooseMode(s.first),
          ),
          const SizedBox(height: 24),
          Text('Tema', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'A cor do Chamado é a que salta: é ela que avisa que chamaram você.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final palette in palettes) ...[
            _PaletteTile(
              palette: palette,
              chosen: palette.id == appearance.palette.id,
              onTap: () => choice.choosePalette(palette),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _PaletteTile extends StatelessWidget {
  const _PaletteTile({
    required this.palette,
    required this.chosen,
    required this.onTap,
  });

  final Palette palette;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: chosen ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            _Miniatura(palette: palette),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    palette.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(palette.description, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (chosen)
              Icon(Icons.check_circle, color: theme.colorScheme.primary),
          ],
        ),
      ),
    );
  }
}

/// Uma telinha do app com as cores do tema: barra, cartão, Chamado e botão.
class _Miniatura extends StatelessWidget {
  const _Miniatura({required this.palette});

  final Palette palette;

  @override
  Widget build(BuildContext context) {
    // Mostra a paleta no claro/escuro que está valendo agora.
    final colors = palette.colors(Theme.of(context).brightness);
    return Container(
      width: 62,
      height: 76,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.surfaceHigh),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _barra(colors.surface, 10),
          const SizedBox(height: 4),
          _barra(colors.surfaceHigh, 8),
          const SizedBox(height: 4),
          // A faixa do Chamado, na cor de destaque.
          _barra(colors.accent, 12),
          const Spacer(),
          _barra(colors.primary, 10),
        ],
      ),
    );
  }

  Widget _barra(Color color, double height) => Container(
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(3),
    ),
  );
}
