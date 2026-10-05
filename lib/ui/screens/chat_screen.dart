import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../data/repository.dart';
import '../../domain/mentions.dart';
import '../../domain/models.dart';
import '../../push/push.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../widgets/brand.dart';
import '../widgets/chamado_card.dart';
import '../widgets/chat_audio.dart';
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

  /// A busca na conversa: a barra de busca aberta e o termo procurado.
  bool _searching = false;
  final _search = TextEditingController();
  String _query = '';

  /// A gravação do recado de voz. O gravador nasce só na primeira vez: criá-lo
  /// de saída chamaria o plugin nativo, que não existe nos testes de widget.
  AudioRecorder? _recorder;
  bool _recording = false;
  Duration _recordElapsed = Duration.zero;
  Timer? _recordTimer;
  String? _recordPath;

  /// O que eu estou fazendo aqui, contado aos outros ("digitando…"), e o
  /// relógio que desliga o "digitando" quando a pessoa para de teclar.
  late final SaleRepository _repo;
  ChatActivity? _minhaAtividade;
  Timer? _digitandoTimer;

  @override
  void initState() {
    super.initState();
    // Enquanto a conversa está na tela, mensagem dela não vira aviso no
    // celular: quem está lendo não precisa ser avisado.
    conversaAberta.value = widget.conversation.id;
    // Guardado de saída: o "parei" do dispose não pode mais usar o ref.
    _repo = ref.read(repositoryProvider);
    _input.addListener(_aoDigitar);
  }

  @override
  void dispose() {
    if (conversaAberta.value == widget.conversation.id) {
      conversaAberta.value = null;
    }
    _input.removeListener(_aoDigitar);
    _digitandoTimer?.cancel();
    _contar(null);
    _input.dispose();
    _search.dispose();
    _recordTimer?.cancel();
    _recorder?.dispose();
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
          mentions: quemFoiMencionado(text, _nomes(), widget.userId),
        );
  }

  /// id -> nome de quem está na conversa, para as menções.
  Map<String, String> _nomes() => {
    for (final id in widget.conversation.memberIds) id: _repo.profile(id).name,
  };

  /// Completa o "@" que se está digitando com o nome escolhido.
  void _mencionar(String nome) {
    final novo = completarMencao(_input.text, nome);
    _input.value = TextEditingValue(
      text: novo,
      selection: TextSelection.collapsed(offset: novo.length),
    );
  }

  /// A mensagem fixada da conversa, se ainda estiver nela e não apagada.
  Message? _mensagemFixada(Conversation conversation, List<Message>? lista) {
    final id = conversation.pinnedMessageId;
    if (id == null || lista == null) return null;
    return lista.where((m) => m.id == id && !m.isDeleted).firstOrNull;
  }

  /// Fixa a mensagem no topo da conversa; nulo desafixa.
  Future<void> _fixar(String? messageId) async {
    try {
      await _repo.pinMessage(
        conversationId: widget.conversation.id,
        messageId: messageId,
      );
    } catch (e) {
      _avisar('Não deu para fixar: $e');
    }
  }

  /// A mensagem fixada inteira, para ler sem caçar na conversa.
  void _verFixada(Message message) {
    final autor = message.authorId == widget.userId
        ? 'Você'
        : _repo.profile(message.authorId).name;
    showDialog<void>(
      context: context,
      builder: (dialogo) => AlertDialog(
        icon: const Icon(Icons.push_pin_outlined),
        title: Text('Fixada por $autor'),
        content: SelectableText(
          (message.text ?? '').trim().isEmpty
              ? messageSummary(message)
              : message.text!,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogo),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  /// Conta aos outros o que estou fazendo na conversa — só quando muda.
  void _contar(ChatActivity? atividade) {
    if (_minhaAtividade == atividade) return;
    _minhaAtividade = atividade;
    unawaited(
      _repo
          .setActivity(
            conversationId: widget.conversation.id,
            userId: widget.userId,
            activity: atividade,
          )
          .catchError((_) {}),
    );
  }

  /// Teclar liga o "digitando"; quatro segundos parado, ou o campo vazio,
  /// desliga.
  void _aoDigitar() {
    if (_recording) return;
    _digitandoTimer?.cancel();
    if (_input.text.trim().isEmpty) {
      _contar(null);
      return;
    }
    _contar(ChatActivity.typing);
    _digitandoTimer = Timer(const Duration(seconds: 4), () => _contar(null));
  }

  void _avisar(String texto) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(texto)));
    }
  }

  void _pararCronometro() {
    _recordTimer?.cancel();
    _recordTimer = null;
  }

  /// Começa a gravar o recado, depois de pedir o microfone.
  Future<void> _startRecording() async {
    final recorder = _recorder ??= AudioRecorder();
    try {
      if (!await recorder.hasPermission()) {
        _avisar('Sem permissão para o microfone.');
        return;
      }
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/recado_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await recorder.start(const RecordConfig(), path: path);
      _recordPath = path;
      _digitandoTimer?.cancel();
      _contar(ChatActivity.recording);
      setState(() {
        _recording = true;
        _recordElapsed = Duration.zero;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recordElapsed += const Duration(seconds: 1));
        // Recado não é podcast: no teto, manda o que tem.
        if (_recordElapsed.inSeconds >= maxAudioSeconds) _stopAndSend();
      });
    } catch (e) {
      _avisar('Não deu para gravar: $e');
      _resetRecording();
    }
  }

  /// Descarta a gravação em andamento.
  Future<void> _cancelRecording() async {
    _pararCronometro();
    _contar(null);
    try {
      await _recorder?.cancel();
    } catch (_) {}
    _resetRecording();
  }

  /// Fecha a gravação e manda o recado.
  Future<void> _stopAndSend() async {
    _pararCronometro();
    _contar(null);
    final segundos = _recordElapsed.inSeconds;
    final citada = _replyTo;
    String? path;
    try {
      path = await _recorder?.stop();
    } catch (_) {}
    path ??= _recordPath;
    setState(() {
      _recording = false;
      _recordElapsed = Duration.zero;
      _replyTo = null;
    });
    _recordPath = null;
    // Toque curto demais não vira recado.
    if (path == null || segundos < 1) return;
    try {
      final bytes = await File(path).readAsBytes();
      await ref
          .read(repositoryProvider)
          .sendAudio(
            conversationId: widget.conversation.id,
            authorId: widget.userId,
            bytes: bytes,
            fileName: path.split('/').last,
            duration: segundos,
            replyTo: citada?.id,
          );
    } catch (e) {
      _avisar('Não deu para mandar o recado: $e');
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  void _resetRecording() {
    _pararCronometro();
    _contar(null);
    _recordPath = null;
    if (mounted) {
      setState(() {
        _recording = false;
        _recordElapsed = Duration.zero;
      });
    }
  }

  /// A barra de digitar: Chamado, imagem, o campo e — com texto, enviar; vazio,
  /// gravar recado.
  Widget _composerRow() {
    return Row(
      children: [
        IconButton.filled(
          tooltip: 'Chamado',
          onPressed: _openChamado,
          icon: Marca(size: 20, color: Theme.of(context).colorScheme.onPrimary),
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
        ValueListenableBuilder(
          valueListenable: _input,
          builder: (_, value, _) {
            final temTexto = value.text.trim().isNotEmpty;
            return IconButton(
              tooltip: temTexto ? 'Enviar' : 'Gravar recado',
              onPressed: temTexto ? _send : _startRecording,
              icon: Icon(temTexto ? Icons.send : Icons.mic),
            );
          },
        ),
      ],
    );
  }

  /// A barra durante a gravação: o tempo correndo, descartar e mandar.
  Widget _recordingBar() {
    final tempo =
        '${_recordElapsed.inMinutes}:'
        '${(_recordElapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    return Row(
      children: [
        IconButton(
          tooltip: 'Cancelar',
          onPressed: _cancelRecording,
          icon: const Icon(Icons.delete_outline),
        ),
        const Icon(Icons.fiber_manual_record, color: Colors.red, size: 14),
        const SizedBox(width: 8),
        Text(tempo),
        const Spacer(),
        const Text('Gravando recado…'),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Enviar recado',
          onPressed: _stopAndSend,
          icon: const Icon(Icons.send),
        ),
      ],
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

  /// Abre o diálogo de edição com o texto atual e salva o que mudou.
  Future<void> _editMessage(Message message) async {
    final novo = await showDialog<String>(
      context: context,
      builder: (_) => _EditMessageDialog(initial: message.text ?? ''),
    );
    if (novo == null || novo.isEmpty || novo == (message.text ?? '')) return;
    await ref
        .read(repositoryProvider)
        .editMessage(messageId: message.id, userId: widget.userId, text: novo);
  }

  /// Confirma e apaga a mensagem.
  Future<void> _deleteMessage(Message message) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: const Text('Apagar mensagem?'),
        content: const Text(
          'Ela some para todo mundo e vira "mensagem apagada".',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogo, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogo, true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;
    await ref
        .read(repositoryProvider)
        .deleteMessage(messageId: message.id, userId: widget.userId);
  }

  /// O menu de uma mensagem, no toque longo: a fileira de reações em cima, o
  /// que dá para fazer com ela embaixo. Mensagem apagada não tem menu.
  void _openMessageMenu(Message message) {
    if (message.isDeleted) return;
    final minha = message.authorId == widget.userId;
    final fixada =
        ref
            .read(conversationsProvider(widget.userId))
            .value
            ?.where((c) => c.id == widget.conversation.id)
            .firstOrNull
            ?.pinnedMessageId ==
        message.id;
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
            ListTile(
              leading: Icon(fixada ? Icons.push_pin : Icons.push_pin_outlined),
              title: Text(fixada ? 'Desafixar' : 'Fixar no topo'),
              onTap: () {
                Navigator.pop(folha);
                _fixar(fixada ? null : message.id);
              },
            ),
            if (minha) ...[
              if ((message.text ?? '').trim().isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Editar'),
                  onTap: () {
                    Navigator.pop(folha);
                    _editMessage(message);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Apagar'),
                onTap: () {
                  Navigator.pop(folha);
                  _deleteMessage(message);
                },
              ),
            ],
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

  /// Fecha a busca e volta a conversa ao normal.
  void _closeSearch() {
    _search.clear();
    setState(() {
      _searching = false;
      _query = '';
    });
  }

  /// Os resultados da busca: as mensagens de texto que contêm o termo, da mais
  /// nova para a mais antiga, com o trecho em destaque. Card de Chamado não
  /// entra (não tem texto); legenda de imagem entra.
  Widget _searchResults(List<Message> list) {
    if (_query.isEmpty) {
      return const Center(child: Text('Digite para buscar na conversa.'));
    }
    final repo = ref.read(repositoryProvider);
    final termo = _fold(_query);
    final hits = [
      for (final m in list)
        if (m.text != null && _fold(m.text!).contains(termo)) m,
    ].reversed.toList();
    if (hits.isEmpty) {
      return Center(child: Text('Nada encontrado para "$_query".'));
    }
    final destaque = TextStyle(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      fontWeight: FontWeight.bold,
    );
    return ListView.builder(
      itemCount: hits.length,
      itemBuilder: (context, i) {
        final m = hits[i];
        final autor = m.authorId == widget.userId
            ? 'Você'
            : repo.profile(m.authorId).name;
        return ListTile(
          leading: m.isImage ? const Icon(Icons.image_outlined) : null,
          title: Text.rich(
            TextSpan(children: _highlight(m.text!, _query, destaque)),
          ),
          subtitle: Text(
            '$autor · ${dayLabel(m.createdAt)} ${hhmm(m.createdAt)}',
          ),
          onTap: _closeSearch,
        );
      },
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
      appBar: _searching
          ? AppBar(
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Fechar busca',
                onPressed: _closeSearch,
              ),
              title: TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Buscar na conversa',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
              actions: [
                if (_query.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Limpar',
                    onPressed: () {
                      _search.clear();
                      setState(() => _query = '');
                    },
                  ),
              ],
            )
          : AppBar(
              title: _Titulo(
                titulo: conversationTitle(repo, conversation, widget.userId),
                status: conversationStatus(
                  repo,
                  conversation,
                  widget.userId,
                  activity:
                      ref
                          .watch(activityProvider(widget.conversation.id))
                          .value ??
                      const {},
                  online:
                      ref.watch(onlineProvider(widget.userId)).value ??
                      const <String>{},
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search),
                  tooltip: 'Buscar na conversa',
                  onPressed: () => setState(() => _searching = true),
                ),
              ],
            ),
      body: Column(
        children: [
          if (!_searching)
            if (_mensagemFixada(conversation, messages.value)
                case final fixada?)
              _Fixada(
                message: fixada,
                autor: fixada.authorId == widget.userId
                    ? 'Você'
                    : repo.profile(fixada.authorId).name,
                onTap: () => _verFixada(fixada),
                onDesafixar: () => _fixar(null),
              ),
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
                if (_searching) return _searchResults(list);
                if (list.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Marca(
                          size: 48,
                          color: Theme.of(context).colorScheme.outline,
                        ),
                        const SizedBox(height: 8),
                        const Text('Nenhuma mensagem. Que tal um Chamado?'),
                      ],
                    ),
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
          if (!_searching &&
              !_recording &&
              conversation.kind == ConversationKind.group)
            _SugestoesDeMencao(
              texto: _input,
              nomes: [
                for (final id in conversation.memberIds)
                  if (id != widget.userId) repo.profile(id).name,
              ],
              onEscolher: _mencionar,
            ),
          if (!_searching && _replyTo != null)
            _ReplyBar(
              message: _replyTo!,
              onCancel: () => setState(() => _replyTo = null),
            ),
          if (!_searching)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                child: _recording ? _recordingBar() : _composerRow(),
              ),
            ),
        ],
      ),
    );
  }
}

