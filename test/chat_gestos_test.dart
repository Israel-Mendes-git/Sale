import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/domain/models.dart';
import 'package:sale/state/providers.dart';

import 'helpers.dart';

/// Pessoa 1 abre a conversa com a Pessoa 2 depois de [antes] chegar nela.
Future<ProviderContainer> abrirConversa(
  WidgetTester tester, {
  Future<void> Function(ProviderContainer c)? antes,
}) async {
  final container = await pumpApp(tester);
  await signInAs(tester, 'Pessoa 1');
  if (antes != null) await antes(container);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Pessoa 2'));
  await tester.pumpAndSettle();
  return container;
}

Future<void> manda(
  ProviderContainer c,
  String texto, {
  String autor = 'p2',
  String? replyTo,
}) => c
    .read(repositoryProvider)
    .sendText(
      conversationId: 'p1-p2',
      authorId: autor,
      text: texto,
      replyTo: replyTo,
    );

Future<List<Message>> mensagens(
  WidgetTester tester,
  ProviderContainer c,
) async => (await tester.runAsync(
  () => c.read(repositoryProvider).watchMessages('p1-p2').first,
))!;

final campo = find.widgetWithText(TextField, 'Mensagem');

void main() {
  testWidgets('arrastar a bolha para o lado responde a ela', (tester) async {
    await abrirConversa(tester, antes: (c) => manda(c, 'bora hoje?'));

    await tester.drag(find.text('bora hoje?'), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(find.text('Respondendo Pessoa 2'), findsOneWidget);
  });

  testWidgets('arrastar só um pouco não responde', (tester) async {
    await abrirConversa(tester, antes: (c) => manda(c, 'bora hoje?'));

    await tester.drag(find.text('bora hoje?'), const Offset(40, 0));
    await tester.pumpAndSettle();
    expect(find.text('Respondendo Pessoa 2'), findsNothing);
  });

  testWidgets('dois toques reagem com ❤️; dois de novo tiram', (tester) async {
    final c = await abrirConversa(tester, antes: (c) => manda(c, 'ganhamos'));

    final bolha = find.text('ganhamos');
    await tester.tap(bolha);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(bolha);
    await tester.pumpAndSettle();
    expect((await mensagens(tester, c)).single.reactions, {'p1': reacaoRapida});

    await tester.tap(bolha);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(bolha);
    await tester.pumpAndSettle();
    expect((await mensagens(tester, c)).single.reactions, isEmpty);
  });

  testWidgets('um toque só não reage', (tester) async {
    final c = await abrirConversa(tester, antes: (c) => manda(c, 'ganhamos'));

    await tester.tap(find.text('ganhamos'));
    await tester.pumpAndSettle();
    expect((await mensagens(tester, c)).single.reactions, isEmpty);
  });

  testWidgets('copiar leva o texto para a área de transferência', (
    tester,
  ) async {
    String? copiado;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiado = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await abrirConversa(tester, antes: (c) => manda(c, 'ip 10.0.0.7'));

    await tester.longPress(find.text('ip 10.0.0.7'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copiar'));
    await tester.pumpAndSettle();
    expect(copiado, 'ip 10.0.0.7');
    expect(find.text('Mensagem copiada.'), findsOneWidget);
  });

  testWidgets('o rascunho fica na conversa e aparece na lista', (tester) async {
    await abrirConversa(tester);

    await tester.enterText(campo, 'meio escrito');
    await tester.pump();
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Rascunho: meio escrito', findRichText: true),
      findsOneWidget,
    );

    await tester.tap(find.text('Pessoa 2'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(campo).controller!.text, 'meio escrito');

    // Mandou, o rascunho some.
    await tester.tap(find.byTooltip('Enviar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Rascunho', findRichText: true), findsNothing);
  });

  testWidgets('o dia aparece entre as mensagens', (tester) async {
    await abrirConversa(tester, antes: (c) => manda(c, 'oi'));
    expect(find.text('Hoje'), findsOneWidget);
  });

  testWidgets('abrir com mensagens novas mostra a faixa', (tester) async {
    final c = await abrirConversa(tester, antes: (c) => manda(c, 'vista'));
    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();

    await manda(c, 'nova 1');
    await manda(c, 'nova 2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pessoa 2'));
    await tester.pumpAndSettle();
    expect(find.text('2 mensagens novas'), findsOneWidget);
  });

  group('ir até a mensagem', () {
    /// A primeira lá em cima, 30 no meio, e a última citando a primeira.
    Future<void> conversaComprida(
      WidgetTester tester,
      ProviderContainer c,
    ) async {
      await manda(c, 'a primeira de todas');
      final primeira = (await mensagens(tester, c)).single;
      for (var i = 0; i < 30; i++) {
        await manda(c, 'recheio $i');
      }
      await manda(c, 'respondendo a primeira', replyTo: primeira.id);
    }

    testWidgets('tocar na citação rola até a citada', (tester) async {
      await abrirConversa(tester, antes: (c) => conversaComprida(tester, c));
      final original = find.text('a primeira de todas');
      // Só a citação está montada, embaixo; a original está longe.
      expect(original, findsOneWidget);
      expect(find.text('recheio 29').hitTestable(), findsOneWidget);

      await tester.tap(original);
      await tester.pumpAndSettle();
      expect(find.text('recheio 29').hitTestable(), findsNothing);
      expect(find.text('recheio 0').hitTestable(), findsOneWidget);

      // Lá em cima, o botão de descer leva de volta ao fim.
      await tester.tap(find.byTooltip('Descer para o fim'));
      await tester.pumpAndSettle();
      expect(find.text('recheio 29').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Descer para o fim'), findsNothing);
    });

    testWidgets('tocar no resultado da busca rola até a mensagem', (
      tester,
    ) async {
      await abrirConversa(tester, antes: (c) => conversaComprida(tester, c));

      await tester.tap(find.byTooltip('Buscar na conversa'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'recheio 3');
      await tester.pumpAndSettle();
      // "recheio 3" e "recheio 30" não existem juntos: 0..29.
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();

      expect(find.text('recheio 3').hitTestable(), findsOneWidget);
      expect(find.text('recheio 29').hitTestable(), findsNothing);
    });
  });

  testWidgets('segurar uma reação mostra quem reagiu', (tester) async {
    final c = await abrirConversa(
      tester,
      antes: (c) async {
        await manda(c, 'ganhamos');
        final m = (await mensagens(tester, c)).single;
        await c
            .read(repositoryProvider)
            .react(messageId: m.id, userId: 'p2', emoji: '🔥');
      },
    );
    expect(c, isNotNull);

    await tester.longPress(find.text('🔥'));
    await tester.pumpAndSettle();
    expect(find.text('Pessoa 2'), findsWidgets);
    expect(find.widgetWithText(ListTile, 'Pessoa 2'), findsOneWidget);
  });

  testWidgets('no grupo, "Quem viu" separa quem leu de quem só recebeu', (
    tester,
  ) async {
    final container = await pumpApp(tester);
    await signInAs(tester, 'Pessoa 1');
    final repo = container.read(repositoryProvider);
    await repo.sendText(
      conversationId: 'grupo',
      authorId: 'p1',
      text: 'quem vem?',
    );
    await repo.markRead(conversationId: 'grupo', userId: 'p2');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Os 3'));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('quem vem?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quem viu'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ListTile, 'Lida por'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Lida por'),
        matching: find.text('Pessoa 2'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Lida por'),
        matching: find.text('Pessoa 3'),
      ),
      findsNothing,
    );
  });
}
