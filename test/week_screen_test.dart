import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/domain/calendar.dart';

import 'helpers.dart';

/// Segunda, 28/09/2026, 10h: a quinta do encontro (01/10) ainda está por vir.
final monday10h = DateTime(2026, 9, 28, 10);

Future<void> openWeek(WidgetTester tester) async {
  await signInAs(tester, 'Pessoa 1');
  await tester.tap(find.text('Semana'));
  await tester.pumpAndSettle();
}

Future<void> scrollTo(
  WidgetTester tester,
  Finder finder, {
  bool up = false,
}) async {
  await tester.scrollUntilVisible(
    finder,
    up ? -200 : 200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'mostra o encontro, quando todos estão livres e os meus horários',
    (tester) async {
      await pumpApp(tester, now: monday10h);
      await openWeek(tester);

      expect(find.text('28/09 – 04/10'), findsOneWidget);
      expect(find.text('Quinta, 01/10 · 21:00'), findsOneWidget);
      expect(find.text('Toda quinta às 21:00'), findsOneWidget);
      expect(find.text('Pessoa 2: ⏳ ainda não respondeu'), findsOneWidget);

      await scrollTo(tester, find.text('Quando todo mundo está livre'));
      expect(find.text('21:00 às 23:00'), findsOneWidget);
      // Sábado: duas janelas, porque a Pessoa 2 sai das 20h às 21h.
      expect(find.text('16:00 às 20:00'), findsOneWidget);
      expect(find.text('21:00 às 22:00'), findsOneWidget);

      await scrollTo(tester, find.text('Editar meus horários'));
      expect(find.text('qui: 19:00 às 24:00'), findsOneWidget);
    },
  );

  testWidgets('dia a dia resume e abre o horário de cada um', (tester) async {
    await pumpApp(tester, now: monday10h);
    await openWeek(tester);

    // A quinta também aparece em "todos livres"; o resumo é só do dia a dia.
    final resumo = find.text('encontro 21:00 · todos livres 21:00 às 23:00');
    await scrollTo(tester, resumo);
    expect(find.text('Segunda, 28/09 · hoje'), findsOneWidget);

    await tester.tap(resumo);
    await tester.pumpAndSettle();
    expect(find.text('Pessoa 2: livre 21:00 às 24:00'), findsOneWidget);
    expect(find.text('Você: livre 19:00 às 24:00'), findsOneWidget);
  });

  testWidgets('confirma presença e "não vou" pede o motivo', (tester) async {
    final c = await pumpApp(tester, now: monday10h);
    await openWeek(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Vou'));
    await tester.pumpAndSettle();
    var rsvp = (await calendarOf(tester, c, 'p1')).rsvps.single;
    expect(rsvp.status, RsvpStatus.going);
    expect(rsvp.date, DateTime(2026, 10, 1));

    // Fechar o diálogo sem escolher não muda a resposta.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Não vou'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(
      (await calendarOf(tester, c, 'p1')).rsvps.single.status,
      RsvpStatus.going,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Não vou'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'plantão');
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();
    rsvp = (await calendarOf(tester, c, 'p1')).rsvps.single;
    expect(rsvp.status, RsvpStatus.notGoing);
    expect(rsvp.reason, 'plantão');
  });

  testWidgets('pular a semana tem botão visível e dá para desfazer', (
    tester,
  ) async {
    final c = await pumpApp(tester, now: monday10h);
    await openWeek(tester);

    await scrollTo(tester, find.text('Pular esta semana'));
    await tester.tap(find.text('Pular esta semana'));
    await tester.pumpAndSettle();
    // O cartão encolhe e o topo sai da tela: volta para ele.
    await scrollTo(tester, find.text('Pulado nesta semana.'), up: true);

    expect(find.text('Pulado nesta semana.'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Vou'), findsNothing);
    expect(
      (await calendarOf(tester, c, 'p1')).exceptions.single.skipped,
      isTrue,
    );

    await tester.tap(find.text('Desfazer'));
    await tester.pumpAndSettle();
    expect(find.text('Pulado nesta semana.'), findsNothing);
    expect((await calendarOf(tester, c, 'p1')).exceptions, isEmpty);
  });

  testWidgets('"Chamar" agenda um Chamado para o grupo', (tester) async {
    final c = await pumpApp(tester, now: monday10h);
    await openWeek(tester);

    final chamar = find.byTooltip('Agendar Chamado qui 01/10 21:00–23:00');
    await scrollTo(tester, chamar);
    await tester.tap(chamar);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Chamado agendado: qui 01/10 às 21:00'), findsOneWidget);
    final chamado = (await calendarOf(
      tester,
      c,
      'p1',
    )).scheduledChamados.single;
    expect(chamado.scheduledFor, DateTime(2026, 10, 1, 21));
    expect(chamado.targetIds, unorderedEquals(['p2', 'p3']));
    expect(chamado.conversationId, 'grupo');
  });

  testWidgets('dia que já passou não deixa confirmar nem chamar', (
    tester,
  ) async {
    // Sexta: a quinta do encontro já passou.
    await pumpApp(tester, now: DateTime(2026, 10, 2, 10));
    await openWeek(tester);

    expect(find.text('Já passou.'), findsOneWidget);
    final vou = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Vou'),
    );
    expect(vou.onSelected, isNull);
    expect(find.text('Pular esta semana'), findsNothing);

    await scrollTo(tester, find.text('Quando todo mundo está livre'));
    expect(
      find.byTooltip('Agendar Chamado qui 01/10 21:00–23:00'),
      findsNothing,
    );
    expect(find.text('16:00 às 20:00'), findsOneWidget);
  });

  testWidgets('sem encontro fixo, oferece marcar um', (tester) async {
    final c = await pumpApp(tester, now: monday10h);
    await openWeek(tester);

    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remover encontro'));
    await tester.pumpAndSettle();
    expect(find.text('Marcar encontro fixo'), findsOneWidget);
    expect((await calendarOf(tester, c, 'p1')).meetings, isEmpty);

    await tester.tap(find.text('Marcar encontro fixo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'sex'));
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();
    expect(find.text('Sexta, 02/10 · 21:00'), findsOneWidget);
  });

  testWidgets('marca um horário livre novo na disponibilidade', (tester) async {
    final c = await pumpApp(tester, now: monday10h);
    await openWeek(tester);

    await scrollTo(tester, find.text('Editar meus horários'));
    await tester.tap(find.text('Editar meus horários'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Adicionar horário em terça'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // início: 20:00
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK')); // fim: 23:00
    await tester.pumpAndSettle();

    expect(find.text('20:00–23:00'), findsOneWidget);
    final terca = (await calendarOf(
      tester,
      c,
      'p1',
    )).availability.where((a) => a.userId == 'p1' && a.weekday == 2);
    expect(terca.single.range, const TimeRange(20 * 60, 23 * 60));
  });
}
