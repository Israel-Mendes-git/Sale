import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../respond.dart';
import 'avatar.dart';

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
          color: chamado.isOpen ? scheme.primary : scheme.outlineVariant,
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
                const Text('🦇', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'CHAMADO · ${chamadoGame(chamado)}',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${mine ? 'Você' : author.name} chamou '
                        '${chamadoWhen(chamado)} · ${hhmm(chamado.createdAt)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: chamado.status),
              ],
            ),
            if (chamado.note != null) ...[
              const SizedBox(height: 8),
              Text('"${chamado.note}"', style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 8),
            for (final id in chamado.targetIds)
              _TargetRow(
                profile: repo.profile(id),
                response: chamado.responses[id],
                isMe: id == userId,
              ),
            if (chamado.awaits(userId)) ...[
              const Divider(),
              _QuickReplies(chamado: chamado, userId: userId),
            ],
            if (mine && chamado.isOpen)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () =>
                      ref.read(repositoryProvider).closeChamado(chamado.id),
                  child: const Text('Encerrar'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ChamadoStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (status) {
      ChamadoStatus.open => ('aberto', Icons.notifications_active),
      ChamadoStatus.answered => ('respondido', Icons.done_all),
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
    required this.profile,
    required this.response,
    required this.isMe,
  });

  final Profile profile;
  final ChamadoResponse? response;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final r = response;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Avatar(profile, radius: 12),
          const SizedBox(width: 8),
          Text(
            isMe ? 'Você' : profile.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              r == null ? 'aguardando…' : responseLabel(r),
              style: r == null
                  ? TextStyle(color: Theme.of(context).hintColor)
                  : null,
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
            label: Text('${r.emoji} ${r.label}'),
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
