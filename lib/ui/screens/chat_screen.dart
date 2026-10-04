import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/repository.dart';
import '../../domain/models.dart';
import '../../push/push.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../widgets/chamado_card.dart';
import '../widgets/chat_image.dart';
import '../widgets/message_ticks.dart';
import '../widgets/sheet.dart';
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

  /// Até onde já avisamos o servidor que esta pessoa viu. Serve para não
  /// repetir o aviso a cada rebuild da tela.
  DateTime? _seen;

  /// A mensagem que a próxima vai citar, escolhida no toque longo nela.
  Message? _replyTo;

  @override
  void initState() {
    super.initState();
    // Enquanto a conversa está na tela, mensagem dela não vira aviso no
    // celular: quem está lendo não precisa ser avisado.
    conversaAberta.value = widget.conversation.id;
  }

  @override
  void dispose() {
    if (conversaAberta.value == widget.conversation.id) {
      conversaAberta.value = null;
    }
    _input.dispose();
    super.dispose();
  }

  /// Conversa aberta na tela é conversa lida — e continua lida quando chega
  /// mensagem nova com ela aberta.
  Future<void> _markRead(List<Message> messages) async {
    if (!mounted || messages.isEmpty) return;
    final last = messages.last.createdAt;
    final seen = _seen;
    if (seen != null && !last.isAfter(seen)) return;
    _seen = last;
    try {
      await ref
          .read(repositoryProvider)
          .markRead(
            conversationId: widget.conversation.id,
            userId: widget.userId,
          );
    } catch (_) {
      // Sem rede ninguém fica sabendo que você viu; a próxima mensagem (ou a
      // próxima vez que abrir) tenta de novo.
      _seen = seen;
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    final citada = _replyTo;
    setState(() => _replyTo = null);
    await ref
        .read(repositoryProvider)
        .sendText(
          conversationId: widget.conversation.id,
          authorId: widget.userId,
          text: text,
          replyTo: citada?.id,
        );
  }

  /// Reage à mensagem; tocar na reação que já é sua tira ela.
  Future<void> _react(Message message, String emoji) async {
    final minha = message.reactions[widget.userId];
    await ref
        .read(repositoryProvider)
        .react(
          messageId: message.id,
          userId: widget.userId,
          emoji: minha == emoji ? null : emoji,
        );
  }

  /// O menu de uma mensagem, no toque longo: a fileira de reações em cima, o
  /// que dá para fazer com ela embaixo.
  void _openMessageMenu(Message message) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (folha) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final emoji in reactionEmojis)
                    IconButton(
                      tooltip: 'Reagir com $emoji',
                      isSelected: message.reactions[widget.userId] == emoji,
                      onPressed: () {
                        Navigator.pop(folha);
                        _react(message, emoji);
                      },
                      icon: Text(emoji, style: const TextStyle(fontSize: 22)),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.reply),
              title: const Text('Responder'),
              subtitle: Text(
                messageSummary(message),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                Navigator.pop(folha);
                setState(() => _replyTo = message);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Escolhe uma imagem — da câmera ou da galeria — e abre a folha que
  /// pergunta a legenda.
  Future<void> _pickImage(ImageSource de) async {
    final Uint8List bytes;
    final String nome;
    try {
      final escolha = await ImagePicker().pickImage(
        source: de,
        // Foto de celular tem muito mais pixel do que uma conversa precisa;
        // assim ela sobe rápido e cabe no limite do anexo.
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (escolha == null) return;
      nome = escolha.name;
      bytes = await escolha.readAsBytes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não deu para abrir a imagem: $e')),
      );
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewImageSheet(
        conversationId: widget.conversation.id,
        userId: widget.userId,
        fileName: nome,
        bytes: bytes,
        replyTo: _replyTo?.id,
      ),
    );
    if (mounted) setState(() => _replyTo = null);
  }

  /// Da câmera ou da galeria: a folha pergunta de onde.
  void _openImagePicker() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (folha) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto'),
              onTap: () {
                Navigator.pop(folha);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () {
                Navigator.pop(folha);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
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
    // As marcas de entregue e lido mudam enquanto a tela está aberta, então
    // a conversa vem do stream; a do construtor é só o ponto de partida.
    final conversation =
        ref
            .watch(conversationsProvider(widget.userId))
            .value
            ?.where((c) => c.id == widget.conversation.id)
            .firstOrNull ??
        widget.conversation;

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
                // Mexer no provider no meio do build mexeria na árvore que
                // está sendo montada.
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _markRead(list),
                );
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
                      conversation: conversation,
                      mine: m.authorId == widget.userId,
                      showAuthor: conversation.kind == ConversationKind.group,
                      // A citada sai da própria lista: ela é sempre da mesma
                      // conversa, então já está aqui.
                      quoted: m.replyTo == null
                          ? null
                          : list.where((o) => o.id == m.replyTo).firstOrNull,
                      userId: widget.userId,
                      onReply: () => _openMessageMenu(m),
                      onReact: (emoji) => _react(m, emoji),
                    );
                  },
                );
              },
            ),
          ),
          if (_replyTo != null)
            _ReplyBar(
              message: _replyTo!,
              onCancel: () => setState(() => _replyTo = null),
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
                  IconButton(
                    tooltip: 'Imagem',
                    onPressed: _openImagePicker,
                    icon: const Icon(Icons.image_outlined),
                  ),
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
    required this.conversation,
    required this.mine,
    required this.showAuthor,
    required this.userId,
    required this.onReply,
    required this.onReact,
    this.quoted,
  });

  final Message message;
  final Conversation conversation;
  final bool mine;
  final bool showAuthor;

  /// A mensagem que esta responde, quando ela ainda está na conversa.
  final Message? quoted;

  /// Quem está olhando a conversa: é a reação dele que fica em destaque.
  final String userId;
  final VoidCallback onReply;
  final void Function(String emoji) onReact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final author = ref.watch(repositoryProvider).profile(message.authorId);
    final anexo = message.attachment;
    final legenda = message.text ?? '';
    final citada = quoted;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onReply,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.78,
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            padding: anexo == null
                ? const EdgeInsets.fromLTRB(12, 8, 12, 6)
                : const EdgeInsets.fromLTRB(6, 6, 6, 4),
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
                if (citada != null) ...[
                  _Quote(message: citada, mine: mine),
                  const SizedBox(height: 4),
                ],
                if (anexo != null) ...[
                  ChatImage(
                    attachment: anexo,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FullImageScreen(
                          attachment: anexo,
                          author: mine ? 'Você' : author.name,
                          caption: message.text,
                        ),
                      ),
                    ),
                  ),
                  if (legenda.isNotEmpty) const SizedBox(height: 4),
                ],
                if (legenda.isNotEmpty) Text(legenda),
                if (message.reactions.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final (emoji, quantas) in message.reactionCounts)
                        _ReactionChip(
                          emoji: emoji,
                          quantas: quantas,
                          minha: message.reactions[userId] == emoji,
                          onTap: () => onReact(emoji),
                        ),
                    ],
                  ),
                ],
                Align(
                  alignment: Alignment.bottomRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        hhmm(message.createdAt),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      // Só nas minhas: saber se eu li a mensagem do outro não
                      // serve para nada.
                      if (mine) ...[
                        const SizedBox(width: 4),
                        MessageTicks(conversation.statusOf(message)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A imagem escolhida, antes de mandar: a prévia, a legenda e o botão.
///
/// O tamanho da imagem é medido aqui e vai com a mensagem, para a bolha nascer
/// na proporção certa no celular de quem recebe.
class _NewImageSheet extends ConsumerStatefulWidget {
  const _NewImageSheet({
    required this.conversationId,
    required this.userId,
    required this.fileName,
    required this.bytes,
    this.replyTo,
  });

  final String conversationId;
  final String userId;
  final String fileName;
  final Uint8List bytes;
  final String? replyTo;

  @override
  ConsumerState<_NewImageSheet> createState() => _NewImageSheetState();
}

class _NewImageSheetState extends ConsumerState<_NewImageSheet> {
  final _caption = TextEditingController();
  var _sending = false;
  String? _error;

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final imagem = await decodeImageFromList(widget.bytes);
      await ref
          .read(repositoryProvider)
          .sendImage(
            conversationId: widget.conversationId,
            authorId: widget.userId,
            bytes: widget.bytes,
            fileName: widget.fileName,
            width: imagem.width,
            height: imagem.height,
            caption: _caption.text,
            replyTo: widget.replyTo,
          );
      if (mounted) Navigator.pop(context);
    } on StateError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final erro = _error;
    return SheetBody(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              // A prévia não toma a tela: a legenda e o botão continuam à
              // vista, mesmo com o teclado aberto.
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.4,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(widget.bytes, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _caption,
              textCapitalization: TextCapitalization.sentences,
              maxLength: maxCaptionLength,
              decoration: InputDecoration(
                labelText: 'Legenda (opcional)',
                errorText: erro,
              ),
              onSubmitted: (_) => _send(),
            ),
            FilledButton.icon(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
              label: const Text('Mandar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// A mensagem citada, dentro da bolha de quem respondeu.
class _Quote extends ConsumerWidget {
  const _Quote({required this.message, required this.mine});

  final Message message;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final author = ref.watch(repositoryProvider).profile(message.authorId);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: (mine ? scheme.primary : scheme.onSurface).withValues(
          alpha: 0.06,
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: Color(author.color), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            author.name,
            style: TextStyle(
              color: Color(author.color),
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          Text(
            messageSummary(message),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// A citação escolhida, acima do campo de texto, até a mensagem sair.
class _ReplyBar extends ConsumerWidget {
  const _ReplyBar({required this.message, required this.onCancel});

  final Message message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final author = ref.watch(repositoryProvider).profile(message.authorId);

    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Icon(Icons.reply, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Respondendo ${author.name}',
                    style: TextStyle(
                      color: Color(author.color),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    messageSummary(message),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Cancelar resposta',
              icon: const Icon(Icons.close),
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

/// Uma reação no pé da bolha: o emoji, quantas vezes, e a sua em destaque.
class _ReactionChip extends StatelessWidget {
  const _ReactionChip({
    required this.emoji,
    required this.quantas,
    required this.minha,
    required this.onTap,
  });

  final String emoji;
  final int quantas;
  final bool minha;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          // O fundo é o mesmo nas duas: a bolha de quem manda já é
          // primaryContainer, e o chip dela sumiria dentro. O que marca a
          // sua reação é a borda.
          color: scheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: minha ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Text(
          quantas > 1 ? '$emoji $quantas' : emoji,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}
