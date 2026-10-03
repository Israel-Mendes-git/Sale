import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/domain/calendar.dart';
import 'package:sale/domain/models.dart';

void main() {
  late MemoryRepository repo;
  var now = DateTime(2026, 10, 1, 19);

  late QuickReply jantando;
  late QuickReply sair;

  /// Resposta comum a todos, pelo id.
  QuickReply reply(String id) =>
      repo.quickRepliesFor('p2').firstWhere((r) => r.id == id);

  setUp(() async {
    now = DateTime(2026, 10, 1, 19);
    repo = MemoryRepository(clock: () => now);
    jantando = await repo.addQuickReply(
      ownerId: 'p2',
      icon: 'comida',
      label: 'Tô jantando',
      kind: ReplyKind.later,
    );
    sair = await repo.addQuickReply(
      ownerId: 'p3',
      icon: 'rua',
      label: 'Tenho que sair',
      kind: ReplyKind.no,
    );
  });

  test('respostas rápidas = comuns + as da própria pessoa', () {
    final ids = repo.quickRepliesFor('p2').map((r) => r.id).toSet();
    expect(ids, containsAll(['bora', 'hojenao', jantando.id]));
    expect(ids, isNot(contains(sair.id)));
    expect(repo.quickRepliesFor('p1').where((r) => r.ownerId != null), isEmpty);
  });

  group('perfil', () {
    test('troca o nome e marca que a pessoa escolheu', () async {
      expect(repo.profile('p2').named, isFalse);
      await repo.renameProfile('p2', '  Duda ');
      expect(repo.profile('p2').name, 'Duda');
      expect(repo.profile('p2').named, isTrue);
    });

    test('recusa nome vazio ou comprido demais', () {
      expect(() => repo.renameProfile('p2', '   '), throwsArgumentError);
      expect(() => repo.renameProfile('p2', 'x' * 25), throwsArgumentError);
      expect(repo.profile('p2').name, 'Pessoa 2');
    });

    test('"vou, mas depois" pergunta o tempo; sem ícone vira balão', () async {
      final r = await repo.addQuickReply(
        ownerId: 'p1',
        icon: ' ',
        label: 'No trabalho',
        kind: ReplyKind.later,
      );
      expect(r.asksEta, isTrue);
      expect(r.icon, 'balao');
      expect(jantando.asksEta, isTrue);
      expect(sair.asksEta, isFalse);
    });

    test('recusa resposta vazia e o tipo "me chama depois"', () {
      expect(
        () => repo.addQuickReply(
          ownerId: 'p1',
          icon: 'balao',
          label: ' ',
          kind: ReplyKind.no,
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.addQuickReply(
          ownerId: 'p1',
          icon: 'balao',
          label: 'Depois',
          kind: ReplyKind.snooze,
        ),
        throwsArgumentError,
      );
    });

    test('remove a própria resposta, mas não as comuns', () async {
      await repo.removeQuickReply(jantando.id);
      expect(
        repo.quickRepliesFor('p2').map((r) => r.id),
        isNot(contains(jantando.id)),
      );
      expect(() => repo.removeQuickReply('bora'), throwsStateError);
    });
  });

  test(
    'Chamado vira mensagem na conversa e espera todos os chamados',
    () async {
      final c = await repo.sendChamado(
        conversationId: 'grupo',
        authorId: 'p1',
        targetIds: ['p2', 'p3'],
        gameId: 'valorant',
      );

      final messages = await repo.watchMessages('grupo').first;
      expect(messages.single.chamadoId, c.id);
      expect(await repo.watchPendingFor('p2').first, hasLength(1));
      expect(await repo.watchPendingFor('p1').first, isEmpty);
    },
  );

  test('responder atualiza o card, calcula a chegada e fecha quando todos responderem', () async {
    final c = await repo.sendChamado(
      conversationId: 'grupo',
      authorId: 'p1',
      targetIds: ['p2', 'p3'],
    );

    await repo.respond(
      chamadoId: c.id,
      userId: 'p2',
      reply: jantando,
      etaMinutes: 30,
    );
    var atual = await repo.watchChamado(c.id).first;
    expect(atual.status, ChamadoStatus.open);
    expect(atual.promisedBy('p2'), DateTime(2026, 10, 1, 19, 30));
    expect(await repo.watchPendingFor('p2').first, isEmpty);

    await repo.respond(chamadoId: c.id, userId: 'p3', reply: sair);
    atual = await repo.watchChamado(c.id).first;
    expect(atual.status, ChamadoStatus.answered);
  });

  test('"Chego em 10 min" já traz o tempo embutido', () async {
    final c = await repo.sendChamado(
      conversationId: 'p1-p2',
      authorId: 'p1',
      targetIds: ['p2'],
    );
    await repo.respond(chamadoId: c.id, userId: 'p2', reply: reply('chego10'));
    final atual = await repo.watchChamado(c.id).first;
    expect(atual.responses['p2']!.etaMinutes, 10);
  });

  test('Chamado encerrado não aceita mais resposta', () async {
    final c = await repo.sendChamado(
      conversationId: 'grupo',
      authorId: 'p1',
      targetIds: ['p2', 'p3'],
    );
    await repo.closeChamado(c.id);
    await repo.respond(chamadoId: c.id, userId: 'p2', reply: reply('bora'));

    final atual = await repo.watchChamado(c.id).first;
    expect(atual.status, ChamadoStatus.closed);
    expect(atual.responses['p2'], isNull);
    expect(await repo.watchPendingFor('p2').first, isEmpty);
  });

  test(
    'recusa Chamado sem ninguém e resposta de quem não foi chamado',
    () async {
      expect(
        () => repo.sendChamado(
          conversationId: 'grupo',
          authorId: 'p1',
          targetIds: [],
        ),
        throwsArgumentError,
      );

      final c = await repo.sendChamado(
        conversationId: 'p1-p2',
        authorId: 'p1',
        targetIds: ['p2'],
      );
      expect(
        () => repo.respond(chamadoId: c.id, userId: 'p3', reply: reply('bora')),
        throwsStateError,
      );
    },
  );

  test('o stream avisa quem está ouvindo a cada mudança', () async {
    final emitted = <int>[];
    final sub = repo
        .watchMessages('grupo')
        .listen((m) => emitted.add(m.length));
    await Future<void>.delayed(Duration.zero);

    await repo.sendText(conversationId: 'grupo', authorId: 'p2', text: 'bora?');
    await repo.sendText(conversationId: 'p1-p3', authorId: 'p3', text: 'oi');
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    // A mensagem da outra conversa também dispara, mas não muda a contagem.
    expect(emitted, [0, 1, 1]);
  });

  group('o Chamado tocando de novo', () {
    test('a insistência toca uma vez, para quem não respondeu', () async {
      final c = await repo.sendChamado(
        conversationId: 'grupo',
        authorId: 'p1',
        targetIds: ['p2', 'p3'],
      );
      await repo.respond(chamadoId: c.id, userId: 'p2', reply: reply('bora'));

      now = DateTime(2026, 10, 1, 19, 4);
      expect((await repo.watchChamado(c.id).first).nudgedAt, isNull);

      now = DateTime(2026, 10, 1, 19, 5);
      var atual = await repo.watchChamado(c.id).first;
      expect(atual.nudgedAt, DateTime(2026, 10, 1, 19, 5));
      expect(atual.silent, ['p3']);

      // Insiste uma vez só: olhar depois não remarca.
      now = DateTime(2026, 10, 1, 19, 8);
      atual = await repo.watchChamado(c.id).first;
      expect(atual.nudgedAt, DateTime(2026, 10, 1, 19, 5));
    });

    test('atrasada demais, a insistência não toca', () async {
      final c = await repo.sendChamado(
        conversationId: 'grupo',
        authorId: 'p1',
        targetIds: ['p2', 'p3'],
      );
      now = DateTime(2026, 10, 1, 19, 25);
      expect((await repo.watchChamado(c.id).first).nudgedAt, isNull);
    });

    test('a soneca traz o Chamado de volta só para quem pediu', () async {
      final c = await repo.sendChamado(
        conversationId: 'p1-p2',
        authorId: 'p1',
        targetIds: ['p2'],
      );
      await repo.respond(
        chamadoId: c.id,
        userId: 'p2',
        reply: reply('soneca'),
        etaMinutes: 30,
      );

      var atual = await repo.watchChamado(c.id).first;
      // Quem pede soneca já respondeu: o Chamado não fica esperando.
      expect(atual.status, ChamadoStatus.answered);
      expect(
        atual.responses['p2']!.snoozedUntil,
        DateTime(2026, 10, 1, 19, 30),
      );
      expect(await repo.watchPendingFor('p2').first, isEmpty);

      now = DateTime(2026, 10, 1, 19, 30);
      atual = await repo.watchChamado(c.id).first;
      expect(atual.responses['p2'], isNull);
      expect(atual.status, ChamadoStatus.open);
      expect(await repo.watchPendingFor('p2').first, hasLength(1));
    });

    test('soneca atrasada demais cai, e a resposta fica no card', () async {
      final c = await repo.sendChamado(
        conversationId: 'p1-p2',
        authorId: 'p1',
        targetIds: ['p2'],
      );
      await repo.respond(
        chamadoId: c.id,
        userId: 'p2',
        reply: reply('soneca'),
        etaMinutes: 30,
      );

      now = DateTime(2026, 10, 1, 19, 50);
      final atual = await repo.watchChamado(c.id).first;
      final resposta = atual.responses['p2']!;
      expect(resposta.snoozedUntil, isNull);
      expect(resposta.reply.kind, ReplyKind.snooze);
      expect(atual.status, ChamadoStatus.answered);
      expect(await repo.watchPendingFor('p2').first, isEmpty);
    });

    test('quem desiste da soneca não é chamado de novo', () async {
      final c = await repo.sendChamado(
        conversationId: 'grupo',
        authorId: 'p1',
        targetIds: ['p2', 'p3'],
      );
      await repo.respond(
        chamadoId: c.id,
        userId: 'p2',
        reply: reply('soneca'),
        etaMinutes: 30,
      );
      await repo.respond(chamadoId: c.id, userId: 'p2', reply: reply('bora'));

      now = DateTime(2026, 10, 1, 19, 30);
      final atual = await repo.watchChamado(c.id).first;
      expect(atual.responses['p2']!.snoozedUntil, isNull);
      expect(atual.responses['p2']!.reply.kind, ReplyKind.yes);
    });

    test('Chamado encerrado não acorda quem pediu soneca', () async {
      final c = await repo.sendChamado(
        conversationId: 'grupo',
        authorId: 'p1',
        targetIds: ['p2', 'p3'],
      );
      await repo.respond(
        chamadoId: c.id,
        userId: 'p2',
        reply: reply('soneca'),
        etaMinutes: 30,
      );
      await repo.closeChamado(c.id);

      now = DateTime(2026, 10, 1, 19, 30);
      final atual = await repo.watchChamado(c.id).first;
      expect(atual.status, ChamadoStatus.closed);
      expect(atual.responses['p2']!.snoozedUntil, isNull);
      expect(await repo.watchPendingFor('p2').first, isEmpty);
    });
  });

  group('o Chamado expirando', () {
    // Longe das 21h: a quinta às 21h é a hora do encontro fixo no seed, e um
    // Chamado nascendo ali atrapalharia a conta.
    final tarde = DateTime(2026, 10, 1, 15);

    test(
      'fecha sozinho depois de duas horas, e não aceita mais resposta',
      () async {
        now = tarde;
        final c = await repo.sendChamado(
          conversationId: 'grupo',
          authorId: 'p1',
          targetIds: ['p2', 'p3'],
        );

        now = DateTime(2026, 10, 1, 16, 59);
        expect((await repo.watchChamado(c.id).first).isOpen, isTrue);

        now = DateTime(2026, 10, 1, 17);
        var atual = await repo.watchChamado(c.id).first;
        expect(atual.status, ChamadoStatus.closed);
        expect(atual.expired, isTrue);
        expect(await repo.watchPendingFor('p2').first, isEmpty);

        await repo.respond(chamadoId: c.id, userId: 'p2', reply: reply('bora'));
        atual = await repo.watchChamado(c.id).first;
        expect(atual.responses['p2'], isNull);
      },
    );

    test('Chamado respondido não expira: fica de registro', () async {
      now = tarde;
      final c = await repo.sendChamado(
        conversationId: 'p1-p2',
        authorId: 'p1',
        targetIds: ['p2'],
      );
      await repo.respond(chamadoId: c.id, userId: 'p2', reply: reply('bora'));

      now = DateTime(2026, 10, 1, 18);
      final atual = await repo.watchChamado(c.id).first;
      expect(atual.status, ChamadoStatus.answered);
      expect(atual.expired, isFalse);
    });

    test('o Chamado marcado conta as duas horas do horário marcado', () async {
      now = tarde;
      final c = await repo.sendChamado(
        conversationId: 'p1-p2',
        authorId: 'p1',
        targetIds: ['p2'],
        scheduledFor: DateTime(2026, 10, 1, 18),
      );

      // Duas horas depois de nascer, mas a hora dele ainda nem chegou.
      now = DateTime(2026, 10, 1, 17, 30);
      expect((await repo.watchChamado(c.id).first).isOpen, isTrue);

      now = DateTime(2026, 10, 1, 20);
      expect((await repo.watchChamado(c.id).first).expired, isTrue);
    });
  });

  group('encontro fixo disparando sozinho', () {
    // O seed marca o encontro na quinta às 21h; 01/10/2026 é quinta.
    final naHora = DateTime(2026, 10, 1, 21);

    test('vira Chamado na hora, uma vez só e chamando todo mundo', () async {
      now = naHora;
      final chamados = await repo.watchHistory('p1').first;
      expect(chamados, hasLength(1));

      final encontro = chamados.single;
      expect(encontro.automatic, isTrue);
      expect(encontro.conversationId, 'grupo');
      // Sem ninguém chamando, todo mundo da conversa é chamado.
      expect(encontro.targetIds.toSet(), {'p1', 'p2', 'p3'});
      expect(await repo.watchPendingFor('p1').first, hasLength(1));

      // Olhar de novo não dispara outro.
      now = naHora.add(const Duration(minutes: 5));
      expect(await repo.watchHistory('p1').first, hasLength(1));
    });

    test('atrasado demais não acorda mais ninguém', () async {
      now = naHora.add(const Duration(minutes: 20));
      expect(await repo.watchHistory('p1').first, isEmpty);
    });

    test('semana pulada não dispara', () async {
      await repo.setMeetingException(
        MeetingException(
          meetingId: 'encontro-grupo',
          date: DateTime(2026, 10, 1),
          skipped: true,
        ),
      );
      now = naHora;
      expect(await repo.watchHistory('p1').first, isEmpty);
    });

    test('horário trocado na semana manda no disparo', () async {
      await repo.setMeetingException(
        MeetingException(
          meetingId: 'encontro-grupo',
          date: DateTime(2026, 10, 1),
          minute: 23 * 60,
        ),
      );
      now = naHora;
      expect(await repo.watchHistory('p1').first, isEmpty);

      now = DateTime(2026, 10, 1, 23);
      expect(await repo.watchHistory('p1').first, hasLength(1));
    });
  });
}
