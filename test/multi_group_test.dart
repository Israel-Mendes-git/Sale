import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/domain/models.dart';
import 'package:sale/state/providers.dart';

import 'helpers.dart';

void main() {
  group('repositório', () {
    test(
      'criar e entrar em mais um grupo, cada um com a sua conversa',
      () async {
        final repo = MemoryRepository();
        final firma = await repo.createGroup(userId: 'p1', name: ' Firma ');

        final grupos = await repo.watchGroups('p1').first;
        expect(grupos.map((g) => g.name), ['Os 3', 'Firma']);
        final novo = grupos.last;
        expect(novo.id, firma);
        expect(novo.isAdmin('p1'), isTrue);
        expect(await repo.watchGroups('p2').first, hasLength(1));

        // Quem tem o código entra e passa a ver a conversa do grupo novo.
        expect(
          await repo.joinGroup(userId: 'p2', inviteCode: novo.inviteCode),
          firma,
        );
        final conversas = await repo.watchConversations('p2').first;
        final daFirma = conversas
            .where(
              (c) => c.kind == ConversationKind.group && c.groupId == firma,
            )
            .single;
        expect(daFirma.name, 'Firma');
        expect(daFirma.memberIds, unorderedEquals(['p1', 'p2']));

        // Mudar o nome de um grupo não mexe na conversa do outro.
        await repo.editGroup(groupId: firma, name: 'Firma 2');
        final nomes = {
          for (final c in await repo.watchConversations('p1').first)
            if (c.kind == ConversationKind.group) c.name,
        };
        expect(nomes, {'Os 3', 'Firma 2'});
      },
    );

    test('código errado não entra, e o último a sair apaga o grupo', () async {
      final repo = MemoryRepository();
      expect(
        () => repo.joinGroup(userId: 'p1', inviteCode: 'NADA'),
        throwsStateError,
      );
      expect(
        () => repo.createGroup(userId: 'p1', name: '  '),
        throwsArgumentError,
      );
      final id = await repo.createGroup(userId: 'p3', name: 'Só eu');
      await repo.leaveGroup(groupId: id, userId: 'p3');
      expect((await repo.watchGroups('p3').first).map((g) => g.name), ['Os 3']);
    });
  });

  group('telas', () {
    testWidgets('criar outro grupo pelo perfil, e trocar pelo topo', (
      tester,
    ) async {
      final c = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');

      await tester.tap(find.byTooltip('Meu perfil'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.text('Criar ou entrar em outro grupo'));
      await tester.tap(find.text('Criar ou entrar em outro grupo'));
      await tester.pumpAndSettle();
      expect(find.text('Mais um grupo'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Nome do grupo'),
        'Firma',
      );
      await tester.tap(find.text('Criar grupo'));
      await tester.pumpAndSettle();

      // Volta ao perfil com os dois grupos, e o novo já é o ativo.
      expect(find.text('Seus grupos'), findsOneWidget);
      expect(find.textContaining('Ativo'), findsOneWidget);
      final ativo = c.read(activeGroupProvider('p1'));
      expect(ativo?.name, 'Firma');

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      // As conversas dos dois grupos ficam juntas na lista.
      expect(find.text('Os 3'), findsOneWidget);
      expect(find.text('Firma'), findsNWidgets(2)); // a conversa e o topo

      await tester.tap(find.byTooltip('Trocar de grupo'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<String>, 'Os 3'),
      );
      await tester.pumpAndSettle();
      // Trocou pelo menu, sem abrir conversa nenhuma.
      expect(find.text('Mensagem'), findsNothing);
      expect(c.read(activeGroupProvider('p1'))?.name, 'Os 3');
      expect(find.text('Os 3'), findsNWidgets(2));
    });

    testWidgets('abrir a conversa de um grupo o deixa ativo', (tester) async {
      final c = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await tester.runAsync(
        () =>
            c.read(repositoryProvider).createGroup(userId: 'p1', name: 'Firma'),
      );
      await tester.pumpAndSettle();
      expect(c.read(activeGroupProvider('p1'))?.name, 'Os 3');

      await tester.tap(find.text('Firma'));
      await tester.pumpAndSettle();
      expect(c.read(activeGroupProvider('p1'))?.name, 'Firma');
    });
  });
}
