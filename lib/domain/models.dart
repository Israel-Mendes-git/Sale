import 'package:flutter/foundation.dart';

@immutable
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.emoji,
    required this.color,
    this.named = false,
    this.avatarUrl,
    this.soundId,
  });

  final String id;
  final String name;

  /// O som que esta pessoa usa quando chama, escolhido em "Meu perfil → Som
  /// do Chamado". Nulo = o som da marca.
  final String? soundId;

  /// A pessoa já escolheu como quer ser chamada (senão [name] é provisório).
  final bool named;

  /// Foto que veio do Discord ou do Google.
  final String? avatarUrl;

  /// Reserva para quem não tem foto: emoji sorteado sobre a cor.
  final String emoji;
  final int color;

  /// [soundId] com `clearSound` é o jeito de voltar ao som da marca: nulo
  /// sozinho quer dizer "não mexe".
  Profile copyWith({
    String? name,
    bool? named,
    String? soundId,
    bool clearSound = false,
  }) => Profile(
    id: id,
    name: name ?? this.name,
    emoji: emoji,
    color: color,
    named: named ?? this.named,
    avatarUrl: avatarUrl,
    soundId: clearSound ? null : soundId ?? this.soundId,
  );
}

/// Botão de resposta rápida a um Chamado.
///
/// [ownerId] nulo = resposta comum a todos; preenchido = resposta própria
/// daquela pessoa, cadastrada por ela mesma ("No trabalho").
@immutable
class QuickReply {
  const QuickReply({
    required this.id,
    required this.icon,
    required this.label,
    required this.kind,
    this.ownerId,
    this.asksEta = false,
    this.etaMinutes,
  });

  final String id;
  final String? ownerId;

  /// Nome do desenho, de `replyIcons`.
  final String icon;
  final String label;
  final ReplyKind kind;

  /// Pergunta "quanto tempo?" antes de responder.
  final bool asksEta;

  /// Tempo já embutido na resposta ("Chego em 10 min").
  final int? etaMinutes;
}

/// Como a resposta conta para o Chamado.
enum ReplyKind {
  /// Vai jogar agora.
  yes,

  /// Vai jogar, mas depois de um tempo.
  later,

  /// Não vai.
  no,

  /// Pediu para ser chamado de novo.
  snooze,
}

enum ConversationKind { direct, group }

/// Em que pé está a mensagem que eu mandei: parada no servidor, no aparelho
/// de quem vai ler, ou já vista por ela.
enum MessageStatus { sent, delivered, read }

/// Até onde uma pessoa recebeu e viu as mensagens de uma conversa.
///
/// São duas datas em vez de uma marca por mensagem: mensagem mais velha que a
/// data está entregue (ou lida), e contar as novas é comparar datas. Nulo =
/// nunca recebeu, ou nunca abriu, nada dali.
@immutable
class Receipt {
  const Receipt({this.deliveredUntil, this.readUntil});

  final DateTime? deliveredUntil;
  final DateTime? readUntil;

  bool delivered(DateTime moment) =>
      !(deliveredUntil?.isBefore(moment) ?? true);

  bool read(DateTime moment) => !(readUntil?.isBefore(moment) ?? true);
}

@immutable
class Conversation {
  const Conversation({
    required this.id,
    required this.kind,
    required this.memberIds,
    this.name,
    this.receipts = const {},
  });

  final String id;
  final ConversationKind kind;
  final List<String> memberIds;

  /// Só para grupos; conversa individual usa o nome do outro membro.
  final String? name;

  /// Por pessoa, até onde ela recebeu e viu as mensagens daqui.
  final Map<String, Receipt> receipts;

  Receipt receiptOf(String userId) => receipts[userId] ?? const Receipt();

  /// Em que pé está [message], olhando quem mais está na conversa.
  ///
  /// A marca é a do último: num grupo de três, a mensagem só ganha o segundo
  /// tique quando chegou nos dois aparelhos, e só fica lida quando os dois
  /// abriram. É mais honesto do que celebrar o primeiro que viu.
  MessageStatus statusOf(Message message) {
    final others = [
      for (final id in memberIds)
        if (id != message.authorId) id,
    ];
    if (others.every((id) => receiptOf(id).read(message.createdAt))) {
      return MessageStatus.read;
    }
    if (others.every((id) => receiptOf(id).delivered(message.createdAt))) {
      return MessageStatus.delivered;
    }
    return MessageStatus.sent;
  }

