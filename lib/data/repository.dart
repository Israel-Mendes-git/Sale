import '../domain/calendar.dart';
import '../domain/models.dart';

/// Tudo o que as telas precisam do backend.
///
/// Hoje existe só a versão em memória ([MemoryRepository]); a do Supabase
/// entra implementando esta mesma interface.
abstract interface class SaleRepository {
  List<Profile> get profiles;
  Profile profile(String id);

  /// Respostas comuns a todos mais as próprias de [userId].
  List<QuickReply> quickRepliesFor(String userId);

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
    String? game,
    String? note,
    DateTime? scheduledFor,
  });

  Future<void> respond({
    required String chamadoId,
    required String userId,
    required QuickReply reply,
    int? etaMinutes,
  });

  Future<void> closeChamado(String chamadoId);

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
