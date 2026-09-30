import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/domain/models.dart';

void main() {
  late MemoryRepository repo;
  var now = DateTime(2026, 10, 1, 21);

  QuickReply reply(String id) => repo
      .quickRepliesFor('beto')
      .followedBy(repo.quickRepliesFor('caio'))
      .firstWhere((r) => r.id == id);

  setUp(() {
    now = DateTime(2026, 10, 1, 21);
    repo = MemoryRepository(clock: () => now);
  });

  test('respostas rápidas = comuns + as da própria pessoa', () {
    final ids = repo.quickRepliesFor('beto').map((r) => r.id).toSet();
    expect(
      ids,
      containsAll(['bora', 'hojenao', 'beto-namorada', 'beto-gatos']),
    );
    expect(ids.any((id) => id.startsWith('caio-')), isFalse);
    expect(ids.any((id) => id.startsWith('israel-')), isFalse);
  });

  test(
    'Chamado vira mensagem na conversa e espera todos os chamados',
    () async {
      final c = await repo.sendChamado(
        conversationId: 'grupo',
        authorId: 'israel',
        targetIds: ['beto', 'caio'],
        game: 'Valorant',
      );

      final messages = await repo.watchMessages('grupo').first;
      expect(messages.single.chamadoId, c.id);
      expect(await repo.watchPendingFor('beto').first, hasLength(1));
      expect(await repo.watchPendingFor('israel').first, isEmpty);
    },
  );

  test('responder atualiza o card, calcula a chegada e fecha quando todos responderem', () async {
    final c = await repo.sendChamado(
      conversationId: 'grupo',
      authorId: 'israel',
      targetIds: ['beto', 'caio'],
    );

    await repo.respond(
      chamadoId: c.id,
      userId: 'beto',
      reply: reply('beto-jantando'),
      etaMinutes: 30,
    );
    var atual = await repo.watchChamado(c.id).first;
    expect(atual.status, ChamadoStatus.open);
    expect(atual.responses['beto']!.eta, DateTime(2026, 10, 1, 21, 30));
    expect(await repo.watchPendingFor('beto').first, isEmpty);

    await repo.respond(
      chamadoId: c.id,
      userId: 'caio',
      reply: reply('caio-sair'),
    );
    atual = await repo.watchChamado(c.id).first;
    expect(atual.status, ChamadoStatus.answered);
  });

  test('"Chego em 10 min" já traz o tempo embutido', () async {
    final c = await repo.sendChamado(
      conversationId: 'israel-beto',
      authorId: 'israel',
      targetIds: ['beto'],
    );
    await repo.respond(
      chamadoId: c.id,
      userId: 'beto',
      reply: reply('chego10'),
    );
    final atual = await repo.watchChamado(c.id).first;
    expect(atual.responses['beto']!.etaMinutes, 10);
  });

  test('Chamado encerrado não aceita mais resposta', () async {
    final c = await repo.sendChamado(
      conversationId: 'grupo',
      authorId: 'israel',
      targetIds: ['beto', 'caio'],
    );
    await repo.closeChamado(c.id);
    await repo.respond(chamadoId: c.id, userId: 'beto', reply: reply('bora'));

    final atual = await repo.watchChamado(c.id).first;
    expect(atual.status, ChamadoStatus.closed);
    expect(atual.responses['beto'], isNull);
    expect(await repo.watchPendingFor('beto').first, isEmpty);
  });

  test(
    'recusa Chamado sem ninguém e resposta de quem não foi chamado',
    () async {
      expect(
        () => repo.sendChamado(
          conversationId: 'grupo',
          authorId: 'israel',
          targetIds: [],
        ),
        throwsArgumentError,
      );

      final c = await repo.sendChamado(
        conversationId: 'israel-beto',
        authorId: 'israel',
        targetIds: ['beto'],
      );
      expect(
        () =>
            repo.respond(chamadoId: c.id, userId: 'caio', reply: reply('bora')),
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

    await repo.sendText(
      conversationId: 'grupo',
      authorId: 'beto',
      text: 'bora?',
    );
    await repo.sendText(
      conversationId: 'israel-caio',
      authorId: 'caio',
      text: 'oi',
    );
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    // A mensagem da outra conversa também dispara, mas não muda a contagem.
    expect(emitted, [0, 1, 1]);
  });
}
