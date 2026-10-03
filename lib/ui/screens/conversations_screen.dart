import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config.dart';
import '../../domain/calendar.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../widgets/avatar.dart';
import '../widgets/brand.dart';
import '../widgets/rsvp_choice.dart';
import 'chat_screen.dart';
import 'incoming_chamado_screen.dart';
import 'profile_screen.dart';

/// O lembrete de "Cheguei" vale enquanto o Chamado é de agora: passadas umas
/// horas, quem não marcou já não vai marcar, e o aviso só atrapalharia.
const _arrivalWindow = Duration(hours: 3);

/// Dos Chamados em que a pessoa prometeu vir, os que ainda cabem no lembrete.
List<Chamado> _recentPromises(
  List<Chamado> waiting,
  String userId,
  DateTime now,
) {
  final recent = <Chamado>[];
  for (final chamado in waiting) {
    final promised = chamado.promisedBy(userId);
    if (promised != null && now.difference(promised) < _arrivalWindow) {
      recent.add(chamado);
    }
  }
  return recent;
}

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key, required this.userId});

  final String userId;

  void _openProfileScreen(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final me = repo.profile(userId);
    final conversations = ref.watch(conversationsProvider(userId));
    final pending = ref.watch(pendingChamadosProvider(userId)).value ?? [];
    final now = ref.watch(clockProvider)();
    final toArrive = _recentPromises(
      ref.watch(arrivalPendingProvider(userId)).value ?? const [],
      userId,
      now,
    );
    // O encontro que está chegando e ainda espera a sua confirmação. É a
    // mesma conta do lembrete que o servidor manda por push.
    final calendar = ref.watch(calendarProvider(userId)).value;
    final meeting = calendar == null
        ? null
        : meetingAwaitingRsvp(calendar, userId: userId, now: now);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [Marca(size: 22), SizedBox(width: 8), Text('Sale?')],
        ),
        actions: [
          // Trocar de pessoa sem login só existe no backend em memória.
          if (!AppConfig.hasBackend)
            PopupMenuButton<String>(
              tooltip: 'Trocar usuário (desenvolvimento)',
              icon: const Icon(Icons.swap_horiz),
              onSelected: (id) =>
                  ref.read(currentUserProvider.notifier).signIn(id),
              itemBuilder: (context) => [
                for (final p in repo.profiles)
                  PopupMenuItem(
                    value: p.id,
                    enabled: p.id != userId,
                    child: Text('Entrar como ${p.name}'),
                  ),
              ],
            ),
          // Nome, respostas, tema, grupo, versão e sair moram no perfil; a
          // barra guarda só o caminho até ele.
          IconButton(
            tooltip: 'Meu perfil',
            icon: Avatar(me, radius: 16),
            onPressed: () => _openProfileScreen(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (!me.named)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Como o grupo te chama?'),
                subtitle: const Text('Escolha seu nome e suas respostas.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openProfileScreen(context),
              ),
            ),
          for (final c in pending) _PendingBanner(chamado: c, userId: userId),
          for (final c in toArrive) _ArrivalBanner(chamado: c, userId: userId),
          if (meeting != null)
            _MeetingBanner(occurrence: meeting, userId: userId),
          Expanded(
            child: conversations.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: $e')),
              data: (list) => ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) =>
                    _ConversationTile(conversation: list[i], userId: userId),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.conversation, required this.userId});

  final Conversation conversation;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final messages = ref.watch(messagesProvider(conversation.id)).value ?? [];
    final last = messages.isEmpty ? null : messages.last;

    final Widget leading;
    if (conversation.kind == ConversationKind.group) {
      leading = const GroupAvatar();
    } else {
      final otherId = conversation.memberIds.firstWhere((id) => id != userId);
      leading = Avatar(repo.profile(otherId));
    }

    String preview = 'Sem mensagens';
    if (last != null) {
      final author = last.authorId == userId
          ? 'Você'
          : repo.profile(last.authorId).name;
      preview = last.isChamado ? '$author: Chamado' : '$author: ${last.text}';
    }

    return ListTile(
      leading: leading,
      title: Text(conversationTitle(repo, conversation, userId)),
      subtitle: Row(
        children: [
          if (last != null && last.isChamado) ...[
            Marca(size: 14, color: Theme.of(context).colorScheme.secondary),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      trailing: last == null ? null : Text(hhmm(last.createdAt)),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ChatScreen(conversation: conversation, userId: userId),
        ),
      ),
    );
  }
}

/// Chamado esperando resposta, em cima de tudo e na cor do Chamado.
class _PendingBanner extends ConsumerWidget {
  const _PendingBanner({required this.chamado, required this.userId});

  final Chamado chamado;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final author = ref.watch(repositoryProvider).profile(chamado.authorId);
    return Material(
      color: scheme.secondary,
      child: ListTile(
        leading: Marca(size: 30, color: scheme.onSecondary),
        title: Text(
          chamado.automatic
              ? 'Hora do encontro do grupo'
              : '${author.name} te chamou pra jogar',
          style: TextStyle(
            color: scheme.onSecondary,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${chamadoGame(chamado)} · ${chamadoWhen(chamado)}',
          style: TextStyle(color: scheme.onSecondary),
        ),
        trailing: Icon(Icons.chevron_right, color: scheme.onSecondary),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) =>
                IncomingChamadoScreen(chamadoId: chamado.id, userId: userId),
          ),
        ),
      ),
    );
  }
}

/// O encontro fixo chegando: o lembrete de confirmar presença antes da hora,
/// com as mesmas opções da aba Semana.
class _MeetingBanner extends StatelessWidget {
  const _MeetingBanner({required this.occurrence, required this.userId});

  final MeetingOccurrence occurrence;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = occurrence.meeting.game;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.event_available_outlined,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Encontro do grupo às '
                        '${minutesLabel(occurrence.minute)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(game == null ? 'Você vai?' : '$game · você vai?'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            RsvpChoice(occurrence: occurrence, userId: userId),
          ],
        ),
      ),
    );
  }
}

/// Prometeu e ainda não marcou que chegou: o atalho do "Cheguei", que é de
/// onde sai o placar do atraso.
class _ArrivalBanner extends ConsumerWidget {
  const _ArrivalBanner({required this.chamado, required this.userId});

  final Chamado chamado;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final promised = chamado.promisedBy(userId)!;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: ListTile(
        leading: Icon(Icons.flag_outlined, color: scheme.tertiary),
        title: Text('Você disse que chegava às ${hhmm(promised)}'),
        subtitle: Text('${chamadoGame(chamado)} · avise quando chegar'),
        trailing: FilledButton(
          onPressed: () => ref
              .read(repositoryProvider)
              .markArrived(chamadoId: chamado.id, userId: userId),
          child: const Text('Cheguei'),
        ),
      ),
    );
  }
}