  /// Quantas mensagens de outra pessoa chegaram depois da última vez que
  /// [userId] abriu esta conversa.
  int unreadFor(String userId, List<Message> messages) {
    final receipt = receiptOf(userId);
    var count = 0;
    for (final message in messages) {
      if (message.authorId == userId) continue;
      if (!receipt.read(message.createdAt)) count++;
    }
    return count;
  }

  Conversation withReceipts(Map<String, Receipt> receipts) => Conversation(
    id: id,
    kind: kind,
    memberIds: memberIds,
    name: name,
    receipts: receipts,
  );
}

/// Os emojis que o menu da mensagem oferece. Reação é resposta rápida: uma
/// fileira que caiba na tela, não um teclado inteiro.
const reactionEmojis = ['👍', '❤️', '😂', '🔥', '😮', '😢'];

/// O que vem anexado numa mensagem. Por enquanto, imagem.
enum AttachmentKind { image, audio }

/// O arquivo que acompanha a mensagem: ele mora no Storage, e aqui ficam o
/// caminho e o que o app precisa para montar a bolha antes de baixá-lo.
@immutable
class Attachment {
  const Attachment({
    required this.path,
    required this.kind,
    this.width,
    this.height,
    this.duration,
  });

  /// Onde o arquivo está no Storage: `<conversa>/<arquivo>`.
  final String path;
  final AttachmentKind kind;

  /// O tamanho da imagem, para a bolha já nascer na proporção certa em vez de
  /// a conversa saltar quando o arquivo termina de baixar.
  final int? width;
  final int? height;

  /// A duração do áudio, em segundos: a bolha a mostra antes de baixar o
  /// arquivo, e o player a usa de ponto de partida.
  final int? duration;

  double? get aspectRatio {
    final (w, h) = (width, height);
    if (w == null || h == null || h == 0) return null;
    return w / h;
  }
}

@immutable
class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.authorId,
    required this.createdAt,
    this.text,
    this.chamadoId,
    this.attachment,
    this.replyTo,
    this.reactions = const {},
    this.editedAt,
    this.deletedAt,
  });

  final String id;
  final String conversationId;
  final String authorId;
  final DateTime createdAt;

  /// Texto da mensagem — ou a legenda, quando vem com [attachment].
  final String? text;

  /// Preenchido quando a mensagem é o card de um Chamado.
  final String? chamadoId;

  /// Preenchido quando a mensagem leva um arquivo.
  final Attachment? attachment;

  /// A mensagem que esta responde, se for uma resposta citada. É sempre da
  /// mesma conversa; nulo também quando a citada foi apagada depois.
  final String? replyTo;

  /// Quem reagiu e com qual emoji. Uma reação por pessoa.
  final Map<String, String> reactions;

  /// Quando o autor editou a mensagem. Nulo = nunca editada.
  final DateTime? editedAt;

  /// Quando o autor apagou a mensagem. Nulo = não apagada. Apagada vira uma
  /// lápide: sem texto, sem anexo, sem reações.
  final DateTime? deletedAt;

  bool get isEdited => editedAt != null;
  bool get isDeleted => deletedAt != null;

  /// Quantas vezes cada emoji aparece, do mais reagido para o menos.
  List<(String emoji, int quantas)> get reactionCounts {
    final contagem = <String, int>{};
    for (final emoji in reactions.values) {
      contagem[emoji] = (contagem[emoji] ?? 0) + 1;
    }
    final lista = contagem.entries.map((e) => (e.key, e.value)).toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    return lista;
  }

  bool get isChamado => chamadoId != null;
  bool get isImage => attachment?.kind == AttachmentKind.image;
  bool get isAudio => attachment?.kind == AttachmentKind.audio;
}

enum ChamadoStatus {
  open,

  /// Todos os chamados responderam.
  answered,

  /// Quem chamou encerrou.
  closed,
}

@immutable
class ChamadoResponse {
  const ChamadoResponse({
    required this.reply,
    required this.respondedAt,
    this.etaMinutes,
    this.arrivedAt,
    this.snoozedUntil,
  });

  final QuickReply reply;
  final DateTime respondedAt;
  final int? etaMinutes;

  /// A hora em que o Chamado volta para quem pediu "me chama daqui a pouco".
  /// Nulo em toda resposta que não é soneca — e também depois que a soneca
  /// acorda ou perde a hora.
  final DateTime? snoozedUntil;

