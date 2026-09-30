import 'dart:async';

import '../domain/calendar.dart';
import '../domain/models.dart';
import 'repository.dart';
import 'seed.dart';

/// Backend falso, em memória, para desenvolver as telas sem servidor.
class MemoryRepository implements SaleRepository {
  MemoryRepository({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  final _changes = StreamController<void>.broadcast();
  final _messages = <Message>[];
  final _chamados = <String, Chamado>{};
  final _meetings = [...seedMeetings];
  final _exceptions = <MeetingException>[];
  final _rsvps = <Rsvp>[];
  final _availability = [...seedAvailability];
  var _nextId = 0;

  String _id(String prefix) => '$prefix-${_nextId++}';

  /// Emite o valor atual e depois um novo a cada mudança.
  Stream<T> _watch<T>(T Function() read) {
    StreamSubscription<void>? sub;
    final controller = StreamController<T>();
    controller
      ..onListen = () {
        // Assina antes de emitir para não perder mudança no meio do caminho.
        sub = _changes.stream.listen((_) => controller.add(read()));
        controller.add(read());
      }
      ..onCancel = () => sub?.cancel();
    return controller.stream;
  }

  void _notify() => _changes.add(null);

  @override
  List<Profile> get profiles => seedProfiles;

  @override
  Profile profile(String id) => seedProfiles.firstWhere((p) => p.id == id);

  @override
  List<QuickReply> quickRepliesFor(String userId) => [
    for (final r in seedQuickReplies)
      if (r.ownerId == null || r.ownerId == userId) r,
  ];

  DateTime _lastActivity(Conversation c) {
    final own = _messages.where((m) => m.conversationId == c.id);
    return own.isEmpty ? DateTime(0) : own.last.createdAt;
  }

  @override
  Stream<List<Conversation>> watchConversations(String userId) => _watch(() {
    final mine = [
      for (final c in seedConversations)
        if (c.memberIds.contains(userId)) c,
    ];
    mine.sort((a, b) => _lastActivity(b).compareTo(_lastActivity(a)));
    return mine;
  });

  @override
  Stream<List<Message>> watchMessages(String conversationId) => _watch(
    () => [
      for (final m in _messages)
        if (m.conversationId == conversationId) m,
    ],
  );

  @override
  Stream<Chamado> watchChamado(String chamadoId) =>
      _watch(() => _chamados[chamadoId]!);

  @override
  Stream<List<Chamado>> watchPendingFor(String userId) => _watch(
    () => [
      for (final c in _chamados.values)
        if (c.awaits(userId)) c,
    ],
  );

  @override
  Future<void> sendText({
    required String conversationId,
    required String authorId,
    required String text,
  }) async {
    _messages.add(
      Message(
        id: _id('msg'),
        conversationId: conversationId,
        authorId: authorId,
        createdAt: _clock(),
        text: text,
      ),
    );
    _notify();
  }

  @override
  Future<Chamado> sendChamado({
    required String conversationId,
    required String authorId,
    required List<String> targetIds,
    String? game,
    String? note,
    DateTime? scheduledFor,
  }) async {
    if (targetIds.isEmpty) {
      throw ArgumentError('Chamado sem ninguém para chamar.');
    }
    final now = _clock();
    final chamado = Chamado(
      id: _id('chamado'),
      conversationId: conversationId,
      authorId: authorId,
      createdAt: now,
      game: game,
      note: note,
      scheduledFor: scheduledFor,
      responses: {for (final id in targetIds) id: null},
    );
    _chamados[chamado.id] = chamado;
    _messages.add(
      Message(
        id: _id('msg'),
        conversationId: conversationId,
        authorId: authorId,
        createdAt: now,
        chamadoId: chamado.id,
      ),
    );
    _notify();
    return chamado;
  }

  @override
  Future<void> respond({
    required String chamadoId,
    required String userId,
    required QuickReply reply,
    int? etaMinutes,
  }) async {
    final chamado = _chamados[chamadoId]!;
    if (!chamado.responses.containsKey(userId)) {
      throw StateError('$userId não foi chamado em $chamadoId.');
    }
    if (!chamado.isOpen) return;

    final responses = Map.of(chamado.responses)
      ..[userId] = ChamadoResponse(
        reply: reply,
        respondedAt: _clock(),
        etaMinutes: etaMinutes ?? reply.etaMinutes,
      );
    final everyoneAnswered = responses.values.every((r) => r != null);
    _chamados[chamadoId] = chamado.copyWith(
      responses: responses,
      status: everyoneAnswered ? ChamadoStatus.answered : null,
    );
    _notify();
  }

  @override
  Future<void> closeChamado(String chamadoId) async {
    final chamado = _chamados[chamadoId]!;
    if (!chamado.isOpen) return;
    _chamados[chamadoId] = chamado.copyWith(status: ChamadoStatus.closed);
    _notify();
  }

  @override
  Stream<CalendarData> watchCalendar(String userId) => _watch(() {
    final myConversations = {
      for (final c in seedConversations)
        if (c.memberIds.contains(userId)) c.id,
    };
    return CalendarData(
      meetings: [
        for (final m in _meetings)
          if (myConversations.contains(m.conversationId)) m,
      ],
      exceptions: List.unmodifiable(_exceptions),
      rsvps: List.unmodifiable(_rsvps),
      availability: List.unmodifiable(_availability),
      scheduledChamados: [
        for (final c in _chamados.values)
          if (c.scheduledFor != null &&
              c.isOpen &&
              (c.authorId == userId || c.responses.containsKey(userId)))
            c,
      ],
    );
  });

  @override
  Future<void> saveMeeting({
    required String conversationId,
    required int weekday,
    required int minute,
    String? game,
  }) async {
    final existing = _meetings
        .where((m) => m.conversationId == conversationId)
        .firstOrNull;
    if (existing != null) {
      _meetings.remove(existing);
      // Exceções e confirmações valem para o dia antigo; mudou o dia, caem.
      if (existing.weekday != weekday) {
        _exceptions.removeWhere((e) => e.meetingId == existing.id);
        _rsvps.removeWhere((r) => r.meetingId == existing.id);
      }
    }
    _meetings.add(
      WeeklyMeeting(
        id: existing?.id ?? _id('encontro'),
        conversationId: conversationId,
        weekday: weekday,
        minute: minute,
        game: game,
      ),
    );
    _notify();
  }

  @override
  Future<void> deleteMeeting(String meetingId) async {
    _meetings.removeWhere((m) => m.id == meetingId);
    _exceptions.removeWhere((e) => e.meetingId == meetingId);
    _rsvps.removeWhere((r) => r.meetingId == meetingId);
    _notify();
  }

  @override
  Future<void> setMeetingException(MeetingException exception) async {
    _exceptions.removeWhere(
      (e) =>
          e.meetingId == exception.meetingId &&
          sameDate(e.date, exception.date),
    );
    _exceptions.add(exception);
    _notify();
  }

  @override
  Future<void> clearMeetingException(String meetingId, DateTime date) async {
    _exceptions.removeWhere(
      (e) => e.meetingId == meetingId && sameDate(e.date, date),
    );
    _notify();
  }

  @override
  Future<void> setRsvp(Rsvp rsvp) async {
    _rsvps.removeWhere(
      (r) =>
          r.meetingId == rsvp.meetingId &&
          r.userId == rsvp.userId &&
          sameDate(r.date, rsvp.date),
    );
    _rsvps.add(rsvp);
    _notify();
  }

  @override
  Future<void> addAvailability({
    required String userId,
    required int weekday,
    required TimeRange range,
  }) async {
    if (weekday < 1 || weekday > 7) {
      throw ArgumentError.value(weekday, 'weekday', 'deve ser de 1 a 7');
    }
    _availability.add(
      Availability(
        id: _id('av'),
        userId: userId,
        weekday: weekday,
        range: range,
      ),
    );
    _notify();
  }

  @override
  Future<void> removeAvailability(String availabilityId) async {
    _availability.removeWhere((a) => a.id == availabilityId);
    _notify();
  }
}
