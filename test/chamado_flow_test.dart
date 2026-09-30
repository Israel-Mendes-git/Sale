import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/main.dart';

/// Fluxo completo nas telas: Israel dispara, Beto recebe e responde.
void main() {
  testWidgets('Chamado vai do Israel ao Beto e volta com a resposta', (
    tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: SaleApp()));

    // Israel entra e abre o grupo.
    await tester.tap(find.text('Israel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Os 3'));
    await tester.pumpAndSettle();

    // Dispara um Chamado só para o Beto.
    await tester.tap(find.byTooltip('Chamado'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Caio'));
    await tester.enterText(find.widgetWithText(TextField, 'Jogo'), 'Valorant');
    await tester.tap(find.text('Disparar'));
    await tester.pumpAndSettle();

    expect(find.text('CHAMADO · Valorant'), findsOneWidget);
    expect(find.text('aguardando…'), findsOneWidget);

    // Volta e troca para o Beto.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Trocar usuário (desenvolvimento)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrar como Beto'));
    await tester.pumpAndSettle();

    // O aviso aparece e abre a tela cheia.
    expect(find.text('Israel te chamou pra jogar'), findsOneWidget);
    // A tela cheia pulsa sem parar: pumpAndSettle nunca terminaria nela.
    await tester.tap(find.text('Israel te chamou pra jogar'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // "Tô jantando" pergunta o tempo antes de responder.
    await tester.tap(find.text('🍝 Tô jantando'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('30 min'));
    await tester.pumpAndSettle();

    // Voltou para a lista, sem o aviso.
    expect(find.text('Israel te chamou pra jogar'), findsNothing);

    // O card no grupo mostra a resposta.
    await tester.tap(find.text('Os 3'));
    await tester.pumpAndSettle();
    expect(find.textContaining('🍝 Tô jantando · chega ~'), findsOneWidget);
    expect(find.text('respondido'), findsOneWidget);
  });
}
