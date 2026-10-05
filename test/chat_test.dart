import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/domain/models.dart';
import 'package:sale/push/push.dart';
import 'package:sale/ui/widgets/message_ticks.dart';

import 'helpers.dart';

/// A marquinha da mensagem na tela da frente (a de trás continua na árvore).
MessageStatus _ticks(WidgetTester tester) =>
    tester.widget<MessageTicks>(find.byType(MessageTicks).last).status;

void main() {
  testWidgets('a mensagem conta por onde passou: enviada, entregue e lida', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'Pessoa 1');

    // Na conversa individual, quem tem de receber é uma pessoa só.
    await tester.tap(find.text('Pessoa 2'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Mensagem'),
      'bora hoje?',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();

    // A Pessoa 2 nem abriu o app: a mensagem está só no servidor.
    expect(find.text('bora hoje?'), findsOneWidget);
    expect(_ticks(tester), MessageStatus.sent);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    // A Pessoa 2 abre o app: a mensagem chega no aparelho dela e a conversa
    // aparece com uma por ler.
    await switchTo(tester, 'Pessoa 2');
    expect(find.widgetWithText(Badge, '1'), findsOneWidget);

    await switchTo(tester, 'Pessoa 1');
    expect(_ticks(tester), MessageStatus.delivered);

    // A Pessoa 2 abre a conversa: aí sim ela viu.
    await switchTo(tester, 'Pessoa 2');
    await tester.tap(find.text('Pessoa 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(Badge, '1'), findsNothing);

    await switchTo(tester, 'Pessoa 1');
    expect(_ticks(tester), MessageStatus.read);
  });

  testWidgets('a conversa na tela não recebe aviso das mensagens dela', (
    tester,
  ) async {
    // É o que o push consulta antes de montar o aviso no celular: quem está
    // lendo a conversa não precisa ser avisado dela.
    await pumpApp(tester);
    await signInAs(tester, 'Pessoa 1');
    expect(conversaAberta.value, isNull);

    await tester.tap(find.text('Pessoa 2'));
    await tester.pumpAndSettle();
    expect(conversaAberta.value, isNotNull);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(conversaAberta.value, isNull);
  });

  testWidgets('no grupo, a marca espera o último', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'Pessoa 1');

    await tester.tap(find.text('Os 3'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Mensagem'),
      'alguém hoje?',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    // Só a Pessoa 2 abriu o app; falta a Pessoa 3 para o segundo tique.
    await switchTo(tester, 'Pessoa 2');
    await switchTo(tester, 'Pessoa 1');
    expect(_ticks(tester), MessageStatus.sent);

    await switchTo(tester, 'Pessoa 3');
    await switchTo(tester, 'Pessoa 1');
    expect(_ticks(tester), MessageStatus.delivered);

    // E a mensagem só fica lida quando as duas abrirem a conversa.
    await switchTo(tester, 'Pessoa 2');
    await tester.tap(find.text('Os 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    await switchTo(tester, 'Pessoa 1');
    expect(_ticks(tester), MessageStatus.delivered);

    await switchTo(tester, 'Pessoa 3');
    await tester.tap(find.text('Os 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    await switchTo(tester, 'Pessoa 1');
    expect(_ticks(tester), MessageStatus.read);
  });
}
