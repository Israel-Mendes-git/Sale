import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/calendar.dart';
import '../domain/games.dart';
import '../domain/models.dart';
import 'repository.dart';

/// O mesmo [SaleRepository], agora sobre o Supabase.
///
/// Lê por consulta e escreve pelas ações do banco (as funções
/// `security definer` da migração), que conferem quem está pedindo. O tempo
/// real serve só de aviso: quando uma tabela muda, cada stream aberto relê o
/// que mostra. Para um grupo de amigos isso é mais simples e menos sujeito a
/// erro do que remontar o estado evento a evento.
class SupabaseRepository implements SaleRepository {
  SupabaseRepository({
    required SupabaseClient client,
    required this.userId,
    DateTime Function()? clock,
  }) : _db = client,
       _clock = clock ?? DateTime.now;

  /// Quem está logado. O banco confere de novo, pelo token de cada pedido.
  final String userId;

  final SupabaseClient _db;

  /// Só os horários marcados pelo app usam o relógio; o resto vem do banco.
  // ignore: unused_field
  final DateTime Function() _clock;

  final _changes = StreamController<void>.broadcast();

  /// Tabelas que o app escuta. Todas estão na publicação do tempo real.
  static const _tables = [
    'profiles',
    'quick_replies',
    'conversations',
    'conversation_members',
    'group_members',
    'messages',
    'chamados',
    'chamado_targets',
    'chamado_vetoes',
    'games',
    'game_owners',
    'weekly_meetings',
    'meeting_exceptions',
    'meeting_rsvps',
    'availability',
  ];

  /// Mudança nestas obriga a recarregar o que as telas leem sem esperar
  /// ([profiles], [quickRepliesFor]) e o grupo atual.
  static const _cached = {'profiles', 'quick_replies', 'group_members'};

  static const _chamadoFields =
      'id, conversation_id, author_id, game_id, game_name, drawn, note, '
      'scheduled_for, status, created_at, '
      'chamado_targets(user_id, reply_emoji, reply_label, reply_kind, '
      'eta_minutes, responded_at), '
      'chamado_vetoes(user_id, game_id)';

  static const _replyFields =
      'id, owner_id, emoji, label, kind, eta_minutes, asks_eta';

  var _profiles = <Profile>[];
  var _quickReplies = <QuickReply>[];

  /// O grupo da pessoa. O app usa um só; o banco já aceita vários.
  String? _groupId;

  RealtimeChannel? _channel;
  Timer? _debounce;
  var _reloadCache = false;
  Future<void>? _loading;

  /// Carrega o que as telas pedem de pronto e liga o tempo real. Pode ser
  /// chamado quantas vezes for: só acontece uma — e, se falhar (sem rede,
  /// por exemplo), a próxima chamada tenta de novo.
  Future<void> load() async {
    final running = _loading;
    if (running != null) return running;
    final attempt = _start();
    _loading = attempt;
    try {
      await attempt;
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  Future<void> _start() async {
    await _reload();
    var channel = _db.channel('sale');
    for (final table in _tables) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => _changed(cache: _cached.contains(table)),
      );
    }
    _channel = channel..subscribe();
  }

  void dispose() {
    _debounce?.cancel();
    final channel = _channel;
    if (channel != null) unawaited(_db.removeChannel(channel));
    unawaited(_changes.close());
  }