/// Caixa e acento de lado, para a busca achar "nao", "NÃO" e "não" como iguais.
/// Troca cada caractere por um só, então as posições batem com o texto original.
String _fold(String s) {
  s = s.toLowerCase();
  const de = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const para = 'aaaaaeeeeiiiiooooouuuuc';
  for (var i = 0; i < de.length; i++) {
    s = s.replaceAll(de[i], para[i]);
  }
  return s;
}

/// Quebra [text] nos trechos que casam com [query] para destacá-los. Como
/// [_fold] preserva o comprimento, as posições do texto dobrado valem no
/// original.
List<InlineSpan> _highlight(String text, String query, TextStyle destaque) {
  final termo = _fold(query);
  if (termo.isEmpty) return [TextSpan(text: text)];
  final alvo = _fold(text);
  final spans = <InlineSpan>[];
  var start = 0;
  while (true) {
    final idx = alvo.indexOf(termo, start);
    if (idx < 0) {
      spans.add(TextSpan(text: text.substring(start)));
      break;
    }
    if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
    spans.add(
      TextSpan(text: text.substring(idx, idx + termo.length), style: destaque),
    );
    start = idx + termo.length;
  }
  return spans;
}

/// O texto da mensagem com as menções em destaque — a minha (ou o "@todos")
/// com fundo, para saltar aos olhos.
class _TextoComMencoes extends StatelessWidget {
  const _TextoComMencoes({
    required this.texto,
    required this.nomes,
    required this.userId,
  });

