import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repository.dart';
import '../../domain/do_dia.dart';
import '../../domain/formatacao.dart';
import '../../domain/linha_do_tempo.dart';
import '../../domain/mentions.dart';
import '../../domain/models.dart';
import '../../push/push.dart';
import '../../state/providers.dart';
import '../../state/tutorial.dart';
import '../format.dart';
import '../widgets/avatar.dart';
import '../widgets/brand.dart';
import '../widgets/chamado_card.dart';
import '../widgets/chat_audio.dart';
import '../widgets/chat_image.dart';
import '../widgets/dica.dart';
import '../widgets/message_ticks.dart';
import '../widgets/sheet.dart';
import 'discord_screen.dart';
import 'do_dia_screen.dart';
import 'group_info_screen.dart';
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

/// Abre a conversa individual com [otherId], criando-a na primeira vez.
Future<void> abrirConversaCom(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
  required String otherId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  try {
    final conversa = await ref
        .read(repositoryProvider)
        .openDirect(userId: userId, otherId: otherId);
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(conversation: conversa, userId: userId),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          e is StateError ? e.message : 'Não deu para abrir a conversa.',
        ),
      ),
    );
  }
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _foco = FocusNode();

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

  /// A mensagem minha que o campo está editando; nula = escrevendo nova. O
  /// rascunho que estava no campo espera a edição acabar.
  Message? _editando;
  String _rascunhoGuardado = '';
  late final Rascunho _rascunho;

  /// Até onde esta pessoa tinha visto ao abrir: daí para baixo é "novas".
  /// Fica fixo enquanto a tela está aberta — abrir já marca tudo como lido.
  DateTime? _lidaAte;

  /// A rolagem da conversa. A lista é invertida: zero é o fim, a mensagem
  /// mais nova.
  final _rolagem = ScrollController();

  /// Longe do fim, o botão de descer aparece; [_saiuDoFimEm] é a hora da
  /// última mensagem quando a pessoa subiu, para contar as que chegaram.
  bool _longeDoFim = false;
  DateTime? _saiuDoFimEm;

  /// A bolha que acabou de ser alcançada por uma citação ou pela busca, em
  /// destaque por um instante.
  String? _destacada;
  Timer? _destaqueTimer;
  final _chaves = <String, GlobalKey>{};

  @override
  void initState() {
    super.initState();
    _lidaAte = widget.conversation.receiptOf(widget.userId).readUntil;
    _rolagem.addListener(_aoRolar);
    _rascunho = ref.read(rascunhoProvider(widget.conversation.id).notifier);
    final rascunho = ref.read(rascunhoProvider(widget.conversation.id));
    if (rascunho.isNotEmpty) {
      _input.value = TextEditingValue(
        text: rascunho,
        selection: TextSelection.collapsed(offset: rascunho.length),
      );
    }
    // Enquanto a conversa está na tela, mensagem dela não vira aviso no
    // celular: quem está lendo não precisa ser avisado.
    conversaAberta.value = widget.conversation.id;
    // Entrar na conversa de um grupo o deixa ativo: o Chamado daqui sai com
    // os jogos e os sons dele.
    final grupo = widget.conversation.groupId;
    if (widget.conversation.kind == ConversationKind.group && grupo != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(activeGroupIdProvider.notifier).choose(grupo);
      });
    }
    // Guardado de saída: o "parei" do dispose não pode mais usar o ref.
    _repo = ref.read(repositoryProvider);
    // Marcada como não lida, abrir já é ter visto — mesmo sem mensagem nova,
    // que é quando o _markRead não chama o servidor.
    if (widget.conversation.markedUnread) {
      unawaited(
        _repo
            .markRead(
              conversationId: widget.conversation.id,
              userId: widget.userId,
            )
            .catchError((_) {}),
      );
    }
    _input.addListener(_aoDigitar);
  }

  @override
  void dispose() {
    if (conversaAberta.value == widget.conversation.id) {
      conversaAberta.value = null;
    }
    _input.removeListener(_aoDigitar);
    _digitandoTimer?.cancel();
    _destaqueTimer?.cancel();
    _contar(null);
    // Saiu no meio de uma edição: o que fica é o rascunho de antes dela.
    if (_editando != null) unawaited(_rascunho.guardar(_rascunhoGuardado));
    _rolagem.dispose();
    _foco.dispose();
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
    final editando = _editando;
    if (editando != null) {
      _pararDeEditar();
      if (text == (editando.text ?? '').trim()) return;
      try {
        await _repo.editMessage(
          messageId: editando.id,
          userId: widget.userId,
          text: text,
        );
      } catch (e) {
        _avisar('Não deu para editar: $e');
      }
      return;
    }
    _input.clear();
    final citada = _replyTo;
    setState(() => _replyTo = null);
    // Quem manda quer ver a própria mensagem chegar.
    _descer(animado: false);
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

  /// O selo da do dia na bolha: a vencedora de um dia, ou indicada hoje.
  String? _seloDoDia(DoDia? doDia, Message m) {
    if (doDia == null || m.isDeleted) return null;
    final vitoria = doDia.vitoriaDe(m.id);
    if (vitoria != null) return '🏆 A do dia · ${ddmm(vitoria.dia)}';
    if (doDia.indicadas.containsKey(m.id)) {
      final votos = doDia.votosDe(m.id);
      return '⭐ Indicada · ${votos == 1 ? '1 voto' : '$votos votos'}';
    }
    return null;
  }

  /// Indica a mensagem para a do dia.
  Future<void> _indicar(Message message) async {
    try {
      await _repo.nominate(messageId: message.id, userId: widget.userId);
      _avisar('Indicada para a do dia. Agora é votar!');
    } catch (e) {
      _avisar('Não deu para indicar: $e');
    }
  }

  /// Vota na indicada.
  Future<void> _votar(Message message) async {
    try {
      await _repo.vote(messageId: message.id, userId: widget.userId);
    } catch (e) {
      _avisar('Não deu para votar: $e');
    }
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
    // O texto da edição não é rascunho: o rascunho é o que espera por ela.
    if (_editando == null) unawaited(_rascunho.guardar(_input.text));
    if (_recording) return;
    _digitandoTimer?.cancel();
    if (_input.text.trim().isEmpty) {
      _contar(null);
      return;
    }
    _contar(ChatActivity.typing);
    _digitandoTimer = Timer(const Duration(seconds: 4), () => _contar(null));
  }

  /// Mais de uma tela acima do fim, o botão de descer aparece.
  void _aoRolar() {
    final longe = _rolagem.hasClients && _rolagem.offset > 400;
    if (longe == _longeDoFim) return;
    final ultima = ref.read(messagesProvider(widget.conversation.id)).value;
    setState(() {
      _longeDoFim = longe;
      _saiuDoFimEm = longe && ultima != null && ultima.isNotEmpty
          ? ultima.last.createdAt
          : null;
    });
  }

  /// Quantas mensagens dos outros chegaram desde que a pessoa subiu.
  int _chegaramLaEmbaixo(List<Message> lista) {
    final desde = _saiuDoFimEm;
    if (desde == null) return 0;
    return lista
        .where((m) => m.authorId != widget.userId && m.createdAt.isAfter(desde))
        .length;
  }

  void _descer({bool animado = true}) {
    if (!_rolagem.hasClients) return;
    if (animado) {
      _rolagem.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _rolagem.jumpTo(0);
    }
  }

  GlobalKey _chaveDe(String messageId) =>
      _chaves.putIfAbsent(messageId, GlobalKey.new);

  /// Rola até a mensagem e a destaca. A lista só monta o que está perto da
  /// tela, então sobe aos poucos até a bolha existir; daí centraliza nela.
  Future<void> _irPara(String messageId) async {
    final lista = ref.read(messagesProvider(widget.conversation.id)).value;
    if (lista == null || !lista.any((m) => m.id == messageId)) {
      _avisar('Essa mensagem não está mais na conversa.');
      return;
    }
    final chave = _chaveDe(messageId);
    // A primeira volta espera a lista existir (a busca acabou de fechar).
    for (var volta = 0; volta < 200; volta++) {
      if (!mounted) return;
      final alvo = chave.currentContext;
      if (alvo != null && alvo.mounted) {
        await Scrollable.ensureVisible(
          alvo,
          alignment: 0.5,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
        break;
      }
      if (volta > 0) {
        if (!_rolagem.hasClients) return;
        final pos = _rolagem.position;
        // A citada e o que a busca acha estão sempre acima — mais antigos.
        if (pos.pixels >= pos.maxScrollExtent) break;
        _rolagem.jumpTo(
          (pos.pixels + pos.viewportDimension * 0.8).clamp(
            0.0,
            pos.maxScrollExtent,
          ),
        );
      }
      await WidgetsBinding.instance.endOfFrame;
    }
    if (!mounted) return;
    HapticFeedback.selectionClick();
    _destaqueTimer?.cancel();
    setState(() => _destacada = messageId);
    _destaqueTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _destacada = null);
    });
  }

  /// Manda a mensagem para outra conversa, marcada como encaminhada. Foto e
  /// recado sobem de novo, para a pasta da outra conversa: é de lá que sai
  /// quem pode ver o arquivo.
  Future<void> _encaminhar(Message message) async {
    final conversas =
        (ref.read(conversationsProvider(widget.userId)).value ?? const [])
            .where((c) => c.id != widget.conversation.id)
            .toList();
    if (conversas.isEmpty) {
      _avisar('Não tem outra conversa para onde encaminhar.');
      return;
    }
    final destino = await showModalBottomSheet<Conversation>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (folha) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(folha).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Encaminhar para')),
              for (final c in conversas)
                ListTile(
                  leading: c.kind == ConversationKind.group
                      ? GroupAvatar(
                          photoPath: ref
                              .read(groupOfProvider((widget.userId, c.groupId)))
                              ?.photoPath,
                        )
                      : Avatar(
                          _repo.profile(
                            c.memberIds.firstWhere((id) => id != widget.userId),
                          ),
                        ),
                  title: Text(conversationTitle(_repo, c, widget.userId)),
                  onTap: () => Navigator.pop(folha, c),
                ),
            ],
          ),
        ),
      ),
    );
    if (destino == null) return;
    final nome = conversationTitle(_repo, destino, widget.userId);
    try {
      final anexo = message.attachment;
      if (anexo == null) {
        await _repo.sendText(
          conversationId: destino.id,
          authorId: widget.userId,
          text: message.text ?? '',
          forwarded: true,
        );
      } else {
        final bytes = await _repo.attachmentBytes(anexo.path);
        final arquivo = anexo.path.split('/').last;
        if (anexo.kind == AttachmentKind.audio) {
          await _repo.sendAudio(
            conversationId: destino.id,
            authorId: widget.userId,
            bytes: bytes,
            fileName: arquivo,
            duration: anexo.duration ?? 0,
            forwarded: true,
          );
        } else {
          await _repo.sendImage(
            conversationId: destino.id,
            authorId: widget.userId,
            bytes: bytes,
            fileName: arquivo,
            width: anexo.width,
            height: anexo.height,
            caption: message.text,
            forwarded: true,
          );
        }
      }
      _avisar('Encaminhada para $nome.');
    } catch (e) {
      _avisar('Não deu para encaminhar: $e');
    }
  }

  /// Copia o texto da mensagem (ou a legenda da foto).
  Future<void> _copiar(Message message) async {
    await Clipboard.setData(ClipboardData(text: message.text ?? ''));
    _avisar('Mensagem copiada.');
  }

  /// Leva a mensagem para o campo, como no WhatsApp: o que estava escrito
  /// espera a edição acabar.
  void _comecarAEditar(Message message) {
    _rascunhoGuardado = _editando == null ? _input.text : _rascunhoGuardado;
    final texto = message.text ?? '';
    setState(() {
      _editando = message;
      _replyTo = null;
    });
    _input.value = TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
    _foco.requestFocus();
  }

  void _pararDeEditar() {
    final volta = _rascunhoGuardado;
    _rascunhoGuardado = '';
    setState(() => _editando = null);
    _input.value = TextEditingValue(
      text: volta,
      selection: TextSelection.collapsed(offset: volta.length),
    );
  }

  /// Quem reagiu com o quê, segurando uma reação.
  void _verReacoes(Message message) {
    final porEmoji = <String, List<String>>{};
    for (final e in message.reactions.entries) {
      final nome = e.key == widget.userId ? 'Você' : _repo.profile(e.key).name;
      porEmoji.putIfAbsent(e.value, () => []).add(nome);
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final MapEntry(key: emoji, value: nomes) in porEmoji.entries)
              ListTile(
                leading: Text(emoji, style: const TextStyle(fontSize: 22)),
                title: Text(nomes.join(', ')),
              ),
          ],
        ),
      ),
    );
  }

  /// Num grupo, quem já viu a minha mensagem e a quem ela só chegou.
  void _verQuemViu(Message message, Conversation conversation) {
    final lida = <String>[];
    final entregue = <String>[];
    final faltam = <String>[];
    for (final id in conversation.memberIds) {
      if (id == message.authorId) continue;
      final recibo = conversation.receiptOf(id);
      final nome = _repo.profile(id).name;
      if (recibo.read(message.createdAt)) {
        lida.add(nome);
      } else if (recibo.delivered(message.createdAt)) {
        entregue.add(nome);
      } else {
        faltam.add(nome);
      }
    }
    Widget secao(IconData icone, String titulo, List<String> nomes) => ListTile(
      leading: Icon(icone),
      title: Text(titulo),
      subtitle: Text(nomes.isEmpty ? 'Ninguém ainda' : nomes.join(', ')),
    );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            secao(Icons.done_all, 'Lida por', lida),
            secao(Icons.done, 'Entregue a', entregue),
            if (faltam.isNotEmpty)
              secao(Icons.schedule, 'Ainda não chegou para', faltam),
          ],
        ),
      ),
    );
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
            focusNode: _foco,
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
            if (_editando != null) {
              return IconButton(
                tooltip: 'Salvar edição',
                onPressed: temTexto ? _send : null,
                icon: const Icon(Icons.check),
              );
            }
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

  /// Cita a mensagem na próxima e já abre o teclado. Responder cancela uma
  /// edição em andamento: são duas coisas diferentes no mesmo campo.
  void _responder(Message message) {
    if (message.isDeleted) return;
    HapticFeedback.lightImpact();
    if (_editando != null) _pararDeEditar();
    setState(() => _replyTo = message);
    _foco.requestFocus();
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
    final conversation =
        ref
            .read(conversationsProvider(widget.userId))
            .value
            ?.where((c) => c.id == widget.conversation.id)
            .firstOrNull ??
        widget.conversation;
    final fixada = conversation.pinnedMessageId == message.id;
    final temTexto = (message.text ?? '').trim().isNotEmpty;
    // A do dia é só da conversa do grupo.
    final doDia = widget.conversation.kind == ConversationKind.group
        ? ref.read(doDiaProvider(widget.conversation.id)).value
        : null;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      // No grupo o menu é comprido: em celular pequeno, rola.
      isScrollControlled: true,
      builder: (folha) => SafeArea(
        child: SingleChildScrollView(
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
                  _responder(message);
                },
              ),
              if (temTexto)
                ListTile(
                  leading: const Icon(Icons.copy),
                  title: const Text('Copiar'),
                  onTap: () {
                    Navigator.pop(folha);
                    _copiar(message);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.shortcut),
                title: const Text('Encaminhar'),
                onTap: () {
                  Navigator.pop(folha);
                  _encaminhar(message);
                },
              ),
              if (doDia != null && !message.isChamado)
                if (doDia.indicadas.containsKey(message.id))
                  ListTile(
                    leading: const Icon(Icons.star),
                    title: Text(
                      doDia.votos[widget.userId] == message.id
                          ? 'Seu voto para a do dia'
                          : 'Votar para a do dia',
                    ),
                    enabled: doDia.votos[widget.userId] != message.id,
                    onTap: () {
                      Navigator.pop(folha);
                      _votar(message);
                    },
                  )
                else if (diaDoDestaque(message.createdAt) == doDia.hoje)
                  ListTile(
                    leading: const Icon(Icons.star_outline),
                    title: const Text('Indicar para a do dia'),
                    onTap: () {
                      Navigator.pop(folha);
                      _indicar(message);
                    },
                  ),
              ListTile(
                leading: Icon(
                  fixada ? Icons.push_pin : Icons.push_pin_outlined,
                ),
                title: Text(fixada ? 'Desafixar' : 'Fixar no topo'),
                onTap: () {
                  Navigator.pop(folha);
                  _fixar(fixada ? null : message.id);
                },
              ),
              if (minha) ...[
                if (conversation.kind == ConversationKind.group)
                  ListTile(
                    leading: const Icon(Icons.done_all),
                    title: const Text('Quem viu'),
                    onTap: () {
                      Navigator.pop(folha);
                      _verQuemViu(message, conversation);
                    },
                  ),
                if (temTexto)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined),
                    title: const Text('Editar'),
                    onTap: () {
                      Navigator.pop(folha);
                      _comecarAEditar(message);
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
    final termo = semAcento(_query);
    final hits = [
      for (final m in list)
        if (m.text != null && semAcento(m.text!).contains(termo)) m,
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
          onTap: () {
            _closeSearch();
            _irPara(m.id);
          },
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
    final doDia = widget.conversation.kind == ConversationKind.group
        ? ref.watch(doDiaProvider(widget.conversation.id)).value
        : null;
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
              titleSpacing: 0,
              title: _Titulo(
                // No grupo, a foto e o toque no título abrem os dados do grupo.
                foto: conversation.kind == ConversationKind.group
                    ? GroupAvatar(
                        radius: 18,
                        photoPath: ref
                            .watch(
                              groupOfProvider((
                                widget.userId,
                                conversation.groupId,
                              )),
                            )
                            ?.photoPath,
                      )
                    : null,
                onTap: conversation.kind == ConversationKind.group
                    ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => GroupInfoScreen(
                            userId: widget.userId,
                            groupId: conversation.groupId,
                          ),
                        ),
                      )
                    : null,
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
                if (conversation.kind == ConversationKind.group)
                  IconButton(
                    icon: const Icon(Icons.emoji_events_outlined),
                    tooltip: 'Hall das do dia',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => HallScreen(
                          conversation: conversation,
                          userId: widget.userId,
                        ),
                      ),
                    ),
                  ),
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
          if (!_searching && conversation.kind == ConversationKind.group)
            if (ref.watch(
                  groupOfProvider((widget.userId, conversation.groupId)),
                )
                case final grupo? when grupo.discordServidor != null)
              _NaCall(group: grupo, userId: widget.userId),
          if (!_searching && conversation.kind == ConversationKind.group)
            if (doDia != null && doDia.indicadas.isNotEmpty)
              _FaixaDoDia(
                doDia: doDia,
                userId: widget.userId,
                onTap: () => abrirDisputaDoDia(
                  context,
                  conversation: conversation,
                  userId: widget.userId,
                ),
              ),
          if (!_searching)
            const DicaCard(
              dica: Dica.chat,
              texto:
                  'O botão com a marca dispara o Chamado. Arraste uma mensagem '
                  'para o lado para responder, toque duas vezes para um ❤️, e '
                  'segure para copiar, encaminhar, reagir, fixar, editar ou '
                  'apagar — no grupo, também para indicar para a do dia. Com '
                  'o campo vazio, o microfone grava um recado; no grupo, "@" '
                  'chama alguém pelo nome. *negrito*, _itálico_, ~riscado~ e '
                  '`código` funcionam como no WhatsApp.',
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
                final porId = {for (final m in list) m.id: m};
                final itens = linhaDoTempo(
                  list,
                  userId: widget.userId,
                  lidaAte: _lidaAte,
                ).reversed.toList();
                final agora = ref.read(clockProvider)();
                final novasLaEmbaixo = _chegaramLaEmbaixo(list);
                final lista = ListView.builder(
                  controller: _rolagem,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: itens.length,
                  itemBuilder: (context, i) => switch (itens[i]) {
                    InicioDoDia(:final dia) => _SeparadorDeDia(
                      rotulo: rotuloDoDia(dia, agora),
                    ),
                    MensagensNovas(:final quantas) => _FaixaDeNovas(
                      quantas: quantas,
                    ),
                    Bolha(message: final m) when m.isChamado => KeyedSubtree(
                      key: _chaveDe(m.id),
                      child: ChamadoCard(
                        chamadoId: m.chamadoId!,
                        userId: widget.userId,
                      ),
                    ),
                    Bolha(message: final m, :final emendada) => _Bubble(
                      key: _chaveDe(m.id),
                      message: m,
                      conversation: conversation,
                      mine: m.authorId == widget.userId,
                      showAuthor:
                          conversation.kind == ConversationKind.group &&
                          !emendada,
                      emendada: emendada,
                      destacada: _destacada == m.id,
                      // A citada sai da própria lista: ela é sempre da mesma
                      // conversa, então já está aqui.
                      quoted: m.replyTo == null ? null : porId[m.replyTo],
                      userId: widget.userId,
                      onMenu: () => _openMessageMenu(m),
                      onSwipe: () => _responder(m),
                      onDoubleTap: () => _react(m, reacaoRapida),
                      onReact: (emoji) => _react(m, emoji),
                      onVerReacoes: () => _verReacoes(m),
                      onQuoteTap: m.replyTo == null
                          ? null
                          : () => _irPara(m.replyTo!),
                      seloDoDia: _seloDoDia(doDia, m),
                    ),
                  },
                );
                return Stack(
                  children: [
                    lista,
                    if (_longeDoFim)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Badge(
                          isLabelVisible: novasLaEmbaixo > 0,
                          label: Text('$novasLaEmbaixo'),
                          child: FloatingActionButton.small(
                            heroTag: null,
                            tooltip: 'Descer para o fim',
                            onPressed: _descer,
                            child: const Icon(Icons.keyboard_arrow_down),
                          ),
                        ),
                      ),
                  ],
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
          if (!_searching && _editando != null)
            _EditBar(message: _editando!, onCancel: _pararDeEditar)
          else if (!_searching && _replyTo != null)
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

/// Quebra [text] nos trechos que casam com [query] para destacá-los. Como
/// [semAcento] preserva o comprimento, as posições do texto dobrado valem no
/// original.
List<InlineSpan> _highlight(String text, String query, TextStyle destaque) {
  final termo = semAcento(query);
  if (termo.isEmpty) return [TextSpan(text: text)];
  final alvo = semAcento(text);
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

/// O texto da mensagem formatado: *negrito*, _itálico_, ~riscado~, `código`,
/// links que abrem no toque e as menções em destaque — a minha (ou o
/// "@todos") com fundo, para saltar aos olhos.
class _TextoFormatado extends StatefulWidget {
  const _TextoFormatado({
    required this.texto,
    required this.nomes,
    required this.userId,
  });

  final String texto;
  final Map<String, String> nomes;
  final String userId;

  @override
  State<_TextoFormatado> createState() => _TextoFormatadoState();
}

class _TextoFormatadoState extends State<_TextoFormatado> {
  /// Um reconhecedor por link, que precisa ser descartado junto com a bolha.
  final _toques = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _limpar();
    super.dispose();
  }

  void _limpar() {
    for (final t in _toques) {
      t.dispose();
    }
    _toques.clear();
  }

  Future<void> _abrir(String endereco) async {
    final uri = Uri.tryParse(endereco);
    final messenger = ScaffoldMessenger.of(context);
    final abriu =
        uri != null &&
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        ).catchError((_) => false);
    if (!abriu) {
      messenger.showSnackBar(
        SnackBar(content: Text('Não deu para abrir $endereco')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final trechos = trechosDoTexto(
      widget.texto,
      nomes: widget.nomes,
      userId: widget.userId,
    );
    if (textoSimples(trechos)) return Text(widget.texto);
    final scheme = Theme.of(context).colorScheme;
    _limpar();
    final partes = <InlineSpan>[
      for (final t in trechos)
        TextSpan(
          text: t.texto,
          recognizer: t.link == null ? null : _toque(t.link!),
          style: TextStyle(
            fontWeight: t.negrito || t.mencaoMinha != null
                ? FontWeight.bold
                : null,
            fontStyle: t.italico ? FontStyle.italic : null,
            decoration: t.link != null
                ? TextDecoration.underline
                : t.riscado
                ? TextDecoration.lineThrough
                : null,
            fontFamily: t.codigo ? 'monospace' : null,
            color: t.link != null || t.mencaoMinha != null
                ? scheme.primary
                : null,
            backgroundColor: t.codigo
                ? scheme.onSurface.withValues(alpha: 0.08)
                : t.mencaoMinha == true
                ? scheme.primary.withValues(alpha: 0.15)
                : null,
          ),
        ),
    ];
    return Text.rich(TextSpan(children: partes));
  }

  TapGestureRecognizer _toque(String link) {
    final toque = TapGestureRecognizer()..onTap = () => _abrir(link);
    _toques.add(toque);
    return toque;
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

/// Quem está numa call do Discord agora: a faixa só aparece com alguém lá, e
/// o toque abre o Discord do grupo ao vivo.
class _NaCall extends ConsumerWidget {
  const _NaCall({required this.group, required this.userId});

  final Group group;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agora = ref
        .watch(discordAoVivoProvider(group.discordServidor!))
        .value;
    final naCall = agora?.naCall ?? const [];
    if (naCall.isEmpty) return const SizedBox.shrink();
    final calls = agora!.calls;
    final onde = calls.length == 1 ? ' · ${calls.single.nome}' : '';
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => DiscordAoVivoScreen(group: group, userId: userId),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.headset_mic,
                size: 18,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Na call: ${[for (final m in naCall) m.nome].join(', ')}$onde',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: scheme.onSecondaryContainer),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

/// A faixa da disputa de hoje, no topo da conversa do grupo.
class _FaixaDoDia extends StatelessWidget {
  const _FaixaDoDia({
    required this.doDia,
    required this.userId,
    required this.onTap,
  });

  final DoDia doDia;
  final String userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = doDia.indicadas.length;
    final votou = doDia.votos.containsKey(userId);
    return Material(
      color: scheme.tertiaryContainer,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.star, size: 18, color: scheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'A do dia · ${n == 1 ? '1 indicada' : '$n indicadas'}',
                  style: TextStyle(color: scheme.onTertiaryContainer),
                ),
              ),
              Text(
                votou ? 'Você votou' : 'Votar',
                style: TextStyle(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
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
  const _Titulo({
    required this.titulo,
    required this.status,
    this.foto,
    this.onTap,
  });

  final String titulo;
  final String status;
  final Widget? foto;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final textos = status.isEmpty
        ? Text(titulo)
        : Column(
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
    final foto = this.foto;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            if (foto != null) ...[foto, const SizedBox(width: 10)],
            Expanded(child: textos),
          ],
        ),
      ),
    );
  }
}

/// A mensagem sendo editada, acima do campo, até salvar ou desistir.
class _EditBar extends StatelessWidget {
  const _EditBar({required this.message, required this.onCancel});

  final Message message;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            Icon(Icons.edit_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Editando mensagem',
                    style: TextStyle(
                      color: scheme.primary,
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
              tooltip: 'Cancelar edição',
              icon: const Icon(Icons.close),
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Hoje", "Ontem", "12/10": o dia que começa, no meio da conversa.
class _SeparadorDeDia extends StatelessWidget {
  const _SeparadorDeDia({required this.rotulo});

  final String rotulo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(rotulo, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

/// Daqui para baixo, o que chegou desde a última vez que a conversa abriu.
class _FaixaDeNovas extends StatelessWidget {
  const _FaixaDeNovas({required this.quantas});

  final int quantas;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(vertical: 4),
      color: scheme.primary.withValues(alpha: 0.10),
      alignment: Alignment.center,
      child: Text(
        quantas == 1 ? '1 mensagem nova' : '$quantas mensagens novas',
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(color: scheme.primary, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Arrastar a bolha para a direita responde a ela, como no WhatsApp: a bolha
/// acompanha o dedo, a seta aparece, e passou do ponto, vale.
class _ArrastarParaResponder extends StatefulWidget {
  const _ArrastarParaResponder({
    required this.onResponder,
    required this.child,
  });

  final VoidCallback onResponder;
  final Widget child;

  @override
  State<_ArrastarParaResponder> createState() => _ArrastarParaResponderState();
}

class _ArrastarParaResponderState extends State<_ArrastarParaResponder>
    with SingleTickerProviderStateMixin {
  static const _ponto = 64.0;
  static const _maximo = 88.0;

  late final AnimationController _volta = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(() => setState(() => _dx = _soltouEm * (1 - _volta.value)));
  double _dx = 0;
  double _soltouEm = 0;
  bool _avisou = false;

  @override
  void dispose() {
    _volta.dispose();
    super.dispose();
  }

  void _mexeu(DragUpdateDetails d) {
    _volta.stop();
    setState(() => _dx = (_dx + d.delta.dx).clamp(0.0, _maximo));
    // A vibradinha avisa que soltar agora responde.
    if (!_avisou && _dx >= _ponto) {
      _avisou = true;
      HapticFeedback.selectionClick();
    } else if (_dx < _ponto) {
      _avisou = false;
    }
  }

  void _soltou([DragEndDetails? _]) {
    if (_dx >= _ponto) widget.onResponder();
    _avisou = false;
    _soltouEm = _dx;
    _volta.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final progresso = (_dx / _ponto).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _mexeu,
      onHorizontalDragEnd: _soltou,
      onHorizontalDragCancel: _soltou,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          if (_dx > 0)
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Opacity(
                opacity: progresso,
                child: Transform.scale(
                  scale: 0.6 + 0.4 * progresso,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHigh,
                    child: const Icon(Icons.reply, size: 18),
                  ),
                ),
              ),
            ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
}

/// Dois toques rápidos na bolha. Feito com os toques crus, e não com o
/// reconhecedor de toque duplo do Flutter: aquele segura o primeiro toque à
/// espera do segundo, e o play do recado ou a foto ficariam lerdos. Os
/// toques que começam num botão de dentro (a foto, o play, uma reação) são
/// deles — [_DuploToque.ignorar] marca esses.
class _DuploToque extends StatefulWidget {
  const _DuploToque({required this.onDuploToque, required this.child});

  final VoidCallback onDuploToque;
  final Widget child;

  /// Embrulha um pedaço da bolha cujos toques não contam para o duplo.
  static Widget ignorar(Widget child) => Builder(
    builder: (context) => Listener(
      onPointerDown: (_) =>
          context.findAncestorStateOfType<_DuploToqueState>()?._ignorar = true,
      child: child,
    ),
  );

  @override
  State<_DuploToque> createState() => _DuploToqueState();
}

class _DuploToqueState extends State<_DuploToque> {
  static const _intervalo = Duration(milliseconds: 300);
  static const _toqueCurto = Duration(milliseconds: 250);

  bool _ignorar = false;
  DateTime? _desceu;
  Offset? _onde;
  bool _mexeu = false;
  DateTime? _ultimoToque;
  Offset? _ultimoOnde;

  void _down(PointerDownEvent e) {
    _desceu = DateTime.now();
    _onde = e.position;
    _mexeu = false;
  }

  void _move(PointerMoveEvent e) {
    final onde = _onde;
    if (onde != null && (e.position - onde).distance > kTouchSlop) {
      _mexeu = true;
    }
  }

  void _up(PointerUpEvent e) {
    final agora = DateTime.now();
    final desceu = _desceu;
    final valeu =
        !_ignorar &&
        !_mexeu &&
        desceu != null &&
        agora.difference(desceu) < _toqueCurto;
    _ignorar = false;
    if (!valeu) {
      _ultimoToque = null;
      return;
    }
    final anterior = _ultimoToque;
    final ondeAntes = _ultimoOnde;
    if (anterior != null &&
        ondeAntes != null &&
        agora.difference(anterior) < _intervalo &&
        (e.position - ondeAntes).distance < kDoubleTapSlop) {
      _ultimoToque = null;
      HapticFeedback.lightImpact();
      widget.onDuploToque();
    } else {
      _ultimoToque = agora;
      _ultimoOnde = e.position;
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: (_) => _ultimoToque = null,
    child: widget.child,
  );
}

class _Bubble extends ConsumerWidget {
  const _Bubble({
    super.key,
    required this.message,
    required this.conversation,
    required this.mine,
    required this.showAuthor,
    required this.userId,
    required this.onMenu,
    required this.onSwipe,
    required this.onDoubleTap,
    required this.onReact,
    required this.onVerReacoes,
    this.onQuoteTap,
    this.emendada = false,
    this.destacada = false,
    this.quoted,
    this.seloDoDia,
  });

  /// Continua a bolha de cima: fica mais perto dela.
  final bool emendada;

  /// Acabou de ser alcançada por uma citação ou pela busca.
  final bool destacada;

  final Message message;
  final Conversation conversation;

  /// "🏆 A do dia · 05/10" ou "⭐ Indicada · 2 votos"; nulo = nada.
  final String? seloDoDia;
  final bool mine;
  final bool showAuthor;

  /// A mensagem que esta responde, quando ela ainda está na conversa.
  final Message? quoted;

  /// Quem está olhando a conversa: é a reação dele que fica em destaque.
  final String userId;

  /// Toque longo: o menu da mensagem.
  final VoidCallback onMenu;

  /// Arrastada para o lado: responder.
  final VoidCallback onSwipe;

  /// Dois toques: a reação rápida.
  final VoidCallback onDoubleTap;
  final void Function(String emoji) onReact;

  /// Segurar uma reação: quem reagiu.
  final VoidCallback onVerReacoes;

  /// Tocar na citação: ir até a citada.
  final VoidCallback? onQuoteTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final author = ref.watch(repositoryProvider).profile(message.authorId);
    final anexo = message.attachment;
    final legenda = message.text ?? '';
    final citada = quoted;
    final cor = mine ? scheme.primaryContainer : scheme.surfaceContainerHighest;

    final bolha = GestureDetector(
      onLongPress: () {
        HapticFeedback.mediumImpact();
        onMenu();
      },
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          margin: EdgeInsets.fromLTRB(8, emendada ? 1 : 4, 8, 1),
          padding: anexo == null
              ? const EdgeInsets.fromLTRB(12, 8, 12, 6)
              : const EdgeInsets.fromLTRB(6, 6, 6, 4),
          decoration: BoxDecoration(
            color: destacada
                ? Color.alphaBlend(scheme.primary.withValues(alpha: 0.30), cor)
                : cor,
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
                if (message.forwarded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shortcut, size: 14, color: scheme.outline),
                        const SizedBox(width: 4),
                        Text(
                          'Encaminhada',
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: scheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (citada != null) ...[
                  _DuploToque.ignorar(
                    GestureDetector(
                      onTap: onQuoteTap,
                      child: _Quote(message: citada, mine: mine),
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                if (anexo != null) ...[
                  if (anexo.kind == AttachmentKind.audio)
                    _DuploToque.ignorar(
                      ChatAudio(attachment: anexo, mine: mine),
                    )
                  else
                    _DuploToque.ignorar(
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
                    ),
                  if (legenda.isNotEmpty) const SizedBox(height: 4),
                ],
                if (legenda.isNotEmpty)
                  _TextoFormatado(
                    texto: legenda,
                    nomes: {
                      for (final id in conversation.memberIds)
                        id: ref.watch(repositoryProvider).profile(id).name,
                    },
                    userId: userId,
                  ),
                if (message.reactions.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _DuploToque.ignorar(
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
                            onLongPress: onVerReacoes,
                          ),
                      ],
                    ),
                  ),
                ],
              ],
              if (seloDoDia case final selo?)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    selo,
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
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
    );

    // Mensagem apagada não se responde nem recebe reação.
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: message.isDeleted
          ? bolha
          : _ArrastarParaResponder(
              onResponder: onSwipe,
              child: _DuploToque(onDuploToque: onDoubleTap, child: bolha),
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
    required this.onLongPress,
  });

  final String emoji;
  final int quantas;
  final bool minha;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
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
