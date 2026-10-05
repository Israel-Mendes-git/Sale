import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/do_dia.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../widgets/chat_audio.dart';
import '../widgets/chat_image.dart';
import '../widgets/sheet.dart';

/// A disputa de hoje, numa folha: as indicadas, quantos votos cada uma tem e o
/// botão de votar.
Future<void> abrirDisputaDoDia(
  BuildContext context, {
  required Conversation conversation,
  required String userId,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.8,
    child: _DisputaDoDia(conversation: conversation, userId: userId),
  ),
);

class _DisputaDoDia extends ConsumerWidget {
  const _DisputaDoDia({required this.conversation, required this.userId});

  final Conversation conversation;
  final String userId;

  Future<void> _votar(
    BuildContext context,
    WidgetRef ref,
    String messageId,
  ) async {
    try {
      await ref
          .read(repositoryProvider)
          .vote(messageId: messageId, userId: userId);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Não deu para votar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final doDia = ref.watch(doDiaProvider(conversation.id)).value;
    final mensagens = ref.watch(messagesProvider(conversation.id)).value;
    if (doDia == null || mensagens == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final indicadas = [
      for (final id in doDia.indicadas.keys)
        ?mensagens.where((m) => m.id == id && !m.isDeleted).firstOrNull,
    ];
    final meuVoto = doDia.votos[userId];
    final repo = ref.watch(repositoryProvider);

    return SheetBody(
      child: ListView(
        children: [
          Text('⭐ A do dia de hoje', style: theme.textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Um voto por pessoa, e dá para trocar. Fecha amanhã às 6h, e a mais '
            'votada vai para o Hall.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          if (indicadas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Ninguém indicou nada ainda. No toque longo numa mensagem de '
                'hoje: "Indicar para a do dia".',
                textAlign: TextAlign.center,
              ),
            ),
          for (final m in indicadas)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    PreviaDaMensagem(message: m, userId: userId),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Indicada por '
                            '${_nome(repo.profile(doDia.indicadas[m.id]!).name, doDia.indicadas[m.id]!)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        Text(_votos(doDia.votosDe(m.id))),
                        const SizedBox(width: 8),
                        if (meuVoto == m.id)
                          const FilledButton.tonal(
                            onPressed: null,
                            child: Text('Seu voto'),
                          )
                        else
                          OutlinedButton(
                            onPressed: () => _votar(context, ref, m.id),
                            child: const Text('Votar'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _nome(String nome, String id) => id == userId ? 'você' : nome;
}

String _votos(int n) => n == 1 ? '1 voto' : '$n votos';

/// O Hall das do dia: as vencedoras, da mais nova para a mais antiga.
class HallScreen extends ConsumerWidget {
  const HallScreen({
    super.key,
    required this.conversation,
    required this.userId,
  });

  final Conversation conversation;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final doDia = ref.watch(doDiaProvider(conversation.id)).value;
    final mensagens = ref.watch(messagesProvider(conversation.id)).value ?? [];
    final hall = doDia?.hall ?? const <Destaque>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Hall das do dia')),
      body: doDia == null
          ? const Center(child: CircularProgressIndicator())
          : hall.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'O Hall ainda está vazio. Indiquem a frase, o momento ou o '
                  'áudio do dia — às 6h a mais votada entra aqui.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: hall.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                final destaque = hall[i];
                final m = mensagens
                    .where((m) => m.id == destaque.messageId)
                    .firstOrNull;
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.emoji_events, size: 18),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'A do dia · ${dayLabel(destaque.dia)}',
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                            Text(_votos(destaque.votos)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (m == null || m.isDeleted)
                          const Text(
                            'A mensagem foi apagada depois.',
                            style: TextStyle(fontStyle: FontStyle.italic),
                          )
                        else
                          PreviaDaMensagem(message: m, userId: userId),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

/// Uma mensagem fora da conversa: quem escreveu e o conteúdo — o texto, a
/// imagem ou o recado de voz, que toca aqui mesmo.
class PreviaDaMensagem extends ConsumerWidget {
  const PreviaDaMensagem({
    super.key,
    required this.message,
    required this.userId,
  });

  final Message message;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autor = message.authorId == userId
        ? 'Você'
        : ref.watch(repositoryProvider).profile(message.authorId).name;
    final anexo = message.attachment;
    final texto = message.text?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(autor, style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        if (anexo != null && anexo.kind == AttachmentKind.audio)
          ChatAudio(attachment: anexo, mine: false)
        else if (anexo != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ChatImage(attachment: anexo),
          ),
        if (texto.isNotEmpty) ...[
          if (anexo != null) const SizedBox(height: 4),
          Text(texto),
        ],
      ],
    );
  }
}