  final String texto;
  final Map<String, String> nomes;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final mencoes = mencoesNoTexto(texto, nomes);
    if (mencoes.isEmpty) return Text(texto);
    final scheme = Theme.of(context).colorScheme;
    final partes = <InlineSpan>[];
    var i = 0;
    for (final mencao in mencoes) {
      if (mencao.inicio > i) {
        partes.add(TextSpan(text: texto.substring(i, mencao.inicio)));
      }
      final paraMim = mencao.id == null || mencao.id == userId;
      partes.add(
        TextSpan(
          text: texto.substring(mencao.inicio, mencao.fim),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: scheme.primary,
            backgroundColor: paraMim
                ? scheme.primary.withValues(alpha: 0.15)
                : null,
          ),
        ),
      );
      i = mencao.fim;
    }
    if (i < texto.length) partes.add(TextSpan(text: texto.substring(i)));
    return Text.rich(TextSpan(children: partes));
  }
}

/// As sugestões de nome enquanto se digita um "@": tocar completa a menção.
class _SugestoesDeMencao extends StatelessWidget {
  const _SugestoesDeMencao({
    required this.texto,
    required this.nomes,
    required this.onEscolher,
  });

  final TextEditingController texto;
  final List<String> nomes;
  final void Function(String nome) onEscolher;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: texto,
      builder: (context, valor, _) {
        final consulta = mencaoEmAndamento(valor.text)?.toLowerCase();
        if (consulta == null) return const SizedBox.shrink();
        final opcoes = [
          for (final nome in [mencaoTodos, ...nomes])
            if (nome.toLowerCase().startsWith(consulta)) nome,
        ];
        if (opcoes.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final nome in opcoes)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ActionChip(
                    avatar: const Icon(Icons.alternate_email, size: 16),
                    label: Text(nome),
                    onPressed: () => onEscolher(nome),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// A faixa da mensagem fixada, no topo da conversa: tocar mostra inteira.
class _Fixada extends StatelessWidget {
  const _Fixada({
    required this.message,
    required this.autor,
    required this.onTap,
    required this.onDesafixar,
  });

  final Message message;
  final String autor;
  final VoidCallback onTap;
  final VoidCallback onDesafixar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
          child: Row(
            children: [
              Icon(Icons.push_pin, size: 18, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fixada · $autor',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    Text(
                      messageSummary(message),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Desafixar',
                icon: const Icon(Icons.close),
                onPressed: onDesafixar,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// O nome da conversa e, embaixo, quem está digitando, gravando ou por aí.
class _Titulo extends StatelessWidget {
  const _Titulo({required this.titulo, required this.status});

  final String titulo;
  final String status;

  @override
  Widget build(BuildContext context) {
    if (status.isEmpty) return Text(titulo);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(titulo),
        Text(
          status,
          style: Theme.of(context).textTheme.bodySmall,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// O diálogo de editar mensagem. É um widget com estado para cuidar do próprio
/// controller: criá-lo e descartá-lo fora dele daria "usado após descartado"
/// enquanto o diálogo ainda fecha.
class _EditMessageDialog extends StatefulWidget {
  const _EditMessageDialog({required this.initial});

  final String initial;

  @override
  State<_EditMessageDialog> createState() => _EditMessageDialogState();
}

class _EditMessageDialogState extends State<_EditMessageDialog> {
  late final _controle = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar mensagem'),
      content: TextField(
        controller: _controle,
        autofocus: true,
        minLines: 1,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(hintText: 'Mensagem'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controle.text.trim()),
          child: const Text('Salvar'),
        ),
      ],
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
                if (message.isDeleted)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.block, size: 14, color: scheme.outline),
                      const SizedBox(width: 4),
                      Text(
                        'Mensagem apagada',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: scheme.outline,
                        ),
                      ),
                    ],
                  )
                else ...[
                  if (citada != null) ...[
                    _Quote(message: citada, mine: mine),
                    const SizedBox(height: 4),
                  ],
                  if (anexo != null) ...[
                    if (anexo.kind == AttachmentKind.audio)
                      ChatAudio(attachment: anexo, mine: mine)
                    else
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
                  if (legenda.isNotEmpty)
                    _TextoComMencoes(
                      texto: legenda,
                      nomes: {
                        for (final id in conversation.memberIds)
                          id: ref.watch(repositoryProvider).profile(id).name,
                      },
                      userId: userId,
                    ),
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
                ],
                Align(
                  alignment: Alignment.bottomRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.isEdited && !message.isDeleted) ...[
                        Text(
                          'editado',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        hhmm(message.createdAt),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      // Só nas minhas: saber se eu li a mensagem do outro não
                      // serve para nada.
                      if (mine && !message.isDeleted) ...[
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
