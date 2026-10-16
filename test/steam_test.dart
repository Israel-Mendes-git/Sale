import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/domain/games.dart';
import 'package:sale/domain/steam.dart';
import 'package:sale/state/providers.dart';

import 'helpers.dart';

void main() {
  group('o perfil da Steam', () {
    test('sai do link, do ID ou do nome', () {
      expect(
        lerPerfilDaSteam('https://steamcommunity.com/id/israelzin/'),
        'israelzin',
      );
      expect(
        lerPerfilDaSteam('steamcommunity.com/profiles/76561198000000000'),
        '76561198000000000',
      );
      expect(lerPerfilDaSteam('  israelzin '), 'israelzin');
      expect(lerPerfilDaSteam('   '), isNull);
    });
  });

  group('o cruzamento com a biblioteca', () {
    const biblioteca = [
      Game(id: 'cs2', name: 'Counter-Strike 2', minPlayers: 1, maxPlayers: 5),
      Game(id: 'drg', name: 'Deep Rock Galactic', minPlayers: 1, maxPlayers: 4),
    ];

    test('o nome bate sem caixa, ™, ® nem pontuação', () {
      expect(
        normalizarNome('Counter-Strike® 2'),
        normalizarNome('counter strike 2'),
      );
    });

    test('separa o que já está do que falta, o mais jogado primeiro', () {
      final cruzado = cruzarComBiblioteca(const [
        JogoDaSteam(nome: 'Counter-Strike® 2', horas: 300),
        JogoDaSteam(nome: 'Stardew Valley', horas: 10),
        JogoDaSteam(nome: 'Hades', horas: 40),
      ], biblioteca);
      expect(cruzado.naBiblioteca.keys, ['cs2']);
      expect(
        [for (final j in cruzado.fora) j.nome],
        ['Hades', 'Stardew Valley'],
      );
    });
  });

  group('o nome que entra na biblioteca', () {
    test('sem ™ e ®, e cabendo no limite, cortado entre palavras', () {
      expect(nomeParaBiblioteca('Counter-Strike® 2'), 'Counter-Strike 2');
      final longo = nomeParaBiblioteca(
        'STAR WARS Jedi: Fallen Order™ Deluxe Edition',
      );
      expect(longo, 'STAR WARS Jedi: Fallen Order Deluxe');
      expect(longo.length, lessThanOrEqualTo(maxGameNameLength));
    });

    test('sem espaço para cortar, corta no limite', () {
      final nome = nomeParaBiblioteca('A' * 60);
      expect(nome.length, maxGameNameLength);
    });

    test('o jogo que entrou encurtado é achado na próxima importação', () {
      const steam = JogoDaSteam(
        nome: 'STAR WARS Jedi: Fallen Order™ Deluxe Edition',
      );
      final cruzado = cruzarComBiblioteca(
        const [steam],
        const [
          Game(
            id: 'jedi',
            name: 'STAR WARS Jedi: Fallen Order Deluxe',
            minPlayers: 1,
            maxPlayers: 1,
          ),
        ],
      );
      expect(cruzado.naBiblioteca.keys, ['jedi']);
      expect(cruzado.fora, isEmpty);
    });
  });

  group('a faixa de jogadores pela loja', () {
    test('só um jogador é 1', () {
      expect(faixaPelaSteam([2]), (min: 1, max: 1));
    });
    test('co-op sem PvP vai até 4, e com single-player começa em 1', () {
      expect(faixaPelaSteam([2, 1, 9, 38]), (min: 1, max: 4));
      expect(faixaPelaSteam([1, 38]), (min: 2, max: 4));
    });
    test('PvP vai até 10, MMO até o limite', () {
      expect(faixaPelaSteam([1, 36, 49]), (min: 2, max: 10));
      expect(faixaPelaSteam([1, 9, 36]), (min: 2, max: 10));
      expect(faixaPelaSteam([2, 1, 20]), (min: 1, max: maxPlayersLimit));
    });
    test('multijogador só local vai até 4, com rede volta a 10', () {
      // LEGO: solo e tela dividida.
      expect(faixaPelaSteam([2, 1, 24]), (min: 1, max: 4));
      // Rain World: solo e PvP local.
      expect(faixaPelaSteam([2, 1, 49, 37]), (min: 1, max: 4));
      // Brawlhalla: tela dividida, mas também PvP online.
      expect(faixaPelaSteam([2, 1, 49, 36, 37, 24, 27]), (min: 1, max: 10));
      // Só "multijogador", sem dizer onde: não dá para saber, fica 10.
      expect(faixaPelaSteam([2, 1]), (min: 1, max: 10));
    });
    test('sem categoria que diga, não chuta', () {
      expect(faixaPelaSteam([]), isNull);
      expect(faixaPelaSteam([22, 29]), isNull);
    });
  });

  group('telas', () {
    testWidgets('importar marca o que tenho e traz o que eu escolher', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await tester.tap(find.text('Jogos'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Importar da Steam'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'https://steamcommunity.com/id/pessoa1',
      );
      await tester.tap(find.text('Buscar'));
      await tester.pumpAndSettle();

      expect(find.text('Achei 5 jogos na sua Steam'), findsOneWidget);
      // Hades fica de fora da biblioteca: escolho trazer.
      await tester.tap(find.text('Hades'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Trazer 1'));
      await tester.pumpAndSettle();

      final biblioteca = (await tester.runAsync(
        () => container.read(repositoryProvider).watchGames().first,
      ))!;
      final hades = biblioteca.games.where((g) => g.name == 'Hades').single;
      expect(biblioteca.ownersOf(hades.id), contains('p1'));
      // A loja diz que Hades é só de um jogador.
      expect(hades.playersLabel, '1 jogador');
    });

    testWidgets('"Marcar todos" traz todos, até o de nome comprido', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await tester.tap(find.text('Jogos'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Importar da Steam'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'pessoa1');
      await tester.tap(find.text('Buscar'));
      await tester.pumpAndSettle();

      // Nada escolhido ainda: o botão diz o que falta, desligado.
      expect(find.text('Escolha o que importar'), findsOneWidget);
      await tester.tap(find.text('Marcar todos'));
      await tester.pump();
      expect(find.text('Desmarcar todos'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Trazer 3'));
      await tester.pumpAndSettle();

      final nomes = [
        for (final g in (await tester.runAsync(
          () => container.read(repositoryProvider).watchGames().first,
        ))!.games)
          g.name,
      ];
      expect(nomes, containsAll(['Hades', 'Stardew Valley']));
      expect(nomes, contains('STAR WARS Jedi: Fallen Order Deluxe'));
      expect(find.textContaining('Ficou de fora'), findsNothing);
    });

    testWidgets('a faixa de um jogo se ajusta na biblioteca', (tester) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await tester.tap(find.text('Jogos'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Opções de Among Us'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ajustar jogadores'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Menos (Máximo de jogadores)'));
      await tester.pump();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      final biblioteca = (await tester.runAsync(
        () => container.read(repositoryProvider).watchGames().first,
      ))!;
      final among = biblioteca.games.where((g) => g.name == 'Among Us').single;
      expect((among.minPlayers, among.maxPlayers), (4, 14));
    });
  });
}
