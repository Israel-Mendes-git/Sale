import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import '../domain/calendar.dart';
import '../domain/games.dart';
import '../domain/models.dart';
import '../domain/sounds.dart';
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

  /// Marcas de entregue e lido: conversa -> pessoa -> até onde ela chegou.
  final _receipts = <String, Map<String, Receipt>>{};

  /// A lista de sons: os que vêm no app, que aqui usam o próprio nome de
  /// arquivo como id, mais os que o grupo subir.
  final _sounds = [
    for (final som in builtInSounds.entries)
      Sound(id: som.key, name: som.value, file: som.key),
  ];

  /// Os arquivos dos sons do grupo. Sem servidor eles ficam só na memória.
  final _soundFiles = <String, Uint8List>{};

  /// Os anexos das mensagens, pelo caminho que a mensagem guarda. Sem Storage
  /// eles também ficam só na memória.
  final _attachments = <String, Uint8List>{};
  final _chamados = <String, Chamado>{};
  final _profiles = [...seedProfiles];
  final _quickReplies = [...seedQuickReplies];
  final _meetings = [...seedMeetings];
  final _exceptions = <MeetingException>[];
  final _rsvps = <Rsvp>[];
  final _availability = [...seedAvailability];

  /// Ocorrências do encontro fixo já disparadas ("encontro@data").
  final _firedMeetings = <String>{};

  /// Trava contra reentrada: o relógio avisa quem está ouvindo, e quem ouve
  /// lê de novo — o que faria o relógio andar dentro de si mesmo.
  var _clockRunning = false;
  var _nextId = 0;

  String _id(String prefix) => '$prefix-${_nextId++}';

  /// Emite o valor atual e depois um novo a cada mudança.
  Stream<T> _watch<T>(T Function() read) {
    StreamSubscription<void>? sub;
    final controller = StreamController<T>();
    controller
      ..onListen = () {
        // Assina antes de emitir para não perder mudança no meio do caminho.
        sub = _changes.stream.listen((_) => controller.add(_fresh(read)));
        controller.add(_fresh(read));
      }
      ..onCancel = () => sub?.cancel();
    return controller.stream;
  }

  /// Antes de cada leitura, o relógio do grupo anda: o Chamado que esperou
  /// demais fecha, o encontro fixo que chegou a hora vira Chamado, o Chamado
  /// calado toca de novo e a soneca acorda quem pediu. No servidor quem faz isso é o cron (ver
  /// docs/CRON.md); aqui, como não há servidor, a conta acontece quando
  /// alguma tela olha.
  T _fresh<T>(T Function() read) {
    _runClock();
    return read();
  }

  void _runClock() {
    if (_clockRunning) return;
    _clockRunning = true;
    try {
      // Primeiro o que fecha, depois o que toca: Chamado que está expirando
      // não insiste com ninguém nem acorda quem pediu soneca.
      final expirou = _expireOld();
      final encontros = _fireDueMeetings();
      // A insistência vem antes da soneca, como no servidor: quem pediu
      // soneca já respondeu, e assim não é chamado duas vezes de uma só vez.
      final insistiu = _nudgeSilent();
      final acordou = _wakeSnoozed();
      if (expirou || encontros || insistiu || acordou) _notify();
    } finally {
      _clockRunning = false;
    }
  }

  /// Fecha os Chamados que ficaram abertos tempo demais. Chamado respondido
  /// fica como está, de registro.
  bool _expireOld() {
    final now = _clock();
    var expired = false;
    for (final chamado in [..._chamados.values]) {
      if (!chamado.isOpen || now.isBefore(chamado.expiresAt)) continue;
      _chamados[chamado.id] = chamado.copyWith(
        status: ChamadoStatus.closed,
        expiredAt: now,
      );
      expired = true;
    }
    return expired;
  }

  /// Dispara os encontros cuja hora chegou, uma vez por data. A janela é a
  /// mesma do servidor: encontro muito atrasado não acorda mais ninguém.
  bool _fireDueMeetings() {
    final now = _clock();
    final today = dateOnly(now);
    var created = false;
    for (final meeting in _meetings) {
      if (today.weekday != meeting.weekday) continue;
      final exception = _exceptions
          .where((e) => e.meetingId == meeting.id && sameDate(e.date, today))
          .firstOrNull;
      if (exception?.skipped ?? false) continue;

      final startsAt = today.add(
        Duration(minutes: exception?.minute ?? meeting.minute),
      );
      if (now.isBefore(startsAt)) continue;
      if (now.difference(startsAt) >= fireWindow) continue;
      if (!_firedMeetings.add('${meeting.id}@${dateOnly(today)}')) continue;

      final conversation = seedConversations.firstWhere(
        (c) => c.id == meeting.conversationId,
      );
      // Sem ninguém chamando, todo mundo da conversa é chamado.
      final chamado = Chamado(
        id: _id('chamado'),
        conversationId: conversation.id,
        authorId: conversation.memberIds.first,
        createdAt: now,
        game: meeting.game,
        automatic: true,
        responses: {for (final id in conversation.memberIds) id: null},
      );
      _chamados[chamado.id] = chamado;
      _messages.add(
        Message(
          id: _id('msg'),
          conversationId: conversation.id,
          authorId: chamado.authorId,
          createdAt: now,
          chamadoId: chamado.id,
        ),
      );
      created = true;
    }
    return created;
  }

  /// A insistência: Chamado que ficou sem resposta toca de novo, uma vez só,
  /// para quem ficou calado. Fora da janela não toca mais — o servidor
  /// também não insiste por um Chamado cuja hora já passou.
  bool _nudgeSilent() {
    final now = _clock();
    var nudged = false;
    for (final chamado in [..._chamados.values]) {
      if (!chamado.isOpen || chamado.nudgedAt != null) continue;
      if (chamado.silent.isEmpty) continue;
      final due = (chamado.scheduledFor ?? chamado.createdAt).add(nudgeDelay);
      if (now.isBefore(due) || now.difference(due) >= fireWindow) continue;
      _chamados[chamado.id] = chamado.copyWith(nudgedAt: now);
      nudged = true;
    }
    return nudged;
  }

  /// A soneca: na hora pedida, quem respondeu "me chama daqui a pouco" volta
  /// para a fila de quem não respondeu, e o Chamado torna a esperar por ela.
  /// No servidor isso sai com um push novo; aqui o Chamado só reaparece.
  bool _wakeSnoozed() {
    final now = _clock();
    var changed = false;
    for (final chamado in [..._chamados.values]) {
      final responses = Map.of(chamado.responses);
      var woke = false;
      var dropped = false;
      for (final entry in chamado.responses.entries) {
        final until = entry.value?.snoozedUntil;
        if (until == null || now.isBefore(until)) continue;
        // Encerrado ou atrasado demais: a soneca cai sem acordar ninguém, e
        // o 💤 continua no card.
        if (chamado.status == ChamadoStatus.closed ||
            now.difference(until) >= fireWindow) {
          responses[entry.key] = entry.value!.withoutSnooze();
          dropped = true;
        } else {
          responses[entry.key] = null;
          woke = true;
        }
      }
      if (!woke && !dropped) continue;
      _chamados[chamado.id] = chamado.copyWith(
        responses: responses,
        // O Chamado tinha todas as respostas; agora espera de novo por uma.
        status: woke && chamado.status == ChamadoStatus.answered
            ? ChamadoStatus.open
            : null,
      );
      changed = true;
    }
    return changed;
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
        if (c.memberIds.contains(userId))
          c.withReceipts(_receipts[c.id] ?? const {}),
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
    String? replyTo,
  }) async {
    _messages.add(
      Message(
        id: _id('msg'),
        conversationId: conversationId,
        authorId: authorId,
        createdAt: _clock(),
        text: text,
        replyTo: _citada(conversationId, replyTo),
      ),
    );
    _notify();
  }

  /// A mensagem citada, conferida como no banco: tem de ser da mesma conversa.
  String? _citada(String conversationId, String? replyTo) {
    if (replyTo == null) return null;
    final existe = _messages.any(
      (m) => m.id == replyTo && m.conversationId == conversationId,
    );
    if (!existe) {
      throw ArgumentError.value(replyTo, 'replyTo', 'não é desta conversa');
    }
    return replyTo;
  }

  @override
  Future<void> sendImage({
    required String conversationId,
    required String authorId,
    required Uint8List bytes,
    required String fileName,
    int? width,
    int? height,
    String? caption,
    String? replyTo,
  }) async {
    if (bytes.lengthInBytes > maxImageBytes) {
      throw StateError('A imagem é grande demais para mandar.');
    }
    final dot = fileName.lastIndexOf('.');
    final path =
        '$conversationId/$_nextId${dot == -1 ? '.jpg' : fileName.substring(dot)}';
    _attachments[path] = bytes;
    final legenda = caption?.trim();
    _messages.add(
      Message(
        id: _id('msg'),
        conversationId: conversationId,
        authorId: authorId,
        createdAt: _clock(),
        text: legenda == null || legenda.isEmpty ? null : legenda,
        replyTo: _citada(conversationId, replyTo),
        attachment: Attachment(
          path: path,
          kind: AttachmentKind.image,
          width: width,
          height: height,
        ),
      ),
    );
    _notify();
  }

  @override
  Future<Uint8List> attachmentBytes(String path) async {
    final bytes = _attachments[path];
    if (bytes == null) throw StateError('Anexo sem arquivo neste aparelho.');
    return bytes;
  }

  @override
  Future<void> markDelivered(String userId) async {
    final now = _clock();
    var changed = false;
    for (final conversation in seedConversations) {
      if (!conversation.memberIds.contains(userId)) continue;
      changed = _mark(conversation.id, userId, deliveredUntil: now) || changed;
    }
    if (changed) _notify();
  }

  @override
  Future<void> markRead({
    required String conversationId,
    required String userId,
  }) async {
    final now = _clock();
    // Quem viu também recebeu, senão a mensagem lida ficaria com um tique.
    if (_mark(conversationId, userId, deliveredUntil: now, readUntil: now)) {
      _notify();
    }
  }

  /// Anda com as marcas de uma pessoa numa conversa; devolve se andou. As
  /// datas só vão para a frente, como no banco.
  bool _mark(
    String conversationId,
    String userId, {
    DateTime? deliveredUntil,
    DateTime? readUntil,
  }) {
    final byUser = _receipts.putIfAbsent(conversationId, () => {});
    final old = byUser[userId] ?? const Receipt();
    final receipt = Receipt(
      deliveredUntil: _later(old.deliveredUntil, deliveredUntil),
      readUntil: _later(old.readUntil, readUntil),
    );
    if (receipt.deliveredUntil == old.deliveredUntil &&
        receipt.readUntil == old.readUntil) {
      return false;
    }
    byUser[userId] = receipt;
    return true;
  }

  static DateTime? _later(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return b.isAfter(a) ? b : a;
  }

  @override
  Future<Chamado> sendChamado({
    required String conversationId,
    required String authorId,
    required List<String> targetIds,
    String? soundId,
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
      soundKey: _soundKey(soundId),
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

  // -------------------------------------------------------------------
  // Som do Chamado

  @override
  Stream<List<Sound>> watchSounds() =>
      _watch(() => List<Sound>.unmodifiable(_sounds));

  @override
  Future<Sound> addSound({
    required String name,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > maxSoundNameLength) {
      throw ArgumentError.value(
        name,
        'name',
        'precisa ter de 1 a $maxSoundNameLength letras',
      );
    }
    if (_sounds.any((s) => s.name.toLowerCase() == clean.toLowerCase())) {
      throw StateError('Já existe um som com esse nome.');
    }
    if (bytes.lengthInBytes > maxSoundBytes) {
      throw StateError('O arquivo é grande demais para um toque.');
    }
    final dot = fileName.lastIndexOf('.');
    final sound = Sound(
      id: _id('som'),
      name: clean,
      // Sem servidor não há Storage: o caminho é de mentira, e o que vale é
      // o arquivo guardado na memória.
      file: 'dev/${_sounds.length}${dot == -1 ? '' : fileName.substring(dot)}',
      groupId: 'grupo',
    );
    _sounds.add(sound);
    _soundFiles[sound.id] = bytes;
    _notify();
    return sound;
  }

  @override
  Future<void> removeSound(String soundId) async {
    final sound = _sounds.where((s) => s.id == soundId).firstOrNull;
    if (sound == null) return;
    if (sound.builtIn) {
      throw StateError('Som que vem no app não sai da lista.');
    }
    _sounds.remove(sound);
    _soundFiles.remove(soundId);
    // Quem o tinha como padrão volta ao som da marca, como no banco.
    for (var i = 0; i < _profiles.length; i++) {
      if (_profiles[i].soundId == soundId) {
        _profiles[i] = _profiles[i].copyWith(clearSound: true);
      }
    }
    _notify();
  }

  @override
  Future<Uint8List> soundBytes(Sound sound) async {
    final bytes = _soundFiles[sound.id];
    if (bytes == null) throw StateError('Som sem arquivo neste aparelho.');
    return bytes;
  }

  @override
  Future<void> setProfileSound(String userId, String? soundId) async {
    if (soundId != null && !_sounds.any((s) => s.id == soundId)) {
      throw ArgumentError.value(soundId, 'soundId', 'não está na lista');
    }
    final i = _profiles.indexWhere((p) => p.id == userId);
    _profiles[i] = _profiles[i].copyWith(
      soundId: soundId,
      clearSound: soundId == null,
    );
    _notify();
  }

  /// A chave com que o Chamado toca o som escolhido, como a do banco.
  String? _soundKey(String? soundId) {
    if (soundId == null) return null;
    final sound = _sounds.where((s) => s.id == soundId).firstOrNull;
    if (sound == null) {
      throw ArgumentError.value(soundId, 'soundId', 'não está na lista');
    }
    return sound.key;
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

    final now = _clock();
    final eta = etaMinutes ?? reply.etaMinutes;
    final responses = Map.of(chamado.responses)
      ..[userId] = ChamadoResponse(
        reply: reply,
        respondedAt: now,
        etaMinutes: eta,
        // A soneca é a única resposta que pede o Chamado de volta. Quem
        // responde de novo perde a soneca antiga, e é isso que esta troca faz.
        snoozedUntil: reply.kind == ReplyKind.snooze
            ? now.add(Duration(minutes: eta ?? defaultSnoozeMinutes))
            : null,
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
  Future<void> markArrived({
    required String chamadoId,
    required String userId,
  }) async {
    final chamado = _chamados[chamadoId]!;
    if (!chamado.awaitsArrival(userId)) {
      throw StateError('$userId não tem chegada para marcar em $chamadoId.');
    }
    final responses = Map.of(chamado.responses)
      ..[userId] = chamado.responses[userId]!.arriving(_clock());
    _chamados[chamadoId] = chamado.copyWith(responses: responses);
    _notify();
  }

  @override
  Stream<List<Chamado>> watchArrivalPending(String userId) => _watch(
    () => [
      for (final c in _chamados.values)
        if (c.awaitsArrival(userId)) c,
    ],
  );

  @override
  Stream<List<Chamado>> watchHistory(String userId) => _watch(() {
    final mine = {
      for (final c in seedConversations)
        if (c.memberIds.contains(userId)) c.id,
    };
    final history = [
      for (final c in _chamados.values)
        if (mine.contains(c.conversationId)) c,
    ];
    history.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return history;
  });

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

  // Sem servidor não há push: guardar o aparelho não levaria a lugar nenhum.
  @override
  Future<void> saveDeviceToken(String token) async {}

  @override
  Future<void> removeDeviceToken(String token) async {}
}
