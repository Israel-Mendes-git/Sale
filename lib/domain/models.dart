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
  });

  final String id;
  final String name;

  /// A pessoa já escolheu como quer ser chamada (senão [name] é provisório).
  final bool named;

  /// Foto que veio do Discord ou do Google.
  final String? avatarUrl;

  /// Reserva para quem não tem foto: emoji sorteado sobre a cor.
  final String emoji;
  final int color;

  Profile copyWith({String? name, bool? named}) => Profile(
    id: id,
    name: name ?? this.name,
    emoji: emoji,
    color: color,
    named: named ?? this.named,
    avatarUrl: avatarUrl,
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

@immutable
class Conversation {
  const Conversation({
    required this.id,
    required this.kind,
    required this.memberIds,
    this.name,
  });

  final String id;
  final ConversationKind kind;
  final List<String> memberIds;

  /// Só para grupos; conversa individual usa o nome do outro membro.
  final String? name;
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
  });

  final String id;
  final String conversationId;
  final String authorId;
  final DateTime createdAt;
  final String? text;

  /// Preenchido quando a mensagem é o card de um Chamado.
  final String? chamadoId;

  bool get isChamado => chamadoId != null;
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

  Chamado copyWith({
    ChamadoStatus? status,
    Map<String, ChamadoResponse?>? responses,
    DateTime? nudgedAt,
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

/// Grupo de amigos: dono das conversas, dos jogos e do encontro fixo.
@immutable
class Group {
  const Group({required this.id, required this.name, required this.inviteCode});

  final String id;
  final String name;

  /// O que a pessoa manda para alguém novo entrar no grupo.
  final String inviteCode;
}
