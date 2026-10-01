import '../domain/calendar.dart';
import '../domain/games.dart';
import '../domain/models.dart';

const maxNameLength = 24;
const maxReplyLength = 40;
const maxGroupNameLength = 40;

/// Tudo o que as telas precisam do backend.
///
/// Duas implementações: [MemoryRepository], para desenvolver as telas sem
/// servidor, e `SupabaseRepository`, usada quando o APK sai com a
/// configuração do Supabase.
abstract interface class SaleRepository {
  List<Profile> get profiles;
  Profile profile(String id);

  /// Respostas comuns a todos mais as próprias de [userId].
  List<QuickReply> quickRepliesFor(String userId);

  /// Grupos de que a pessoa participa. Enquanto estiver vazia, o app pede
  /// para criar um grupo ou entrar com um código de convite.
  Stream<List<Group>> watchGroups(String userId);

  /// Cria o grupo (com a conversa do grupo) e entra nele.
  Future<void> createGroup(String name);

  /// Entra num grupo pelo código de convite.
  Future<void> joinGroup(String inviteCode);

  Stream<List<Conversation>> watchConversations(String userId);
  Stream<List<Message>> watchMessages(String conversationId);
  Stream<Chamado> watchChamado(String chamadoId);

  /// Chamados abertos que ainda esperam resposta de [userId].
  Stream<List<Chamado>> watchPendingFor(String userId);

  Future<void> sendText({
    required String conversationId,
    required String authorId,
    required String text,
  });

  Future<Chamado> sendChamado({
    required String conversationId,
    required String authorId,
    required List<String> targetIds,
    String? gameId,
    bool drawGame = false,
    String? note,
    DateTime? scheduledFor,
  });

  /// Veta o jogo sorteado e sorteia outro entre os que sobraram.
  Future<void> vetoGame({required String chamadoId, required String userId});

  Future<void> respond({
    required String chamadoId,
    required String userId,
    required QuickReply reply,
    int? etaMinutes,
  });

  Future<void> closeChamado(String chamadoId);

  // Perfil.

  /// Troca o nome exibido. Recusa nome vazio ou com mais de [maxNameLength].
  Future<void> renameProfile(String userId, String name);

  /// Cria uma resposta própria de [ownerId]. "Vou, mas depois" pergunta o
  /// tempo na hora de responder. [icon] é um nome de `replyIcons`.
  Future<QuickReply> addQuickReply({
    required String ownerId,
    required String icon,
    required String label,
    required ReplyKind kind,
  });

  /// Remove uma resposta própria; as comuns a todos não podem ser removidas.
  Future<void> removeQuickReply(String replyId);

  // Jogos.

  Stream<GameLibrary> watchGames();

  /// Adiciona um jogo, já marcado como de [addedBy].
  Future<Game> addGame({
    required String name,
    required int minPlayers,
    required int maxPlayers,
    required String addedBy,
  });

  Future<void> setOwnsGame({
    required String gameId,
    required String userId,
    required bool owns,
  });

  Future<void> removeGame(String gameId);

  // Calendário.

  /// Encontros dos grupos de [userId], exceções, confirmações, a
  /// disponibilidade de todos e os Chamados agendados abertos em que
  /// [userId] chamou ou foi chamado.
  Stream<CalendarData> watchCalendar(String userId);

  /// Cria ou substitui o encontro fixo da conversa (um por grupo).
  Future<void> saveMeeting({
    required String conversationId,
    required int weekday,
    required int minute,
    String? game,
  });

  Future<void> deleteMeeting(String meetingId);

  /// Cria ou substitui a exceção daquela data.
  Future<void> setMeetingException(MeetingException exception);

  Future<void> clearMeetingException(String meetingId, DateTime date);

  /// Cria ou substitui a confirmação da pessoa naquela data.
  Future<void> setRsvp(Rsvp rsvp);

  Future<void> addAvailability({
    required String userId,
    required int weekday,
    required TimeRange range,
  });

  Future<void> removeAvailability(String availabilityId);
}
