import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../widgets/avatar.dart';
import '../widgets/brand.dart';
import 'chat_screen.dart';
import 'incoming_chamado_screen.dart';
import 'profile_screen.dart';

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
          '${author.name} te chamou pra jogar',
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