  /// Quando a pessoa marcou "Cheguei". É o que o placar do atraso compara
  /// com a hora prometida (`Chamado.promisedBy`).
  final DateTime? arrivedAt;

  /// A hora prometida, contando de [from]: quem vem na hora chega em [from];
  /// quem pediu um tempo, o tempo depois dele. Quem não vem não promete.
  ///
  /// Quem conhece o [from] é o Chamado, porque um Chamado marcado para depois
  /// conta do horário marcado, não da hora em que a pessoa respondeu.
  DateTime? promiseFrom(DateTime from) => switch (reply.kind) {
    ReplyKind.yes => from,
    ReplyKind.later =>
      etaMinutes == null ? null : from.add(Duration(minutes: etaMinutes!)),
    ReplyKind.no || ReplyKind.snooze => null,
  };

  /// A mesma resposta, com a chegada marcada.
  ChamadoResponse arriving(DateTime at) => ChamadoResponse(
    reply: reply,
    respondedAt: respondedAt,
    etaMinutes: etaMinutes,
    arrivedAt: at,
    snoozedUntil: snoozedUntil,
  );

  /// A mesma resposta sem a soneca pendente: o 💤 continua no card, mas o
  /// Chamado não volta mais por ele.
  ChamadoResponse withoutSnooze() => ChamadoResponse(
    reply: reply,
    respondedAt: respondedAt,
    etaMinutes: etaMinutes,
    arrivedAt: arrivedAt,
  );
}

@immutable
class Chamado {
  const Chamado({
    required this.id,
    required this.conversationId,
    required this.authorId,
    required this.createdAt,
    required this.responses,
    this.game,
    this.gameId,
    this.drawn = false,
    this.vetoes = const {},
    this.note,
    this.scheduledFor,
    this.status = ChamadoStatus.open,
    this.automatic = false,
    this.nudgedAt,
    this.expiredAt,
    this.soundKey,
  });

  final String id;
  final String conversationId;
  final String authorId;
  final DateTime createdAt;

  /// Nasceu do encontro fixo, na hora marcada, sem ninguém apertar o botão.
  /// Aí [authorId] é só quem criou o grupo: o card diz "Encontro fixo".
  final bool automatic;

  /// Nome do jogo; nulo = "qualquer coisa".
  final String? game;

  /// Jogo da biblioteca, quando veio de lá.
  final String? gameId;

  /// O jogo foi sorteado (e pode ser vetado).
  final bool drawn;

  /// Quem vetou qual jogo (id). Cada pessoa veta uma vez.
  final Map<String, String> vetoes;
  final String? note;

  /// Nulo = agora.
  final DateTime? scheduledFor;
  final ChamadoStatus status;

  /// Quando o Chamado tocou de novo porque ninguém respondeu. Uma vez só por
  /// Chamado: o batsinal insiste, não fica apitando a noite toda.
  final DateTime? nudgedAt;

  /// Quando o Chamado fechou sozinho, de tanto esperar resposta. Preenchido
  /// só nesse caso: encerrado por quem chamou é outra coisa, e o card diz
  /// qual foi.
  final DateTime? expiredAt;

  /// Com que som este Chamado toca: a chave do som escolhido por quem chamou
  /// ([Sound.key]). Nulo = o som da marca, que é o do encontro fixo e o de
  /// quem não escolheu nada.
  final String? soundKey;

  /// Uma entrada por pessoa chamada; valor nulo = ainda não respondeu.
  final Map<String, ChamadoResponse?> responses;

  Iterable<String> get targetIds => responses.keys;

  /// Quem chamou e quem foi chamado.
  Set<String> get participants => {authorId, ...responses.keys};

  bool canVeto(String userId) =>
      isOpen &&
      drawn &&
      gameId != null &&
      participants.contains(userId) &&
      !vetoes.containsKey(userId);
  bool get isOpen => status == ChamadoStatus.open;
  bool awaits(String userId) =>
      isOpen && responses.containsKey(userId) && responses[userId] == null;

  /// De quando conta a promessa de quem responde: do horário marcado, se o
  /// Chamado é para depois e a resposta veio antes dele; senão, da hora da
  /// própria resposta. Sem isso, quem diz "bora" de manhã para um Chamado da
  /// noite chegaria horas atrasado no placar.
  DateTime _promiseBase(ChamadoResponse response) {
    final marked = scheduledFor;
    return marked != null && marked.isAfter(response.respondedAt)
        ? marked
        : response.respondedAt;
  }

