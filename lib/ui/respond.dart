import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models.dart';
import '../state/providers.dart';

const _etaOptions = [10, 20, 30, 45, 60];

/// Envia a resposta de [userId] a um Chamado, perguntando o tempo antes
/// quando a resposta pede ("Tô jantando" → "quanto tempo?"; a soneca →
/// "daqui a quanto?").
///
/// Devolve false se a pessoa desistiu na pergunta do tempo.
Future<bool> respondToChamado(
  BuildContext context,
  WidgetRef ref, {
  required Chamado chamado,
  required String userId,
  required QuickReply reply,
}) async {
  int? eta;
  if (reply.asksEta) {
    eta = await showModalBottomSheet<int>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                // A soneca não promete chegada: ela marca a volta do
                // Chamado.
                reply.kind == ReplyKind.snooze
                    ? 'Te chamo de novo daqui a quanto?'
                    : '${reply.label}. Chega em quanto tempo?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in _etaOptions)
                    ActionChip(
                      label: Text('$m min'),
                      onPressed: () => Navigator.pop(context, m),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (eta == null) return false;
  }
  await ref
      .read(repositoryProvider)
      .respond(
        chamadoId: chamado.id,
        userId: userId,
        reply: reply,
        etaMinutes: eta,
      );
  return true;
}
