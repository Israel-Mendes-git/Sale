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

      expect(find.text('Achei 4 jogos na sua Steam'), findsOneWidget);
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
    });
  });
}