  /// A hora em que [userId] prometeu chegar; nulo quando não prometeu nada.
  DateTime? promisedBy(String userId) {
    final response = responses[userId];
    if (response == null) return null;
    return response.promiseFrom(_promiseBase(response));
  }

  /// Quanto [userId] passou do que prometeu; negativo = chegou antes. Nulo
  /// enquanto não marcar que chegou.
  Duration? lateBy(String userId) {
    final arrival = responses[userId]?.arrivedAt;
    final promised = promisedBy(userId);
    if (arrival == null || promised == null) return null;
    return arrival.difference(promised);
  }

  /// A pessoa prometeu vir e ainda não marcou que chegou — é dela que o
  /// placar espera o "Cheguei". Chamado encerrado por quem chamou não
  /// espera mais ninguém.
  bool awaitsArrival(String userId) {
    final response = responses[userId];
    return status != ChamadoStatus.closed &&
        response != null &&
        response.arrivedAt == null &&
        promisedBy(userId) != null;
  }

  /// Quem ainda não respondeu — é com essas pessoas que a insistência fala.
  Iterable<String> get silent => [
    for (final e in responses.entries)
      if (e.value == null) e.key,
  ];

  /// Fechou sozinho, de tanto esperar: o card diz "expirou", não "encerrado".
  bool get expired => expiredAt != null;

  /// A hora em que o Chamado desiste de esperar resposta. Conta do toque; o
  /// marcado que nunca tocou conta do horário marcado.
  DateTime get expiresAt => (scheduledFor ?? createdAt).add(chamadoLifetime);

  Chamado copyWith({
    ChamadoStatus? status,
    Map<String, ChamadoResponse?>? responses,
    DateTime? nudgedAt,
    DateTime? expiredAt,
  }) {
    return Chamado(
      id: id,
      conversationId: conversationId,
      authorId: authorId,
      createdAt: createdAt,
      game: game,
      gameId: gameId,
      drawn: drawn,
      vetoes: vetoes,
      note: note,
      scheduledFor: scheduledFor,
      automatic: automatic,
      nudgedAt: nudgedAt ?? this.nudgedAt,
      expiredAt: expiredAt ?? this.expiredAt,
      soundKey: soundKey,
      status: status ?? this.status,
      responses: responses ?? this.responses,
    );
  }

  /// Troca o jogo depois de um veto (nulo = acabaram as opções).
  Chamado withRedraw({
    required String? gameId,
    required String? game,
    required Map<String, String> vetoes,
  }) {
    return Chamado(
      id: id,
      conversationId: conversationId,
      authorId: authorId,
      createdAt: createdAt,
      game: game,
      gameId: gameId,
      drawn: drawn,
      vetoes: vetoes,
      note: note,
      scheduledFor: scheduledFor,
      automatic: automatic,
      nudgedAt: nudgedAt,
      expiredAt: expiredAt,
      soundKey: soundKey,
      status: status,
      responses: responses,
    );
  }
}

/// Quanto tempo depois da hora um disparo ainda vale: o encontro fixo que
/// chegou a hora, a insistência e a soneca. A mesma janela vale no servidor
/// (`janela_do_disparo`, no banco): o que atrasou demais não acorda mais
/// ninguém.
const fireWindow = Duration(minutes: 15);

/// Quanto tempo de silêncio antes de o Chamado tocar de novo
/// (`espera_da_insistencia`, no banco).
const nudgeDelay = Duration(minutes: 5);

/// O "daqui a pouco" de quem pede soneca sem escolher o tempo.
const defaultSnoozeMinutes = 15;

/// Quanto tempo o Chamado fica aberto esperando resposta antes de fechar
/// sozinho (`vida_do_chamado`, no banco). Passado isso, a hora de jogar
/// passou.
const chamadoLifetime = Duration(hours: 2);

/// Grupo de amigos: dono das conversas, dos jogos e do encontro fixo.
@immutable
class Group {
  const Group({required this.id, required this.name, required this.inviteCode});

  final String id;
  final String name;

  /// O que a pessoa manda para alguém novo entrar no grupo.
  final String inviteCode;
}
