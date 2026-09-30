import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/domain/calendar.dart';
import 'package:sale/main.dart';
import 'package:sale/state/providers.dart';

/// Segunda, 28/09/2026, 10h: a quinta do encontro (01/10) ainda está por vir.
final fixedNow = DateTime(2026, 9, 28, 10);

Future<ProviderContainer> openWeek(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [clockProvider.overrideWithValue(() => fixedNow)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const SaleApp()),
  );
  await tester.tap(find.text('Israel'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Semana'));
  await tester.pumpAndSettle();
  return container;
}

/// Lê o repositório fora do relógio falso do teste: esperar o stream
/// direto dentro do testWidgets trava o toque seguinte.
Future<CalendarData> calendarOf(
  WidgetTester tester,
  ProviderContainer c,
  String userId,
) async => (await tester.runAsync(
  () => c.read(repositoryProvider).watchCalendar(userId).first,
))!;

Future<void> showThursday(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byTooltip('Todos livres 21:00–23:00'),
    200,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('mostra a semana, o encontro fixo e quem está livre junto', (
    tester,
  ) async {
    await openWeek(tester);

    expect(find.text('28/09 – 04/10'), findsOneWidget);
    expect(find.text('segunda'), findsOneWidget);
    expect(find.text('hoje'), findsOneWidget);

    await showThursday(tester);
    expect(find.text('Encontro fixo · 21:00'), findsOneWidget);
    // Sábado: dois blocos, porque o Beto sai das 20h às 21h.
    await tester.scrollUntilVisible(
      find.byTooltip('Todos livres 21:00–22:00'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byTooltip('Todos livres 16:00–20:00'), findsOneWidget);
  });

  testWidgets('confirma presença e "não vou" pede o motivo', (tester) async {
    final c = await openWeek(tester);
    await showThursday(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Vou'));
    await tester.pumpAndSettle();
    var rsvp = (await calendarOf(tester, c, 'israel')).rsvps.single;
    expect(rsvp.status, RsvpStatus.going);
    expect(rsvp.date, DateTime(2026, 10, 1));

    // Fechar o diálogo sem escolher não muda a resposta.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Não vou'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(
      (await calendarOf(tester, c, 'israel')).rsvps.single.status,
      RsvpStatus.going,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Não vou'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'plantão');
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();
    rsvp = (await calendarOf(tester, c, 'israel')).rsvps.single;
    expect(rsvp.status, RsvpStatus.notGoing);
    expect(rsvp.reason, 'plantão');
  });

  testWidgets('pular a semana risca o encontro e esconde a confirmação', (
    tester,
  ) async {
    final c = await openWeek(tester);
    await showThursday(tester);

    await tester.ensureVisible(find.byTooltip('Opções do encontro'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Opções do encontro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pular esta semana'));
    await tester.pumpAndSettle();

    expect(find.text('pulado esta semana'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Vou'), findsNothing);
    expect(
      (await calendarOf(tester, c, 'israel')).exceptions.single.skipped,
      isTrue,
    );

    await tester.ensureVisible(find.byTooltip('Opções do encontro'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Opções do encontro'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voltar ao normal'));
    await tester.pumpAndSettle();
    expect(find.text('pulado esta semana'), findsNothing);
  });

  testWidgets('tocar no "todos livres" agenda um Chamado para o grupo', (
    tester,
  ) async {
    final c = await openWeek(tester);
    await showThursday(tester);

    await tester.tap(find.byTooltip('Todos livres 21:00–23:00'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.text('Chamado agendado: qui 01/10 às 21:00'), findsOneWidget);
    final chamado = (await calendarOf(
      tester,
      c,
      'israel',
    )).scheduledChamados.single;
    expect(chamado.scheduledFor, DateTime(2026, 10, 1, 21));
    expect(chamado.targetIds, unorderedEquals(['beto', 'caio']));
    expect(chamado.conversationId, 'grupo');
  });

  testWidgets('dia que já passou não deixa agendar nem confirmar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    // Sexta: a quinta do encontro já passou.
    final container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(() => DateTime(2026, 10, 2, 10)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SaleApp()),
    );
    await tester.tap(find.text('Israel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();
    await showThursday(tester);

    final vou = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Vou'),
    );
    expect(vou.onSelected, isNull);
    expect(find.byTooltip('Opções do encontro'), findsNothing);

    await tester.tap(find.byTooltip('Todos livres 21:00–23:00'));
    await tester.pumpAndSettle();
    expect(find.text('OK'), findsNothing);
  });

  testWidgets('marca um horário livre novo na disponibilidade', (tester) async {
    final c = await openWeek(tester);

    await tester.tap(find.byTooltip('Minha disponibilidade'));
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
      'israel',
    )).availability.where((a) => a.userId == 'israel' && a.weekday == 2);
    expect(terca.single.range, const TimeRange(20 * 60, 23 * 60));
  });
}
