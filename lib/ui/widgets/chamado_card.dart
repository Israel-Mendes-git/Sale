import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../icons.dart';
import '../format.dart';
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
            if (chamado.drawn) _DrawInfo(chamado: chamado, userId: userId),
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