  /// Avisa os streams. Espera um instante porque uma ação só (disparar um
  /// Chamado, por exemplo) mexe em várias tabelas de uma vez.
  void _changed({bool cache = false}) {
    _reloadCache = _reloadCache || cache;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () async {
      if (_reloadCache) {
        _reloadCache = false;
        await _reload();
      }
      if (!_changes.isClosed) _changes.add(null);
    });
  }

  Future<void> _reload() async {
    final profiles = await _db
        .from('profiles')
        .select('id, name, named, emoji, color');
    final replies = await _db
        .from('quick_replies')
        .select(_replyFields)
        .order('created_at', ascending: true);
    final groups = await _db
        .from('group_members')
        .select('group_id')
        .eq('user_id', userId)
        .order('joined_at', ascending: true)
        .limit(1);
    _profiles = [for (final row in profiles) _profile(row)];
    _quickReplies = [for (final row in replies) _reply(row)];
    _groupId = groups.isEmpty ? null : groups.first['group_id'] as String;
  }

  /// Emite o valor agora e de novo a cada aviso de mudança. Se chegar aviso
  /// com uma leitura em andamento, relê depois dela, uma vez só.
  Stream<T> _watch<T>(Future<T> Function() read) {
    late StreamController<T> controller;
    StreamSubscription<void>? sub;
    var reading = false;
    var again = false;

    Future<void> emit() async {
      if (reading) {
        again = true;
        return;
      }
      reading = true;
      try {
        do {
          again = false;
          final value = await read();
          if (!controller.isClosed) controller.add(value);
        } while (again);
      } catch (error, stack) {
        if (!controller.isClosed) controller.addError(error, stack);
      } finally {
        reading = false;
      }
    }

    controller = StreamController<T>(
      onListen: () {
        sub = _changes.stream.listen((_) => emit());
        emit();
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
  }

  /// As ações do banco explicam o problema em português; a tela mostra a
  /// mensagem como veio.
  Future<T> _call<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (e) {
      throw StateError(e.message);
    }
  }

  // -------------------------------------------------------------------
  // Leitura direta (as telas pedem sem esperar)

  @override
  List<Profile> get profiles => List.unmodifiable(_profiles);

  @override
  Profile profile(String id) => _profiles.firstWhere(
    (p) => p.id == id,
    // Quem saiu do grupo ainda aparece nas mensagens antigas.
    orElse: () =>
        Profile(id: id, name: 'Alguém', emoji: '👤', color: 0xFF9E9E9E),
  );

  @override
  List<QuickReply> quickRepliesFor(String userId) => [
    for (final r in _quickReplies)
      if (r.ownerId == null || r.ownerId == userId) r,
  ];

  // -------------------------------------------------------------------
  // Grupos

  @override
  Stream<List<Group>> watchGroups(String userId) => _watch(() async {
    final rows = await _db
        .from('groups')
        .select('id, name, invite_code')
        .order('created_at', ascending: true);
    return [
      for (final row in rows)
        Group(
          id: row['id'] as String,
          name: row['name'] as String,
          inviteCode: row['invite_code'] as String,
        ),
    ];
  });

  @override
  Future<void> createGroup(String name) => _call(() async {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > maxGroupNameLength) {
      throw ArgumentError.value(
        name,
        'name',
        'precisa ter de 1 a $maxGroupNameLength letras',
      );
    }
    await _db.rpc('create_group', params: {'p_name': clean});
    await _reload();
    _changed();
  });

  @override
  Future<void> joinGroup(String inviteCode) => _call(() async {
    final clean = inviteCode.trim();
    if (clean.isEmpty) {
      throw ArgumentError.value(inviteCode, 'inviteCode', 'está vazio');
    }
    await _db.rpc('join_group', params: {'p_code': clean});
    await _reload();
    _changed();
  });

  // -------------------------------------------------------------------
  // Conversas e mensagens

  @override
  Stream<List<Conversation>> watchConversations(String userId) =>
      _watch(() async {
        final rows = await _db
            .from('conversations')
            .select('id, kind, name, conversation_members(user_id)');
        // A conversa com mensagem mais recente fica em cima. As datas vêm
        // do banco em UTC, então comparar o texto já ordena.
        final recent = await _db
            .from('messages')
            .select('conversation_id, created_at')
            .order('created_at', ascending: false)
            .limit(300);
        final last = <String, String>{};
        for (final m in recent) {
          last.putIfAbsent(
            m['conversation_id'] as String,
            () => m['created_at'] as String,
          );
        }
        return [for (final row in rows) _conversation(row)]
          ..sort((a, b) => (last[b.id] ?? '').compareTo(last[a.id] ?? ''));
      });

  @override
  Stream<List<Message>> watchMessages(String conversationId) =>
      _watch(() async {
        final rows = await _db
            .from('messages')
            .select(
              'id, conversation_id, author_id, body, chamado_id, created_at',
            )
            .eq('conversation_id', conversationId)
            .order('created_at', ascending: true);
        return [for (final row in rows) _message(row)];
      });

  @override
  Future<void> sendText({
    required String conversationId,
    required String authorId,
    required String text,
  }) => _call(() async {
    await _db.from('messages').insert({
      'conversation_id': conversationId,
      'body': text,
    });
    _changed();
  });

  // -------------------------------------------------------------------
  // Chamados

  @override
  Stream<Chamado> watchChamado(String chamadoId) => _watch(() async {
    final row = await _db
        .from('chamados')
        .select(_chamadoFields)
        .eq('id', chamadoId)
        .single();
    return _chamado(row);
  });

  @override
  Stream<List<Chamado>> watchPendingFor(String userId) => _watch(() async {
    final rows = await _db
        .from('chamados')
        .select(_chamadoFields)
        .eq('status', 'open');
    final pending = <Chamado>[];
    for (final row in rows) {
      final chamado = _chamado(row);
      if (chamado.awaits(userId)) pending.add(chamado);
    }
    return pending;
  });

  @override
  Future<Chamado> sendChamado({
    required String conversationId,
    required String authorId,
    required List<String> targetIds,
    String? gameId,
    bool drawGame = false,
    String? note,
    DateTime? scheduledFor,
  }) => _call(() async {
    final id = await _db.rpc(
      'send_chamado',
      params: {
        'p_conversation': conversationId,
        'p_targets': targetIds,
        'p_game': gameId,
        'p_draw': drawGame,
        'p_note': note,
        'p_scheduled_for': scheduledFor?.toUtc().toIso8601String(),
      },
    ) as String;
    _changed();
    final row = await _db
        .from('chamados')
        .select(_chamadoFields)
        .eq('id', id)
        .single();
    return _chamado(row);
  });

  @override
  Future<void> vetoGame({required String chamadoId, required String userId}) =>
      _call(() async {
        await _db.rpc('veto_game', params: {'p_chamado': chamadoId});
        _changed();
      });

  @override
  Future<void> respond({
    required String chamadoId,
    required String userId,
    required QuickReply reply,
    int? etaMinutes,
  }) => _call(() async {
    await _db.rpc(
      'respond_chamado',
      params: {
        'p_chamado': chamadoId,
        'p_reply': reply.id,
        'p_eta': etaMinutes,
      },
    );
    _changed();
  });

  @override
  Future<void> closeChamado(String chamadoId) => _call(() async {
    await _db.rpc('close_chamado', params: {'p_chamado': chamadoId});
    _changed();
  });

  // -------------------------------------------------------------------
  // Perfil

  @override
  Future<void> renameProfile(String userId, String name) => _call(() async {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > maxNameLength) {
      throw ArgumentError.value(
        name,
        'name',
        'precisa ter de 1 a $maxNameLength letras',
      );
    }
    await _db
        .from('profiles')
        .update({'name': clean, 'named': true})
        .eq('id', userId);
    await _reload();
    _changed();
  });

  @override
  Future<QuickReply> addQuickReply({
    required String ownerId,
    required String emoji,
    required String label,
    required ReplyKind kind,
  }) => _call(() async {
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
    final row = await _db
        .from('quick_replies')
        .insert({
          'owner_id': ownerId,
          'emoji': emoji.trim().isEmpty ? '💬' : emoji.trim(),
          'label': clean,
          'kind': kind.name,
        })
        .select(_replyFields)
        .single();
    await _reload();
    _changed();
    return _reply(row);
  });

  @override
  Future<void> removeQuickReply(String replyId) => _call(() async {
    final reply = _quickReplies.where((r) => r.id == replyId).firstOrNull;
    if (reply != null && reply.ownerId == null) {
      throw StateError('Resposta comum a todos não pode ser removida.');
    }
    await _db.from('quick_replies').delete().eq('id', replyId);
    await _reload();
    _changed();
  });

  // -------------------------------------------------------------------
  // Jogos

  @override
  Stream<GameLibrary> watchGames() => _watch(() async {
    final rows = await _db
        .from('games')
        .select('id, name, min_players, max_players, game_owners(user_id)')
        .order('name', ascending: true);
    return GameLibrary(
      games: [for (final row in rows) _game(row)],
      owners: {
        for (final row in rows)
          row['id'] as String: {
            for (final owner in row['game_owners'] as List)
              (owner as Map)['user_id'] as String,
          },
      },
    );
  });

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
    final group = _groupId;
    if (group == null) {
      throw StateError('Entre num grupo antes de cadastrar jogos.');
    }
    try {
      final row = await _db
          .from('games')
          .insert({
            'group_id': group,
            'name': clean,
            'min_players': minPlayers,
            'max_players': maxPlayers,
          })
          .select('id, name, min_players, max_players')
          .single();
      _changed();
      return _game(row);
    } on PostgrestException catch (e) {
      // 23505 = o índice que impede dois jogos com o mesmo nome no grupo.
      if (e.code == '23505') {
        throw StateError('"$clean" já está na biblioteca.');
      }
      throw StateError(e.message);
    }
  }

  @override
  Future<void> setOwnsGame({
    required String gameId,
    required String userId,
    required bool owns,
  }) => _call(() async {
    if (owns) {
      await _db.from('game_owners').upsert({
        'game_id': gameId,
        'user_id': userId,
      }, onConflict: 'game_id,user_id');
    } else {
      await _db
          .from('game_owners')
          .delete()
          .eq('game_id', gameId)
          .eq('user_id', userId);
    }
    _changed();
  });

  @override
  Future<void> removeGame(String gameId) => _call(() async {
    await _db.from('games').delete().eq('id', gameId);
    _changed();
  });

  // -------------------------------------------------------------------
  // Calendário

  @override
  Stream<CalendarData> watchCalendar(String userId) => _watch(() async {
    final meetings = await _db
        .from('weekly_meetings')
        .select('id, conversation_id, weekday, minute, game');
    final exceptions = await _db
        .from('meeting_exceptions')
        .select('meeting_id, date, skipped, minute');
    final rsvps = await _db
        .from('meeting_rsvps')
        .select('meeting_id, date, user_id, status, reason');
    final availability = await _db
        .from('availability')
        .select('id, user_id, weekday, start_minute, end_minute');
    final chamados = await _db
        .from('chamados')
        .select(_chamadoFields)
        .eq('status', 'open');

    final scheduled = <Chamado>[];
    for (final row in chamados) {
      final chamado = _chamado(row);
      if (chamado.scheduledFor != null &&
          chamado.participants.contains(userId)) {
        scheduled.add(chamado);
      }
    }
    return CalendarData(
      meetings: [for (final row in meetings) _meeting(row)],
      exceptions: [for (final row in exceptions) _exception(row)],
      rsvps: [for (final row in rsvps) _rsvp(row)],
      availability: [for (final row in availability) _availability(row)],
      scheduledChamados: scheduled,
    );
  });

  @override
  Future<void> saveMeeting({
    required String conversationId,
    required int weekday,
    required int minute,
    String? game,
  }) => _call(() async {
    final existing = await _db
        .from('weekly_meetings')
        .select('id, weekday')
        .eq('conversation_id', conversationId)
        .maybeSingle();
    // Exceções e confirmações valem para o dia antigo; mudou o dia, caem.
    // As confirmações dos outros ficam no banco (cada um só apaga a sua),
    // mas somem da tela por não casarem mais com o dia do encontro.
    if (existing != null && existing['weekday'] != weekday) {
      final id = existing['id'] as String;
      await _db.from('meeting_exceptions').delete().eq('meeting_id', id);
      await _db
          .from('meeting_rsvps')
          .delete()
          .eq('meeting_id', id)
          .eq('user_id', userId);
    }
    await _db.from('weekly_meetings').upsert({
      'conversation_id': conversationId,
      'weekday': weekday,
      'minute': minute,
      'game': game,
    }, onConflict: 'conversation_id');
    _changed();
  });

  @override
  Future<void> deleteMeeting(String meetingId) => _call(() async {
    await _db.from('weekly_meetings').delete().eq('id', meetingId);
    _changed();
  });

  @override
  Future<void> setMeetingException(MeetingException exception) =>
      _call(() async {
        await _db.from('meeting_exceptions').upsert({
          'meeting_id': exception.meetingId,
          'date': _day(exception.date),
          'skipped': exception.skipped,
          'minute': exception.minute,
        }, onConflict: 'meeting_id,date');
        _changed();
      });

  @override
  Future<void> clearMeetingException(String meetingId, DateTime date) =>
      _call(() async {
        await _db
            .from('meeting_exceptions')
            .delete()
            .eq('meeting_id', meetingId)
            .eq('date', _day(date));
        _changed();
      });

  @override
  Future<void> setRsvp(Rsvp rsvp) => _call(() async {
    await _db.from('meeting_rsvps').upsert({
      'meeting_id': rsvp.meetingId,
      'date': _day(rsvp.date),
      'user_id': rsvp.userId,
      'status': _rsvpName(rsvp.status),
      'reason': rsvp.reason,
    }, onConflict: 'meeting_id,date,user_id');
    _changed();
  });

  @override
  Future<void> addAvailability({
    required String userId,
    required int weekday,
    required TimeRange range,
  }) => _call(() async {
    if (weekday < 1 || weekday > 7) {
      throw ArgumentError.value(weekday, 'weekday', 'deve ser de 1 a 7');
    }
    await _db.from('availability').insert({
      'user_id': userId,
      'weekday': weekday,
      'start_minute': range.start,
      'end_minute': range.end,
    });
    _changed();
  });

  @override
  Future<void> removeAvailability(String availabilityId) => _call(() async {
    await _db.from('availability').delete().eq('id', availabilityId);
    _changed();
  });

  // -------------------------------------------------------------------
  // Linha do banco → modelo

  Profile _profile(Map<String, dynamic> row) => Profile(
    id: row['id'] as String,
    name: row['name'] as String,
    named: row['named'] as bool? ?? false,
    emoji: row['emoji'] as String? ?? '🎮',
    // O Postgres guarda a cor como inteiro com sinal; o Flutter quer
    // 0xAARRGGBB.
    color: (row['color'] as int) & 0xFFFFFFFF,
  );

  QuickReply _reply(Map<String, dynamic> row) => QuickReply(
    id: row['id'] as String,
    ownerId: row['owner_id'] as String?,
    emoji: row['emoji'] as String,
    label: row['label'] as String,
    kind: _replyKind(row['kind'] as String?),
    asksEta: row['asks_eta'] as bool? ?? false,
    etaMinutes: row['eta_minutes'] as int?,
  );

  Conversation _conversation(Map<String, dynamic> row) => Conversation(
    id: row['id'] as String,
    kind: row['kind'] == 'group'
        ? ConversationKind.group
        : ConversationKind.direct,
    name: row['name'] as String?,
    memberIds: [
      for (final member in row['conversation_members'] as List)
        (member as Map)['user_id'] as String,
    ],
  );

  Message _message(Map<String, dynamic> row) => Message(
    id: row['id'] as String,
    conversationId: row['conversation_id'] as String,
    authorId: row['author_id'] as String,
    createdAt: _moment(row['created_at'])!,
    text: row['body'] as String?,
    chamadoId: row['chamado_id'] as String?,
  );

  Chamado _chamado(Map<String, dynamic> row) {
    final targets = (row['chamado_targets'] as List)
        .cast<Map<String, dynamic>>();
    final vetoes = (row['chamado_vetoes'] as List).cast<Map<String, dynamic>>();
    return Chamado(
      id: row['id'] as String,
      conversationId: row['conversation_id'] as String,
      authorId: row['author_id'] as String,
      createdAt: _moment(row['created_at'])!,
      game: row['game_name'] as String?,
      gameId: row['game_id'] as String?,
      drawn: row['drawn'] as bool? ?? false,
      note: row['note'] as String?,
      scheduledFor: _moment(row['scheduled_for']),
      status: _status(row['status'] as String?),
      vetoes: {
        for (final veto in vetoes)
          // O jogo pode ter saído da biblioteca; o veto continua valendo.
          veto['user_id'] as String: veto['game_id'] as String? ?? '',
      },
      responses: {
        for (final target in targets)
          target['user_id'] as String: _response(target),
      },
    );
  }

  ChamadoResponse? _response(Map<String, dynamic> target) {
    final at = _moment(target['responded_at']);
    if (at == null) return null;
    final eta = target['eta_minutes'] as int?;
    return ChamadoResponse(
      reply: QuickReply(
        // O Chamado guarda uma cópia da resposta: ela sobrevive mesmo que a
        // pessoa apague a resposta do perfil depois.
        id: '',
        emoji: target['reply_emoji'] as String? ?? '💬',
        label: target['reply_label'] as String? ?? '',
        kind: _replyKind(target['reply_kind'] as String?),
        etaMinutes: eta,
      ),
      respondedAt: at,
      etaMinutes: eta,
    );
  }

  Game _game(Map<String, dynamic> row) => Game(
    id: row['id'] as String,
    name: row['name'] as String,
    minPlayers: row['min_players'] as int,
    maxPlayers: row['max_players'] as int,
  );

  WeeklyMeeting _meeting(Map<String, dynamic> row) => WeeklyMeeting(
    id: row['id'] as String,
    conversationId: row['conversation_id'] as String,
    weekday: row['weekday'] as int,
    minute: row['minute'] as int,
    game: row['game'] as String?,
  );

  MeetingException _exception(Map<String, dynamic> row) => MeetingException(
    meetingId: row['meeting_id'] as String,
    date: DateTime.parse(row['date'] as String),
    skipped: row['skipped'] as bool? ?? false,
    minute: row['minute'] as int?,
  );

  Rsvp _rsvp(Map<String, dynamic> row) => Rsvp(
    meetingId: row['meeting_id'] as String,
    date: DateTime.parse(row['date'] as String),
    userId: row['user_id'] as String,
    status: _rsvpStatus(row['status'] as String?),
    reason: row['reason'] as String?,
  );

  Availability _availability(Map<String, dynamic> row) => Availability(
    id: row['id'] as String,
    userId: row['user_id'] as String,
    weekday: row['weekday'] as int,
    range: TimeRange(row['start_minute'] as int, row['end_minute'] as int),
  );

  DateTime? _moment(Object? value) =>
      value == null ? null : DateTime.parse(value as String).toLocal();

  /// Só o dia, como a coluna `date` do Postgres espera.
  String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  ReplyKind _replyKind(String? value) => switch (value) {
    'yes' => ReplyKind.yes,
    'later' => ReplyKind.later,
    'snooze' => ReplyKind.snooze,
    _ => ReplyKind.no,
  };

  ChamadoStatus _status(String? value) => switch (value) {
    'answered' => ChamadoStatus.answered,
    'closed' => ChamadoStatus.closed,
    _ => ChamadoStatus.open,
  };

  RsvpStatus _rsvpStatus(String? value) => switch (value) {
    'going' => RsvpStatus.going,
    'maybe' => RsvpStatus.maybe,
    _ => RsvpStatus.notGoing,
  };

  String _rsvpName(RsvpStatus status) => switch (status) {
    RsvpStatus.going => 'going',
    RsvpStatus.maybe => 'maybe',
    RsvpStatus.notGoing => 'not_going',
  };
}
