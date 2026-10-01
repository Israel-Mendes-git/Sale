import 'dart:async';
import 'dart:math';

import '../domain/calendar.dart';
import '../domain/games.dart';
import '../domain/models.dart';
import 'repository.dart';
import 'seed.dart';

/// Backend falso, em memória, para desenvolver as telas sem servidor.
class MemoryRepository implements SaleRepository {
  MemoryRepository({DateTime Function()? clock, Random? random})
    : _clock = clock ?? DateTime.now,
      _random = random ?? Random();

  final DateTime Function() _clock;
  final Random _random;
  final _games = [...seedGames];
  final _gameOwners = {
    for (final e in seedGameOwners.entries) e.key: {...e.value},
  };
  final _changes = StreamController<void>.broadcast();
  final _messages = <Message>[];
  final _chamados = <String, Chamado>{};
  final _profiles = [...seedProfiles];
  final _quickReplies = [...seedQuickReplies];
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
  List<Profile> get profiles => List.unmodifiable(_profiles);

  @override
  Profile profile(String id) => _profiles.firstWhere((p) => p.id == id);

  @override
  List<QuickReply> quickRepliesFor(String userId) => [
    for (final r in _quickReplies)
      if (r.ownerId == null || r.ownerId == userId) r,
  ];

  @override
  Stream<List<Group>> watchGroups(String userId) => _watch(() => [seedGroup]);

  @override
  Future<void> createGroup(String name) async =>
      throw UnsupportedError('Grupos só com o Supabase ligado.');

  @override
  Future<void> joinGroup(String inviteCode) async =>
      throw UnsupportedError('Grupos só com o Supabase ligado.');

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
    String? gameId,
    bool drawGame = false,
    String? note,
    DateTime? scheduledFor,
  }) async {
    if (targetIds.isEmpty) {
      throw ArgumentError('Chamado sem ninguém para chamar.');
    }
    if (gameId != null && drawGame) {
      throw ArgumentError('Escolha um jogo ou o sorteio, não os dois.');
    }
    Game? game;
    if (gameId != null) {
      game = _library.byId(gameId);
      if (game == null) throw ArgumentError.value(gameId, 'gameId');
    } else if (drawGame) {
      game = _draw(_library.playableBy({authorId, ...targetIds}));
      if (game == null) {
        throw StateError('Nenhum jogo em comum para sortear.');
      }
    }
    final now = _clock();
    final chamado = Chamado(
      id: _id('chamado'),
      conversationId: conversationId,
      authorId: authorId,
      createdAt: now,
      game: game?.name,
      gameId: game?.id,
      drawn: drawGame,
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

  GameLibrary get _library => GameLibrary(
    games: List.unmodifiable(_games),
    owners: {
      for (final e in _gameOwners.entries) e.key: Set.unmodifiable(e.value),
    },
  );

  Game? _draw(List<Game> options, {Set<String> excluded = const {}}) =>
      drawGame(options, _random, excluded: excluded);

  @override
  Future<void> vetoGame({
    required String chamadoId,
    required String userId,
  }) async {
    final chamado = _chamados[chamadoId]!;
    if (!chamado.canVeto(userId)) {
      throw StateError('$userId não pode vetar em $chamadoId.');
    }
    final vetoes = {...chamado.vetoes, userId: chamado.gameId!};
    final next = _draw(
      _library.playableBy(chamado.participants),
      excluded: vetoes.values.toSet(),
    );
    _chamados[chamadoId] = chamado.withRedraw(
      gameId: next?.id,
      game: next?.name,
      vetoes: vetoes,
    );
    _notify();
  }

  @override
  Stream<GameLibrary> watchGames() => _watch(() => _library);

  @override
  Future<Game> addGame({
    required String name,
    required int minPlayers,
    required int maxPlayers,
    required String addedBy,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > maxGameNameLength) {
      throw ArgumentError.value(
        name,
        'name',
        'de 1 a $maxGameNameLength letras',
      );
    }
    if (minPlayers < 1 ||
        maxPlayers > maxPlayersLimit ||
        minPlayers > maxPlayers) {
      throw ArgumentError(
        'Jogadores de $minPlayers a $maxPlayers não faz sentido.',
      );
    }
    if (_games.any((g) => g.name.toLowerCase() == clean.toLowerCase())) {
      throw StateError('"$clean" já está na biblioteca.');
    }
    final game = Game(
      id: _id('jogo'),
      name: clean,
      minPlayers: minPlayers,
      maxPlayers: maxPlayers,
    );
    _games.add(game);
    _gameOwners[game.id] = {addedBy};
    _notify();
    return game;
  }

  @override
  Future<void> setOwnsGame({
    required String gameId,
    required String userId,
    required bool owns,
  }) async {
    final owners = _gameOwners.putIfAbsent(gameId, () => {});
    owns ? owners.add(userId) : owners.remove(userId);
    _notify();
  }

  @override
  Future<void> removeGame(String gameId) async {
    _games.removeWhere((g) => g.id == gameId);
    _gameOwners.remove(gameId);
    _notify();
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
  Future<void> renameProfile(String userId, String name) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > maxNameLength) {
      throw ArgumentError.value(
        name,
        'name',
        'precisa ter de 1 a $maxNameLength letras',
      );
    }
    final i = _profiles.indexWhere((p) => p.id == userId);
    _profiles[i] = _profiles[i].copyWith(name: clean, named: true);
    _notify();
  }

  @override
  Future<QuickReply> addQuickReply({
    required String ownerId,
    required String icon,
    required String label,
    required ReplyKind kind,
  }) async {
    final clean = label.trim();
    if (clean.isEmpty || clean.length > maxReplyLength) {
      throw ArgumentError.value(
        label,
        'label',
        'precisa ter de 1 a $maxReplyLength letras',
      );
    }
    if (kind == ReplyKind.snooze) {
      throw ArgumentError.value(kind, 'kind', '"me chama depois" já existe');
    }
    final reply = QuickReply(
      id: _id('resposta'),
      ownerId: ownerId,
      icon: icon.trim().isEmpty ? 'balao' : icon.trim(),
      label: clean,
      kind: kind,
      asksEta: kind == ReplyKind.later,
    );
    _quickReplies.add(reply);
    _notify();
    return reply;
  }

  @override
  Future<void> removeQuickReply(String replyId) async {
    final reply = _quickReplies.firstWhere((r) => r.id == replyId);
    if (reply.ownerId == null) {
      throw StateError('Resposta comum a todos não pode ser removida.');
    }
    _quickReplies.remove(reply);
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
