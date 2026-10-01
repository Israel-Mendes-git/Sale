import 'package:flutter/foundation.dart';

@immutable
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.emoji,
    required this.color,
    this.named = false,
  });

  final String id;
  final String name;

  /// A pessoa já escolheu como quer ser chamada (senão [name] é provisório).
  final bool named;

  /// Avatar provisório enquanto não há foto (virá do Discord/Google).
  final String emoji;
  final int color;

  Profile copyWith({String? name, bool? named}) => Profile(
    id: id,
    name: name ?? this.name,
    emoji: emoji,
    color: color,
    named: named ?? this.named,
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
    required this.emoji,
    required this.label,
    required this.kind,
    this.ownerId,
    this.asksEta = false,
    this.etaMinutes,
  });

  final String id;
  final String? ownerId;
  final String emoji;
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
  });

  final QuickReply reply;
  final DateTime respondedAt;
  final int? etaMinutes;

  /// Horário prometido de chegada, quando há tempo estimado.
  DateTime? get eta => etaMinutes == null
      ? null
      : respondedAt.add(Duration(minutes: etaMinutes!));
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
  });

  final String id;
  final String conversationId;
  final String authorId;
  final DateTime createdAt;

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

  Chamado copyWith({
    ChamadoStatus? status,
    Map<String, ChamadoResponse?>? responses,
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
      status: status,
      responses: responses,
    );
  }
}

/// Grupo de amigos: dono das conversas, dos jogos e do encontro fixo.
@immutable
class Group {
  const Group({
    required this.id,
    required this.name,
    required this.inviteCode,
  });

  final String id;
  final String name;

  /// O que a pessoa manda para alguém novo entrar no grupo.
  final String inviteCode;
}
