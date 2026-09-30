import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../update/update_providers.dart';
import '../../update/update_ui.dart';
import '../format.dart';
import '../widgets/avatar.dart';
import 'chat_screen.dart';
import 'incoming_chamado_screen.dart';

/// Item do menu do avatar que não é um usuário.
const _checkUpdate = '__verificar_atualizacao__';

class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final me = repo.profile(userId);
    final conversations = ref.watch(conversationsProvider(userId));
    final pending = ref.watch(pendingChamadosProvider(userId)).value ?? [];
    final version = ref.watch(installedVersionProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sale?'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Trocar usuário (desenvolvimento)',
            icon: Avatar(me, radius: 16),
            onSelected: (id) {
              if (id == _checkUpdate) {
                checkUpdateNow(context, ref);
              } else {
                ref.read(currentUserProvider.notifier).signIn(id);
              }
            },
            itemBuilder: (context) => [
              for (final p in repo.profiles)
                PopupMenuItem(
                  value: p.id,
                  enabled: p.id != userId,
                  child: Text('Entrar como ${p.name}'),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: _checkUpdate,
                child: Text(
                  'Verificar atualização'
                  '${version == null ? '' : ' (v$version)'}',
                ),
              ),
            ],
          ),
          IconButton(
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(currentUserProvider.notifier).signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
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
      preview = last.isChamado
          ? '$author: 🦇 Chamado'
          : '$author: ${last.text}';
    }

    return ListTile(
      leading: leading,
      title: Text(conversationTitle(repo, conversation, userId)),
      subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
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

class _PendingBanner extends ConsumerWidget {
  const _PendingBanner({required this.chamado, required this.userId});

  final Chamado chamado;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final author = ref.watch(repositoryProvider).profile(chamado.authorId);
    return Material(
      color: scheme.primary,
      child: ListTile(
        leading: const Text('🦇', style: TextStyle(fontSize: 28)),
        title: Text(
          '${author.name} te chamou pra jogar',
          style: TextStyle(
            color: scheme.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${chamadoGame(chamado)} · ${chamadoWhen(chamado)}',
          style: TextStyle(color: scheme.onPrimary),
        ),
        trailing: Icon(Icons.chevron_right, color: scheme.onPrimary),
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
