import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../widgets/chamado_card.dart';
import 'new_chamado_screen.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversation,
    required this.userId,
  });

  final Conversation conversation;
  final String userId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await ref
        .read(repositoryProvider)
        .sendText(
          conversationId: widget.conversation.id,
          authorId: widget.userId,
          text: text,
        );
  }

  void _openChamado() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => NewChamadoScreen(
          conversation: widget.conversation,
          userId: widget.userId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final messages = ref.watch(messagesProvider(widget.conversation.id));
    final conversation = widget.conversation;

    return Scaffold(
      appBar: AppBar(
        title: Text(conversationTitle(repo, conversation, widget.userId)),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: $e')),
              data: (list) {
                if (list.isEmpty) {
                  return const Center(
                    child: Text('Nenhuma mensagem. Que tal um 🦇?'),
                  );
                }
                final ordered = list.reversed.toList();
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: ordered.length,
                  itemBuilder: (context, i) {
                    final m = ordered[i];
                    if (m.isChamado) {
                      return ChamadoCard(
                        chamadoId: m.chamadoId!,
                        userId: widget.userId,
                      );
                    }
                    return _Bubble(
                      message: m,
                      mine: m.authorId == widget.userId,
                      showAuthor: conversation.kind == ConversationKind.group,
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton.filled(
                    tooltip: 'Chamado',
                    onPressed: _openChamado,
                    icon: const Text('🦇', style: TextStyle(fontSize: 20)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 5,
                      decoration: const InputDecoration(hintText: 'Mensagem'),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Enviar',
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble({
    required this.message,
    required this.mine,
    required this.showAuthor,
  });

  final Message message;
  final bool mine;
  final bool showAuthor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final author = ref.watch(repositoryProvider).profile(message.authorId);

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: mine
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showAuthor && !mine)
                Text(
                  author.name,
                  style: TextStyle(
                    color: Color(author.color),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              Text(message.text ?? ''),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  hhmm(message.createdAt),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
