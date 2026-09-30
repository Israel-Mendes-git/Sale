import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/domain/games.dart';
import 'package:sale/domain/models.dart';
import 'package:sale/state/providers.dart';

import 'helpers.dart';

const valorant = Game(id: 'v', name: 'Valorant', minPlayers: 1, maxPlayers: 5);
const amongUs = Game(id: 'a', name: 'Among Us', minPlayers: 4, maxPlayers: 15);
const duo = Game(id: 'd', name: 'Duo', minPlayers: 2, maxPlayers: 2);

final lib = GameLibrary(
  games: const [valorant, amongUs, duo],
  owners: const {
    'v': {'p1', 'p2', 'p3'},
    'a': {'p1', 'p2', 'p3'},
    'd': {'p1', 'p2'},
  },
);

void main() {
  group('quais jogos dá pra jogar', () {
    test('todos precisam ter e o número de pessoas precisa caber', () {
      expect(lib.playableBy(['p1', 'p2', 'p3']).map((g) => g.id), ['v']);
      // Duas pessoas: o Among Us pede 4; o Duo cabe.
      expect(lib.playableBy(['p1', 'p2']).map((g) => g.name), [
        'Duo',
        'Valorant',
      ]);
      // A Pessoa 3 não tem o Duo.
      expect(lib.playableBy(['p1', 'p3']).map((g) => g.id), ['v']);
      expect(lib.playableBy([]), isEmpty);
    });

    test('faixa de jogadores', () {
      expect(duo.fits(2), isTrue);
      expect(duo.fits(3), isFalse);
      expect(amongUs.playersLabel, '4 a 15 jogadores');
      expect(duo.playersLabel, '2 jogadores');
    });
  });

  group('sorteio', () {
    test('nunca sorteia um excluído e devolve nulo se não sobrar nada', () {
      final options = [valorant, amongUs, duo];
      for (var seed = 0; seed < 50; seed++) {
        final g = drawGame(options, Random(seed), excluded: {'v', 'a'});
        expect(g, duo);
      }
      expect(drawGame(options, Random(1), excluded: {'v', 'a', 'd'}), isNull);
      expect(drawGame(const [], Random(1)), isNull);
    });

    test('com várias opções, todas podem sair', () {
      final seen = {
        for (var seed = 0; seed < 100; seed++)
          drawGame([valorant, amongUs, duo], Random(seed))!.id,
      };
      expect(seen, {'v', 'a', 'd'});
    });
  });

  group('repositório', () {
    late MemoryRepository repo;
    setUp(() => repo = MemoryRepository(random: Random(7)));

    Future<GameLibrary> library() => repo.watchGames().first;

    test('adiciona já marcado como de quem adicionou', () async {
      final g = await repo.addGame(
        name: ' Rocket League ',
        minPlayers: 1,
        maxPlayers: 4,
        addedBy: 'p2',
      );
      expect(g.name, 'Rocket League');
      expect((await library()).ownersOf(g.id), {'p2'});
    });

    test('recusa nome vazio, repetido e faixa sem sentido', () async {
      Future<Game> add(String name, int min, int max) => repo.addGame(
        name: name,
        minPlayers: min,
        maxPlayers: max,
        addedBy: 'p1',
      );
      expect(() => add('  ', 1, 4), throwsArgumentError);
      expect(() => add('valorant', 1, 5), throwsStateError);
      expect(() => add('Xadrez', 3, 2), throwsArgumentError);
      expect(() => add('Xadrez', 0, 2), throwsArgumentError);
      expect(() => add('Xadrez', 1, maxPlayersLimit + 1), throwsArgumentError);
    });

    test('marca, desmarca e remove', () async {
      await repo.setOwnsGame(gameId: 'cs2', userId: 'p3', owns: true);
      expect((await library()).ownersOf('cs2'), containsAll(['p3']));
      await repo.setOwnsGame(gameId: 'cs2', userId: 'p3', owns: false);
      expect((await library()).ownersOf('cs2'), isNot(contains('p3')));
      await repo.removeGame('cs2');
      expect((await library()).byId('cs2'), isNull);
    });

    test('Chamado com jogo escolhido guarda nome e id', () async {
      final c = await repo.sendChamado(
        conversationId: 'grupo',
        authorId: 'p1',
        targetIds: ['p2'],
        gameId: 'cs2',
      );
      expect(c.game, 'Counter-Strike 2');
      expect(c.gameId, 'cs2');
      expect(c.drawn, isFalse);
      expect(
        () => repo.sendChamado(
          conversationId: 'grupo',
          authorId: 'p1',
          targetIds: ['p2'],
          gameId: 'nao-existe',
        ),
        throwsArgumentError,
      );
      expect(
        () => repo.sendChamado(
          conversationId: 'grupo',
          authorId: 'p1',
          targetIds: ['p2'],
          gameId: 'cs2',
          drawGame: true,
        ),
        throwsArgumentError,
      );
    });

    test('sorteio só tira jogo que todos os participantes têm', () async {
      final everyone = (await library()).playableBy(['p1', 'p2', 'p3']);
      for (var seed = 0; seed < 30; seed++) {
        final r = MemoryRepository(random: Random(seed));
        final c = await r.sendChamado(
          conversationId: 'grupo',
          authorId: 'p1',
          targetIds: ['p2', 'p3'],
          drawGame: true,
        );
        expect(c.drawn, isTrue);
        expect(everyone.map((g) => g.id), contains(c.gameId));
      }
    });

    test('sem jogo em comum, não dá para sortear', () async {
      await repo.removeGame('valorant');
      await repo.removeGame('minecraft');
      await repo.removeGame('lethal');
      await repo.removeGame('among-us');
      expect(
        () => repo.sendChamado(
          conversationId: 'grupo',
          authorId: 'p1',
          targetIds: ['p2', 'p3'],
          drawGame: true,
        ),
        throwsStateError,
      );
    });

    test('veto: uma vez por pessoa, sem repetir, até acabar', () async {
      var c = await repo.sendChamado(
        conversationId: 'grupo',
        authorId: 'p1',
        targetIds: ['p2', 'p3'],
        drawGame: true,
      );
      // Valorant, Minecraft e Lethal Company: os três servem para os três.
      final first = c.gameId!;

      await repo.vetoGame(chamadoId: c.id, userId: 'p2');
      c = await repo.watchChamado(c.id).first;
      expect(c.vetoes, {'p2': first});
      expect(c.gameId, isNot(first));
      expect(c.canVeto('p2'), isFalse);
      expect(
        () => repo.vetoGame(chamadoId: c.id, userId: 'p2'),
        throwsStateError,
      );

      final second = c.gameId!;
      await repo.vetoGame(chamadoId: c.id, userId: 'p1');
      c = await repo.watchChamado(c.id).first;
      expect(c.gameId, isNot(anyOf(first, second)));

      await repo.vetoGame(chamadoId: c.id, userId: 'p3');
      c = await repo.watchChamado(c.id).first;
      expect(c.gameId, isNull);
      expect(c.game, isNull);
      expect(c.vetoes, hasLength(3));
    });

    test('quem não participa não veta, nem Chamado sem sorteio', () async {
      final sorteado = await repo.sendChamado(
        conversationId: 'p1-p2',
        authorId: 'p1',
        targetIds: ['p2'],
        drawGame: true,
      );
      expect(
        () => repo.vetoGame(chamadoId: sorteado.id, userId: 'p3'),
        throwsStateError,
      );
      final escolhido = await repo.sendChamado(
        conversationId: 'p1-p2',
        authorId: 'p1',
        targetIds: ['p2'],
        gameId: 'valorant',
      );
      expect(
        () => repo.vetoGame(chamadoId: escolhido.id, userId: 'p2'),
        throwsStateError,
      );
      await repo.closeChamado(sorteado.id);
      expect(
        () => repo.vetoGame(chamadoId: sorteado.id, userId: 'p2'),
        throwsStateError,
      );
    });
  });

  group('telas', () {
    testWidgets('aba Jogos: marcar "Eu tenho" e adicionar jogo', (
      tester,
    ) async {
      await pumpApp(tester);
      await signInAs(tester, 'Pessoa 3');
      await tester.tap(find.text('Jogos'));
      await tester.pumpAndSettle();

      expect(find.text('Que todo o grupo tem (4)'), findsOneWidget);
      final cs2 = find.ancestor(
        of: find.text('Counter-Strike 2'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(of: cs2, matching: find.byType(FilterChip)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Que todo o grupo tem (5)'), findsOneWidget);

      await tester.tap(find.text('Adicionar jogo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Nome do jogo'),
        'valorant',
      );
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      expect(find.text('"valorant" já está na biblioteca.'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Nome do jogo'),
        'Rocket League',
      );
      await tester.tap(find.byTooltip('Menos (Máximo de jogadores)'));
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Rocket League'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Rocket League'), findsOneWidget);
      expect(find.text('1 a 4 jogadores · têm: você'), findsOneWidget);
    });

    testWidgets('Chamado só oferece jogos que todos os chamados têm', (
      tester,
    ) async {
      await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await tester.tap(find.text('Os 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Chamado'));
      await tester.pumpAndSettle();

      // Com os três, o CS2 não aparece (a Pessoa 3 não tem).
      expect(find.widgetWithText(ChoiceChip, 'Counter-Strike 2'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Valorant'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilterChip, 'Pessoa 3'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(ChoiceChip, 'Counter-Strike 2'),
        findsOneWidget,
      );
    });

    testWidgets('sorteio no Chamado e veto no card', (tester) async {
      final c = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await tester.tap(find.text('Os 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Chamado'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '🎲 Sortear'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disparar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('CHAMADO · 🎲 '), findsOneWidget);
      expect(
        find.text('Jogo sorteado. Cada um pode vetar uma vez.'),
        findsOneWidget,
      );

      await tester.tap(find.text('Vetar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Vetados: '), findsOneWidget);
      expect(find.textContaining('(você)'), findsOneWidget);
      expect(find.text('Vetar'), findsNothing);

      final repo = c.read(repositoryProvider);
      final msgs = (await tester.runAsync(
        () => repo.watchMessages('grupo').first,
      ))!;
      final chamado = (await tester.runAsync(
        () => repo.watchChamado(msgs.single.chamadoId!).first,
      ))!;
      expect(chamado.vetoes.keys, ['p1']);
      expect(chamado.gameId, isNot(chamado.vetoes['p1']));
      expect(chamado.status, ChamadoStatus.open);
    });
  });
}
