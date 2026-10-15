import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/tutorial.dart';

/// A dica de uma tela: aparece na primeira visita, ensinando o que não está
/// à vista (toque longo, três pontinhos), e some de vez no "Entendi".
class DicaCard extends ConsumerWidget {
  const DicaCard({
    super.key,
    required this.dica,
    required this.texto,
    this.margin = const EdgeInsets.fromLTRB(12, 8, 12, 4),
  });

  final Dica dica;
  final String texto;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(tutorialProvider).contains(dica)) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: margin,
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb_outline, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(texto)),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    ref.read(tutorialProvider.notifier).marcar(dica),
                child: const Text('Entendi'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
