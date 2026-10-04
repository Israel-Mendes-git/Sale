import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/domain/models.dart';
import 'package:sale/state/providers.dart';

import 'helpers.dart';

void main() {
  group('a resposta citada', () {
    late MemoryRepository repo;

    setUp(() => repo = MemoryRepository());

    Future<List<Message>> mensagens(String conversa) =>
        repo.watchMessages(conversa).first;

    test('aponta para a mensagem citada', () async {
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p1',
        text: 'quem vem?',
      );
      final pergunta = (await mensagens('grupo')).single;
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p2',
        text: 'eu',
        replyTo: pergunta.id,
      );
      final resposta = (await mensagens('grupo')).last;
      expect(resposta.replyTo, pergunta.id);
    });

    test('a imagem também cita', () async {
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p1',
        text: 'manda o print',
      );
      final pedido = (await mensagens('grupo')).single;
      await repo.sendImage(
        conversationId: 'grupo',
        authorId: 'p2',
        bytes: Uint8List(8),
        fileName: 'print.png',
        replyTo: pedido.id,
      );
      expect((await mensagens('grupo')).last.replyTo, pedido.id);
    });

    test('citar de outra conversa é recusado', () async {
      await repo.sendText(
        conversationId: 'p1-p2',
        authorId: 'p1',
        text: 'só nós dois',
      );
      final reservada = (await mensagens('p1-p2')).single;
      await expectLater(
        repo.sendText(
          conversationId: 'grupo',
          authorId: 'p1',
          text: 'citando de fora',
          replyTo: reservada.id,
        ),
        throwsArgumentError,
      );
    });

    test('citar mensagem que não existe é recusado', () async {
      await expectLater(
        repo.sendText(
          conversationId: 'grupo',
          authorId: 'p1',
          text: 'citando o nada',
          replyTo: 'msg-que-não-existe',
        ),
        throwsArgumentError,
      );
    });
  });

  group('telas', () {
    testWidgets('responder cita a mensagem na bolha', (tester) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');

      await container
          .read(repositoryProvider)
          .sendText(
            conversationId: 'p1-p2',
            authorId: 'p2',
            text: 'bora hoje?',
          );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pessoa 2'));
      await tester.pumpAndSettle();

      // Toque longo na mensagem abre o menu dela.
      await tester.longPress(find.text('bora hoje?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Responder'));
      await tester.pumpAndSettle();

      // A citação fica à vista até a mensagem sair.
      expect(find.text('Respondendo Pessoa 2'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Mensagem'),
        'bora sim',
      );
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();

      expect(find.text('Respondendo Pessoa 2'), findsNothing);
      // A bolha da resposta mostra a citada: o texto dela aparece duas vezes
      // na conversa, na original e na citação.
      expect(find.text('bora sim'), findsOneWidget);
      expect(find.text('bora hoje?'), findsNWidgets(2));
    });

    testWidgets('cancelar a citação deixa a mensagem solta', (tester) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await container
          .read(repositoryProvider)
          .sendText(
            conversationId: 'p1-p2',
            authorId: 'p2',
            text: 'bora hoje?',
          );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pessoa 2'));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('bora hoje?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Responder'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cancelar resposta'));
      await tester.pumpAndSettle();
      expect(find.text('Respondendo Pessoa 2'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'Mensagem'),
        'sem citar',
      );
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();
      expect(find.text('bora hoje?'), findsOneWidget);
    });
  });
}
