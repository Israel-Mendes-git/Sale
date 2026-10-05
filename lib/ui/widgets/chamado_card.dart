import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../icons.dart';
import '../respond.dart';
import 'avatar.dart';
import 'brand.dart';

/// Card vivo do Chamado dentro da conversa: mostra a resposta de cada
/// chamado em tempo real e os botões para quem ainda não respondeu.
class ChamadoCard extends ConsumerWidget {
  const ChamadoCard({super.key, required this.chamadoId, required this.userId});

  final String chamadoId;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chamado = ref.watch(chamadoProvider(chamadoId)).value;
    if (chamado == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final repo = ref.watch(repositoryProvider);
    final author = repo.profile(chamado.authorId);
    final mine = chamado.authorId == userId;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: chamado.isOpen ? scheme.secondary : scheme.outlineVariant,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Marca(size: 26, color: scheme.secondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CHAMADO · ${chamadoGame(chamado)}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.secondary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        chamado.automatic
                            // Ninguém apertou o botão: foi a hora que chegou.
                            ? 'Encontro fixo do grupo · '
                                  '${hhmm(chamado.createdAt)}'
                            : '${mine ? 'Você' : author.name} chamou '
                                  '${chamadoWhen(chamado)} · '
                                  '${hhmm(chamado.createdAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _StatusChip(chamado: chamado),
              ],
            ),
            // A insistência: o Chamado tocou de novo, e o card conta.
            if (chamado.nudgedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  nudgeLabel(chamado),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.secondary,
                  ),
                ),
              ),
            if (chamado.drawn) _DrawInfo(chamado: chamado, userId: userId),
            if (chamado.note != null) ...[
              const SizedBox(height: 8),
              Text('"${chamado.note}"', style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 8),
            for (final id in chamado.targetIds)
              _TargetRow(
                chamado: chamado,
                profile: repo.profile(id),
                isMe: id == userId,
              ),
            if (chamado.awaits(userId)) ...[
              const Divider(),
              _QuickReplies(chamado: chamado, userId: userId),
            ],
            if (chamado.awaitsArrival(userId) || (mine && chamado.isOpen))
              Row(
                children: [
                  // Quem prometeu vir avisa que chegou, e é dessa hora que
                  // sai o placar do atraso.
                  if (chamado.awaitsArrival(userId))
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.flag_outlined, size: 18),
                      label: const Text('Cheguei'),
                      onPressed: () => repo.markArrived(
                        chamadoId: chamado.id,
                        userId: userId,
                      ),
                    ),
                  const Spacer(),
                  if (mine && chamado.isOpen)
                    TextButton(
                      onPressed: () => repo.closeChamado(chamado.id),
                      child: const Text('Encerrar'),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.chamado});

  final Chamado chamado;

  @override
  Widget build(BuildContext context) {
    // Fechar sozinho, de tanto esperar, não é o mesmo que alguém encerrar.
    final (label, icon) = switch (chamado.status) {
      ChamadoStatus.open => ('aberto', Icons.notifications_active),
      ChamadoStatus.answered => ('respondido', Icons.done_all),
      ChamadoStatus.closed when chamado.expired => (
        'expirou',
        Icons.hourglass_disabled,
      ),
      ChamadoStatus.closed => ('encerrado', Icons.block),
    };
    return Chip(
      visualDensity: VisualDensity.compact,
      avatar: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({
    required this.chamado,
    required this.profile,
    required this.isMe,
  });

  final Chamado chamado;
  final Profile profile;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = chamado.responses[profile.id];
    final arrival = arrivalLabel(chamado, profile.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Avatar(profile, radius: 12),
          const SizedBox(width: 8),
          Text(
            isMe ? 'Você' : profile.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r == null
                      ? 'aguardando…'
                      : responseLabel(chamado, profile.id),
                  style: r == null ? TextStyle(color: theme.hintColor) : null,
                ),
                if (arrival.isNotEmpty)
                  Text(
                    arrival,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickReplies extends ConsumerWidget {
  const _QuickReplies({required this.chamado, required this.userId});

  final Chamado chamado;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final replies = ref.watch(repositoryProvider).quickRepliesFor(userId);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final r in replies)
          ActionChip(
            avatar: Icon(replyIcon(r.icon), size: 18),
            label: Text(r.label),
            onPressed: () => respondToChamado(
              context,
              ref,
              chamado: chamado,
              userId: userId,
              reply: r,
            ),
          ),
      ],
    );
  }
}

/// Sorteio: quem vetou o quê e o botão de vetar (uma vez por pessoa).
class _DrawInfo extends ConsumerWidget {
  const _DrawInfo({required this.chamado, required this.userId});

  final Chamado chamado;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final library = ref.watch(gamesProvider).value;
    final small = Theme.of(context).textTheme.bodySmall;

    String gameName(String id) => library?.byId(id)?.name ?? 'jogo removido';
    String who(String id) => id == userId ? 'você' : repo.profile(id).name;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              chamado.vetoes.isEmpty
                  ? 'Jogo sorteado. Cada um pode vetar uma vez.'
                  : 'Vetados: ${chamado.vetoes.entries.map((e) => '${gameName(e.value)} (${who(e.key)})').join(', ')}',
              style: small,
            ),
          ),
          if (chamado.canVeto(userId))
            TextButton.icon(
              icon: const Icon(Icons.block, size: 18),
              label: const Text('Vetar'),
              onPressed: () =>
                  repo.vetoGame(chamadoId: chamado.id, userId: userId),
            ),
        ],
      ),
    );
  }
}
