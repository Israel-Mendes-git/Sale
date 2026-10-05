import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/state/providers.dart';

import 'helpers.dart';

void main() {
  group('a busca na conversa', () {
    testWidgets('acha por texto, sem caixa nem acento, e some o resto', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      final repo = container.read(repositoryProvider);
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p2',
        text: 'bora jogar mais tarde',
      );
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p3',
        text: 'hoje NÃO dá',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Os 3'));
      await tester.pumpAndSettle();

      // O compositor está à vista antes da busca.
      expect(find.widgetWithText(TextField, 'Mensagem'), findsOneWidget);

      await tester.tap(find.byTooltip('Buscar na conversa'));
      await tester.pumpAndSettle();

      // Enquanto busca, o compositor dá lugar à busca.
      expect(find.widgetWithText(TextField, 'Mensagem'), findsNothing);

      // "nao", minúsculo e sem acento, acha "NÃO".
      await tester.enterText(find.byType(TextField), 'nao');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('hoje NÃO dá', findRichText: true),
        findsOneWidget,
      );
      // A que não casa sai da tela.
      expect(
        find.textContaining('bora jogar', findRichText: true),
        findsNothing,
      );

      // Fechar a busca traz a conversa e o compositor de volta.
      await tester.tap(find.byTooltip('Fechar busca'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Mensagem'), findsOneWidget);
      expect(find.text('bora jogar mais tarde'), findsOneWidget);
    });

    testWidgets('sem resultado, avisa', (tester) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await container
          .read(repositoryProvider)
          .sendText(conversationId: 'grupo', authorId: 'p2', text: 'bora hoje');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Os 3'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Buscar na conversa'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'xpto');
      await tester.pumpAndSettle();
      expect(find.textContaining('Nada encontrado'), findsOneWidget);
    });
  });
}
