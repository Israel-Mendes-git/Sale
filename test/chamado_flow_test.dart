import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

/// Fluxo completo nas telas: a Pessoa 2 escolhe o nome e cadastra uma
/// resposta própria; a Pessoa 1 chama; a Pessoa 2 responde com ela.
void main() {
  testWidgets('nome e resposta próprios chegam ao Chamado', (tester) async {
    await pumpApp(tester);

    // Pessoa 2 escolhe como quer ser chamada.
    await signInAs(tester, 'Pessoa 2');
    await tester.tap(find.text('Como o grupo te chama?'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Seu nome'), 'Duda');
    await tester.tap(find.text('Salvar nome'));
    await tester.pumpAndSettle();

    // E cadastra uma situação dela, do tipo "vou, mas depois" (o padrão).
    await scrollTo(tester, find.text('Nova resposta'), scrollable: frontList);
    await tester.tap(find.text('Nova resposta'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.restaurant_rounded));
    await tester.enterText(
      find.widgetWithText(TextField, 'Situação'),
      'Tô jantando',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Tô jantando'), scrollable: frontList);
    expect(find.text('Tô jantando'), findsOneWidget);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(find.text('Como o grupo te chama?'), findsNothing);

    // Pessoa 1 abre o grupo e chama só a Duda.
    await switchTo(tester, 'Pessoa 1');
    await tester.tap(find.text('Os 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chamado'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Pessoa 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Valorant'));
    await tester.tap(find.text('Disparar'));
    await tester.pumpAndSettle();

    expect(find.text('CHAMADO · Valorant'), findsOneWidget);
    expect(find.text('Duda'), findsOneWidget);
    expect(find.text('aguardando…'), findsOneWidget);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    await switchTo(tester, 'Duda');

    // O aviso aparece e abre a tela cheia.
    expect(find.text('Pessoa 1 te chamou pra jogar'), findsOneWidget);
    // A tela cheia pulsa sem parar: pumpAndSettle nunca terminaria nela.
    await tester.tap(find.text('Pessoa 1 te chamou pra jogar'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // A resposta própria aparece e pergunta o tempo antes de responder.
    await tester.tap(find.text('Tô jantando'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('30 min'));
    await tester.pumpAndSettle();

    expect(find.text('Pessoa 1 te chamou pra jogar'), findsNothing);

    // O card no grupo mostra a resposta.
    await tester.tap(find.text('Os 3'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Tô jantando · chega ~'), findsOneWidget);
    expect(find.text('respondido'), findsOneWidget);
  });

  testWidgets('a soneca traz o Chamado de volta, e a insistência avisa', (
    tester,
  ) async {
    var agora = DateTime(2026, 10, 1, 19);
    await pumpApp(tester, clock: () => agora);

    // A Pessoa 1 chama o grupo todo.
    await signInAs(tester, 'Pessoa 1');
    await tester.tap(find.text('Os 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Chamado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disparar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    // A Pessoa 2 pede para ser chamada de novo em 30 minutos.
    await switchTo(tester, 'Pessoa 2');
    await tester.tap(find.text('Pessoa 1 te chamou pra jogar'));
    // A tela cheia pulsa sem parar: pumpAndSettle nunca terminaria nela.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Me chama daqui a pouco'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Te chamo de novo daqui a quanto?'), findsOneWidget);
    await tester.tap(find.text('30 min'));
    await tester.pumpAndSettle();

    // O aviso sai da lista, e o card diz quando o Chamado volta.
    expect(find.text('Pessoa 1 te chamou pra jogar'), findsNothing);
    await tester.tap(find.text('Os 3'));
    await tester.pumpAndSettle();
    expect(
      find.text('Me chama daqui a pouco · de novo às 19:30'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    // Cinco minutos de silêncio da Pessoa 3: o Chamado toca de novo para ela.
    agora = DateTime(2026, 10, 1, 19, 5);
    await switchTo(tester, 'Pessoa 3');
    expect(find.text('Pessoa 1 te chamou pra jogar'), findsOneWidget);
    await tester.tap(find.text('Os 3'));
    await tester.pumpAndSettle();
    expect(
      find.text('Tocou de novo às 19:05, para quem não respondeu'),
      findsOneWidget,
    );

    // Na hora pedida, o Chamado volta a esperar a Pessoa 2 — aqui o relógio
    // anda na resposta da Pessoa 3, que é quem faz o app ler de novo.
    agora = DateTime(2026, 10, 1, 19, 30);
    await tester.tap(find.text('Hoje não'));
    await tester.pumpAndSettle();
    expect(find.text('aguardando…'), findsOneWidget);
    expect(find.text('aberto'), findsOneWidget);

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    await switchTo(tester, 'Pessoa 2');
    expect(find.text('Pessoa 1 te chamou pra jogar'), findsOneWidget);
  });

  testWidgets('sem respostas próprias, o perfil explica como criar', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'Pessoa 3');
    await tester.tap(find.byTooltip('Meu perfil'));
    await tester.pumpAndSettle();

    expect(find.text('Sem nome ainda'), findsOneWidget);

    // Nome vazio é recusado com aviso, sem mudar nada.
    await tester.tap(find.text('Salvar nome'));
    await tester.pumpAndSettle();
    expect(find.text('O nome precisa ter de 1 a 24 letras.'), findsOneWidget);
    expect(find.text('Sem nome ainda'), findsOneWidget);

    // As respostas ficam no fim da tela, depois do placar, da aparência e do
    // som do Chamado.
    await scrollTo(
      tester,
      find.textContaining('Nenhuma ainda'),
      scrollable: frontList,
    );
    expect(find.textContaining('Nenhuma ainda'), findsOneWidget);
  });
}
