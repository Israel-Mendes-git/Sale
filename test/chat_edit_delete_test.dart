import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/domain/models.dart';
import 'package:sale/state/providers.dart';

import 'helpers.dart';

void main() {
  group('editar e apagar', () {
    late MemoryRepository repo;

    setUp(() => repo = MemoryRepository());

    Future<Message> unica() async =>
        (await repo.watchMessages('grupo').first).single;

    test('editar troca o texto e marca como editada', () async {
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p1',
        text: 'bora hj',
      );
      expect((await unica()).isEdited, isFalse);
      await repo.editMessage(
        messageId: (await unica()).id,
        userId: 'p1',
        text: 'bora hoje',
      );
      final editada = await unica();
      expect(editada.text, 'bora hoje');
      expect(editada.isEdited, isTrue);
    });

    test('só o autor edita', () async {
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p1',
        text: 'minha',
      );
      await expectLater(
        repo.editMessage(
          messageId: (await unica()).id,
          userId: 'p2',
          text: 'tua',
        ),
        throwsStateError,
      );
    });

    test('editar para vazio não vale', () async {
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p1',
        text: 'algo',
      );
      await expectLater(
        repo.editMessage(
          messageId: (await unica()).id,
          userId: 'p1',
          text: '   ',
        ),
        throwsArgumentError,
      );
    });

    test('apagar vira lápide, sem texto nem reações', () async {
      await repo.sendText(conversationId: 'grupo', authorId: 'p1', text: 'ops');
      final m = await unica();
      await repo.react(messageId: m.id, userId: 'p2', emoji: '🔥');
      await repo.deleteMessage(messageId: m.id, userId: 'p1');
      final apagada = await unica();
      expect(apagada.isDeleted, isTrue);
      expect(apagada.text, isNull);
      expect(apagada.reactions, isEmpty);
    });

    test('só o autor apaga', () async {
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p1',
        text: 'minha',
      );
      await expectLater(
        repo.deleteMessage(messageId: (await unica()).id, userId: 'p2'),
        throwsStateError,
      );
    });

    test('apagar a citada tira a citação de quem respondeu', () async {
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p1',
        text: 'quem vem?',
      );
      final pergunta = await unica();
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p2',
        text: 'eu',
        replyTo: pergunta.id,
      );
      await repo.deleteMessage(messageId: pergunta.id, userId: 'p1');
      final msgs = await repo.watchMessages('grupo').first;
      expect(msgs.firstWhere((m) => m.text == 'eu').replyTo, isNull);
    });
  });

  group('telas', () {
    testWidgets('apagar pela conversa mostra a lápide', (tester) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await container
          .read(repositoryProvider)
          .sendText(
            conversationId: 'p1-p2',
            authorId: 'p1',
            text: 'vou apagar essa',
          );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pessoa 2'));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('vou apagar essa'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apagar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Apagar'));
      await tester.pumpAndSettle();

      expect(find.text('vou apagar essa'), findsNothing);
      expect(find.text('Mensagem apagada'), findsOneWidget);
    });

    testWidgets('editar pela conversa troca o texto e marca editado', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await container
          .read(repositoryProvider)
          .sendText(conversationId: 'p1-p2', authorId: 'p1', text: 'bora hj');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pessoa 2'));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('bora hj'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();

      // A edição acontece no próprio campo de digitar, como no WhatsApp.
      expect(find.text('Editando mensagem'), findsOneWidget);
      final campo = find.widgetWithText(TextField, 'Mensagem');
      expect(tester.widget<TextField>(campo).controller!.text, 'bora hj');
      await tester.enterText(campo, 'bora hoje');
      await tester.pump();
      await tester.tap(find.byTooltip('Salvar edição'));
      await tester.pumpAndSettle();

      expect(find.text('Editando mensagem'), findsNothing);
      expect(find.text('bora hoje'), findsOneWidget);
      expect(find.text('editado'), findsOneWidget);
      // O campo volta vazio: a edição não deixou rascunho.
      expect(tester.widget<TextField>(campo).controller!.text, isEmpty);
    });

    testWidgets('desistir da edição devolve o rascunho que estava no campo', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await container
          .read(repositoryProvider)
          .sendText(conversationId: 'p1-p2', authorId: 'p1', text: 'bora hj');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pessoa 2'));
      await tester.pumpAndSettle();

      final campo = find.widgetWithText(TextField, 'Mensagem');
      await tester.enterText(campo, 'meio escrito');
      await tester.pump();
      await tester.longPress(find.text('bora hj'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cancelar edição'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(campo).controller!.text, 'meio escrito');
      expect(find.text('editado'), findsNothing);
    });
  });
}
