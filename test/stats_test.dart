import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/domain/models.dart';
import 'package:sale/domain/stats.dart';
import 'package:sale/ui/format.dart';

import 'helpers.dart';

const _bora = QuickReply(
  id: 'bora',
  icon: 'check',
  label: 'Bora!',
  kind: ReplyKind.yes,
);
const _chego20 = QuickReply(
  id: 'chego20',
  icon: 'relogio',
  label: 'Chego em 20 min',
  kind: ReplyKind.later,
  etaMinutes: 20,
);
const _hojeNao = QuickReply(
  id: 'hojenao',
  icon: 'xis',
  label: 'Hoje não',
  kind: ReplyKind.no,
);
const _soneca = QuickReply(
  id: 'soneca',
  icon: 'soneca',
  label: 'Me chama daqui a pouco',
  kind: ReplyKind.snooze,
);

final _vinteEUma = DateTime(2026, 10, 1, 21);

/// Resposta dada às 21h; [chegou] é quanto tempo depois dela a pessoa marcou
/// "Cheguei".
ChamadoResponse _respondeu(QuickReply reply, {Duration? chegou}) =>
    ChamadoResponse(
      reply: reply,
      respondedAt: _vinteEUma,
      etaMinutes: reply.etaMinutes,
      arrivedAt: chegou == null ? null : _vinteEUma.add(chegou),
    );

Chamado _chamado({
  required Map<String, ChamadoResponse?> responses,
  String id = 'c1',
  String author = 'p1',
  String? game,
  ChamadoStatus status = ChamadoStatus.open,
  DateTime? scheduledFor,
}) => Chamado(
  id: id,
  conversationId: 'grupo',
  authorId: author,
  createdAt: _vinteEUma,
  game: game,
  status: status,
  scheduledFor: scheduledFor,
  responses: responses,
);

