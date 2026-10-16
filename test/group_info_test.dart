import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/domain/models.dart';
import 'package:sale/state/providers.dart';

import 'helpers.dart';

/// Abre os dados do grupo pelo título da conversa do grupo.
Future<void> abrirDadosDoGrupo(WidgetTester tester) async {
  await tester.tap(find.text('Os 3'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Os 3').last);
  await tester.pumpAndSettle();
  expect(find.text('Dados do grupo'), findsOneWidget);
}

void main() {
  testWidgets('o título do grupo abre os dados, e nome e descrição mudam', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    await signInAs(tester, 'Pessoa 2');
    await abrirDadosDoGrupo(tester);

    expect(find.text('3 participantes'), findsWidgets);
    await tester.tap(find.text('Adicionar descrição'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nome do grupo'),
      'Os Três',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Descrição'),
      'IP do servidor: 10.0.0.1',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Os Três'), findsOneWidget);
    expect(find.text('IP do servidor: 10.0.0.1'), findsOneWidget);
    // O nome vale também para a conversa do grupo.
    final conversas = (await tester.runAsync(
      () => c.read(repositoryProvider).watchConversations('p2').first,
    ))!;
    expect(
      conversas.where((c) => c.kind == ConversationKind.group).single.name,
      'Os Três',
    );
  });

  testWidgets('admin remove alguém e nomeia outro admin', (tester) async {
    final c = await pumpApp(tester);
    await signInAs(tester, 'Pessoa 1');
    await abrirDadosDoGrupo(tester);

    expect(find.text('Gerar código novo'), findsOneWidget);
    await scrollTo(tester, find.text('Pessoa 3'));
    await tester.tap(find.text('Pessoa 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover Pessoa 3 do grupo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
    await tester.pumpAndSettle();
    expect(find.text('2 participantes'), findsWidgets);

    await tester.tap(find.text('Pessoa 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tornar admin'));
    await tester.pumpAndSettle();
    final grupo = (await tester.runAsync(
      () => c.read(repositoryProvider).watchGroups('p1').first,
    ))!.single;
    expect(grupo.adminIds, {'p1', 'p2'});
    expect(grupo.memberIds, isNot(contains('p3')));
  });

  testWidgets('quem não é admin não remove nem troca o convite', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'Pessoa 2');
    await abrirDadosDoGrupo(tester);

    expect(find.text('Gerar código novo'), findsNothing);
    await scrollTo(tester, find.text('Pessoa 3'));
    await tester.tap(find.text('Pessoa 3'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Remover'), findsNothing);
    expect(find.text('Tornar admin'), findsNothing);
  });

  testWidgets('sair do grupo tira a conversa do grupo da lista', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'Pessoa 3');
    await abrirDadosDoGrupo(tester);

    await scrollTo(tester, find.text('Sair do grupo'));
    await tester.tap(find.text('Sair do grupo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sair'));
    await tester.pumpAndSettle();

    expect(find.text('Dados do grupo'), findsNothing);
    expect(find.text('Os 3'), findsNothing);
  });
}
