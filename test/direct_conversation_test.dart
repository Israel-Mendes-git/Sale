import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/domain/models.dart';
import 'package:sale/state/providers.dart';

import 'group_info_test.dart' show abrirDadosDoGrupo;
import 'helpers.dart';

void main() {
  test('a conversa a dois é reaproveitada e só com quem é do grupo', () async {
    final repo = MemoryRepository();
    final a = await repo.openDirect(userId: 'p1', otherId: 'p2');
    final b = await repo.openDirect(userId: 'p2', otherId: 'p1');
    expect(a.id, b.id);
    expect(a.kind, ConversationKind.direct);

    expect(
      () => repo.openDirect(userId: 'p1', otherId: 'p1'),
      throwsStateError,
    );
    await repo.leaveGroup(groupId: 'g1', userId: 'p3');
    expect(
      () => repo.openDirect(userId: 'p1', otherId: 'p3'),
      throwsStateError,
    );
  });

  testWidgets('"Nova conversa" lista quem é do grupo e abre a conversa', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'Pessoa 1');

    await tester.tap(find.byTooltip('Nova conversa'));
    await tester.pumpAndSettle();
    expect(find.text('Conversar com'), findsOneWidget);
    expect(find.text('Pessoa 1'), findsNothing);
    await tester.tap(find.text('Pessoa 3').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Mensagem'),
      'oi, só você',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    expect(find.text('oi, só você'), findsOneWidget);
  });

  testWidgets('nos dados do grupo, tocar em alguém abre a conversa a dois', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    await signInAs(tester, 'Pessoa 2');
    await abrirDadosDoGrupo(tester);

    await scrollTo(tester, find.text('Pessoa 3'));
    await tester.tap(find.text('Pessoa 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Conversar com Pessoa 3'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Mensagem'), 'pssiu');
    await tester.pump();
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    // A conversa nasceu agora e já aparece na lista das duas.
    final conversas = (await tester.runAsync(
      () => c.read(repositoryProvider).watchConversations('p3').first,
    ))!;
    final direta = conversas
        .where((c) => c.kind == ConversationKind.direct)
        .where((c) => c.memberIds.contains('p2'))
        .single;
    final mensagens = (await tester.runAsync(
      () => c.read(repositoryProvider).watchMessages(direta.id).first,
    ))!;
    expect(mensagens.last.text, 'pssiu');
  });
}