void main() {
  group('conta', () {
    test('o atraso é a diferença entre o prometido e o Cheguei', () {
      final stats = computeStats([
        _chamado(
          responses: {
            'p2': _respondeu(_chego20, chegou: const Duration(minutes: 27)),
          },
        ),
        _chamado(
          id: 'c2',
          responses: {
            'p2': _respondeu(_chego20, chegou: const Duration(minutes: 15)),
          },
        ),
      ]);
      final p2 = stats.forUser('p2')!;
      expect(p2.arrivals, 2);
      // Sete minutos atrasado e cinco adiantado: um minuto de média.
      expect(p2.averageLate, const Duration(minutes: 1));
      expect(p2.worstLate, const Duration(minutes: 7));
    });

    test('"Bora!" promete a hora da própria resposta', () {
      final stats = computeStats([
        _chamado(
          responses: {
            'p2': _respondeu(_bora, chegou: const Duration(minutes: 10)),
          },
        ),
      ]);
      expect(stats.forUser('p2')!.averageLate, const Duration(minutes: 10));
    });

    test('Chamado marcado para depois conta da hora marcada', () {
      // Respondeu "bora" às 21h a um Chamado das 23h e chegou às 23h05.
      final chamado = _chamado(
        scheduledFor: _vinteEUma.add(const Duration(hours: 2)),
        responses: {
          'p2': _respondeu(_bora, chegou: const Duration(hours: 2, minutes: 5)),
        },
      );
      expect(
        chamado.promisedBy('p2'),
        _vinteEUma.add(const Duration(hours: 2)),
      );
      expect(chamado.lateBy('p2'), const Duration(minutes: 5));
      expect(
        computeStats([chamado]).forUser('p2')!.averageLate,
        const Duration(minutes: 5),
      );
    });

    test('quem não disse que vinha fica fora do placar do atraso', () {
      final stats = computeStats([
        _chamado(
          responses: {
            'p2': _respondeu(_hojeNao, chegou: const Duration(minutes: 5)),
            'p3': _respondeu(_soneca, chegou: const Duration(minutes: 5)),
          },
        ),
      ]);
      expect(stats.byPunctuality, isEmpty);
      expect(stats.forUser('p2')!.refused, 1);
      // "Me chama daqui a pouco" não é sim nem não.
      final p3 = stats.forUser('p3')!;
      expect(p3.answered, 1);
      expect(p3.accepted, 0);
      expect(p3.refused, 0);
    });

    test('quem mais chama e quem mais recusa', () {
      final stats = computeStats([
        _chamado(
          responses: {'p2': _respondeu(_hojeNao), 'p3': _respondeu(_bora)},
        ),
        _chamado(id: 'c2', responses: {'p2': _respondeu(_hojeNao)}),
        _chamado(id: 'c3', author: 'p2', responses: {'p1': _respondeu(_bora)}),
      ]);
      expect([for (final p in stats.byCalls) p.userId], ['p1', 'p2']);
      expect(stats.byCalls.first.called, 2);
      expect([for (final p in stats.byRefusals) p.userId], ['p2']);
      expect(stats.byRefusals.first.refused, 2);
    });

    test('o jogo mais chamado vem primeiro; "qualquer coisa" não conta', () {
      final stats = computeStats([
        _chamado(game: 'Valorant', responses: {'p2': null}),
        _chamado(id: 'c2', game: 'Valorant', responses: {'p2': null}),
        _chamado(id: 'c3', game: 'Among Us', responses: {'p2': null}),
        _chamado(id: 'c4', responses: {'p2': null}),
      ]);
      expect(
        [for (final g in stats.games) '${g.name} ${g.times}'],
        ['Valorant 2', 'Among Us 1'],
      );
      expect(stats.chamados, 4);
    });

    test('só o Chamado encerrado conta como não respondido', () {
      final aberto = computeStats([
        _chamado(responses: {'p2': null}),
      ]);
      expect(aberto.forUser('p2')!.ignored, 0);

      final encerrado = computeStats([
        _chamado(status: ChamadoStatus.closed, responses: {'p2': null}),
      ]);
      expect(encerrado.forUser('p2')!.ignored, 1);
      expect(encerrado.forUser('p2')!.invited, 1);
    });

    test('sem Chamado, o grupo aparece com zero', () {
      final stats = computeStats(const [], members: ['p1', 'p2']);
      expect(stats.isEmpty, isTrue);
      expect(stats.players.length, 2);
      expect(stats.byCalls, isEmpty);
    });
  });

  group('rótulos', () {
    test('atraso em palavras', () {
      expect(lateLabel(const Duration(minutes: 7)), '7 min atrasado');
      expect(lateLabel(const Duration(minutes: -5)), '5 min adiantado');
      expect(lateLabel(const Duration(seconds: 40)), 'na hora');
      expect(lateLabel(const Duration(minutes: 65)), '1 h 05 atrasado');
      expect(lateLabel(const Duration(minutes: 120)), '2 h atrasado');
    });

    test('a chegada aparece com a hora', () {
      final chegou = _chamado(
        responses: {
          'p2': _respondeu(_chego20, chegou: const Duration(minutes: 27)),
        },
      );
      expect(arrivalLabel(chegou, 'p2'), 'chegou 21:27 · 7 min atrasado');
      expect(responseLabel(chegou, 'p2'), 'Chego em 20 min · chega ~21:20');

      final semChegada = _chamado(responses: {'p2': _respondeu(_chego20)});
      expect(arrivalLabel(semChegada, 'p2'), isEmpty);
      // Quem vem na hora não ganha "chega ~": a hora já está no Chamado.
      final bora = _chamado(responses: {'p2': _respondeu(_bora)});
      expect(responseLabel(bora, 'p2'), 'Bora!');
    });
  });

  group('repositório', () {
    late MemoryRepository repo;
    var now = DateTime(2026, 10, 1, 21);

    /// Resposta comum a todos, pelo id.
    QuickReply reply(String id) =>
        repo.quickRepliesFor('p2').firstWhere((r) => r.id == id);

    setUp(() {
      now = DateTime(2026, 10, 1, 21);
      repo = MemoryRepository(clock: () => now);
    });

    Future<Chamado> chamarOGrupo() => repo.sendChamado(
      conversationId: 'grupo',
      authorId: 'p1',
      targetIds: ['p2', 'p3'],
    );

    test('só quem prometeu vir marca que chegou', () async {
      final chamado = await chamarOGrupo();
      // Quem ainda não respondeu não tem o que marcar.
      expect(
        () => repo.markArrived(chamadoId: chamado.id, userId: 'p2'),
        throwsStateError,
      );

      await repo.respond(
        chamadoId: chamado.id,
        userId: 'p2',
        reply: reply('chego20'),
      );
      await repo.respond(
        chamadoId: chamado.id,
        userId: 'p3',
        reply: reply('hojenao'),
      );
      // Nem quem disse que não vinha, nem quem chamou.
      expect(
        () => repo.markArrived(chamadoId: chamado.id, userId: 'p3'),
        throwsStateError,
      );
      expect(
        () => repo.markArrived(chamadoId: chamado.id, userId: 'p1'),
        throwsStateError,
      );

      now = now.add(const Duration(minutes: 27));
      await repo.markArrived(chamadoId: chamado.id, userId: 'p2');
      final atualizado = await repo.watchChamado(chamado.id).first;
      expect(atualizado.lateBy('p2'), const Duration(minutes: 7));
      // E só marca uma vez.
      expect(
        () => repo.markArrived(chamadoId: chamado.id, userId: 'p2'),
        throwsStateError,
      );
    });

    test('Chamado encerrado não espera mais chegada', () async {
      final chamado = await chamarOGrupo();
      await repo.respond(
        chamadoId: chamado.id,
        userId: 'p2',
        reply: reply('bora'),
      );
      expect(await repo.watchArrivalPending('p2').first, hasLength(1));

      await repo.closeChamado(chamado.id);
      expect(await repo.watchArrivalPending('p2').first, isEmpty);
      expect(
        () => repo.markArrived(chamadoId: chamado.id, userId: 'p2'),
        throwsStateError,
      );
    });

    test('o histórico traz só os Chamados de quem olha', () async {
      await chamarOGrupo();
      await repo.sendChamado(
        conversationId: 'p2-p3',
        authorId: 'p2',
        targetIds: ['p3'],
      );
      expect(await repo.watchHistory('p1').first, hasLength(1));
      expect(await repo.watchHistory('p3').first, hasLength(2));
    });
  });

  group('telas', () {
    testWidgets('o Cheguei vira placar', (tester) async {
      var agora = DateTime(2026, 10, 1, 21);
      await pumpApp(tester, clock: () => agora);

      // A Pessoa 1 chama o grupo.
      await signInAs(tester, 'Pessoa 1');
      await tester.tap(find.text('Os 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Chamado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disparar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();

      // A Pessoa 2 promete chegar em 20 min, pela tela cheia.
      await switchTo(tester, 'Pessoa 2');
      await tester.tap(find.text('Pessoa 1 te chamou pra jogar'));
      // A tela cheia pulsa sem parar: pumpAndSettle nunca terminaria nela.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Chego em 20 min'));
      await tester.pumpAndSettle();

      // O aviso de chegada aparece com a hora prometida.
      expect(find.text('Você disse que chegava às 21:20'), findsOneWidget);

      // Ela chega sete minutos depois do prometido.
      agora = agora.add(const Duration(minutes: 27));
      await tester.tap(find.text('Cheguei'));
      await tester.pumpAndSettle();
      expect(find.text('Cheguei'), findsNothing);

      // O card da conversa mostra a chegada.
      await tester.tap(find.text('Os 3'));
      await tester.pumpAndSettle();
      expect(find.text('chegou 21:27 · 7 min atrasado'), findsOneWidget);
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();

      // E o placar também.
      await tester.tap(find.byTooltip('Meu perfil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Placar'));
      await tester.pumpAndSettle();
      expect(find.text('7 min atrasado'), findsOneWidget);
      expect(find.text('1 chegada'), findsOneWidget);
      expect(find.text('Quem mais chama'), findsOneWidget);
      expect(find.text('Contando 1 Chamado.'), findsOneWidget);
    });

    testWidgets('sem Chamado, o placar explica que está vazio', (tester) async {
      await pumpApp(tester);
      await signInAs(tester, 'Pessoa 3');
      await tester.tap(find.byTooltip('Meu perfil'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Placar'));
      await tester.pumpAndSettle();

      expect(find.text('O placar começa no primeiro Chamado.'), findsOneWidget);
    });
  });
}
