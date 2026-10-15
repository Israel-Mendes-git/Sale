import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/state/settings.dart';
import 'package:sale/state/tutorial.dart';

import 'helpers.dart';

const dicaConversas = 'Toque numa conversa para abrir';

void main() {
  testWidgets('a apresentação abre antes das abas, uma vez', (tester) async {
    final c = await pumpApp(tester, tutorial: true);
    await signInAs(tester, 'Pessoa 1');

    expect(find.text('Bem-vindo ao Sale?'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    for (final titulo in ['O Chamado', 'Três abas', 'Segure para mais']) {
      await tester.tap(find.text('Próximo'));
      await tester.pumpAndSettle();
      expect(find.text(titulo), findsOneWidget);
    }
    await tester.tap(find.text('Começar'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(c.read(settingsStoreProvider).read(Tutorial.chave), 'boasVindas');
  });

  testWidgets('"Pular" vai direto para as abas', (tester) async {
    await pumpApp(tester, tutorial: true);
    await signInAs(tester, 'Pessoa 1');

    await tester.tap(find.text('Pular'));
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.textContaining(dicaConversas), findsOneWidget);
  });

  testWidgets('a dica some no "Entendi" e não volta', (tester) async {
    final c = await pumpApp(tester, tutorial: true);
    await c.read(tutorialProvider.notifier).marcar(Dica.boasVindas);
    await signInAs(tester, 'Pessoa 1');

    expect(find.textContaining(dicaConversas), findsOneWidget);
    await tester.tap(find.text('Entendi'));
    await tester.pumpAndSettle();
    expect(find.textContaining(dicaConversas), findsNothing);

    // A semana tem a dela, que ainda não foi vista.
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Seus horários'), findsWidgets);
    expect(find.text('Entendi'), findsOneWidget);

    await tester.tap(find.text('Conversas'));
    await tester.pumpAndSettle();
    expect(find.textContaining(dicaConversas), findsNothing);
  });

  testWidgets('"Como usar" reabre a apresentação e traz as dicas de volta', (
    tester,
  ) async {
    await pumpApp(tester);
    await signInAs(tester, 'Pessoa 1');
    expect(find.textContaining(dicaConversas), findsNothing);

    await tester.tap(find.byTooltip('Meu perfil'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Como usar'), scrollable: frontList);
    await tester.tap(find.text('Como usar'));
    await tester.pumpAndSettle();

    expect(find.text('Bem-vindo ao Sale?'), findsOneWidget);
    await tester.tap(find.text('Pular'));
    await tester.pumpAndSettle();

    // De volta ao perfil, e não à apresentação no lugar das abas.
    expect(find.text('Meu perfil'), findsOneWidget);
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.textContaining(dicaConversas), findsOneWidget);
  });

  test('ignora o que não reconhece no que foi salvo', () async {
    final settings = MemorySettingsStore();
    await settings.write(Tutorial.chave, 'chat,coisa-velha,,jogos');
    final c = ProviderContainer(
      overrides: [settingsStoreProvider.overrideWithValue(settings)],
    );
    addTearDown(c.dispose);
    expect(c.read(tutorialProvider), {Dica.chat, Dica.jogos});
  });
}
