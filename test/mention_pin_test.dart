import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/domain/mentions.dart';
import 'package:sale/domain/models.dart';
import 'package:sale/state/providers.dart';
import 'package:sale/ui/format.dart';

import 'helpers.dart';

const _nomes = {'a': 'Ana', 'ap': 'Ana Paula', 'b': 'Bruno'};

void main() {
  group('as menções no texto', () {
    test('acha o nome depois do arroba, sem ligar para a caixa', () {
      expect(quemFoiMencionado('bora @bruno?', _nomes, 'a'), {'b'});
    });

    test('o nome mais longo ganha do mais curto', () {
      expect(quemFoiMencionado('oi @Ana Paula', _nomes, 'b'), {'ap'});
      expect(quemFoiMencionado('oi @Ana', _nomes, 'b'), {'a'});
    });

    test('a menção termina onde termina a palavra', () {
      expect(quemFoiMencionado('@Anabela chegou', _nomes, 'b'), isEmpty);
      expect(quemFoiMencionado('fala@Bruno', _nomes, 'a'), isEmpty);
    });

    test('@todos vale todo mundo, fora quem escreveu', () {
      expect(quemFoiMencionado('@todos hoje?', _nomes, 'a'), {'ap', 'b'});
    });

    test('quem escreve não se menciona', () {
      expect(quemFoiMencionado('eu, @Bruno, vou', _nomes, 'b'), isEmpty);
    });

    test('os trechos ficam onde estão, para destacar', () {
      final achadas = mencoesNoTexto('vem @Bruno e @todos', _nomes);
      expect([for (final m in achadas) m.id], ['b', null]);
      expect(
        'vem @Bruno e @todos'.substring(achadas[0].inicio, achadas[0].fim),
        '@Bruno',
      );
    });

    test('o arroba no fim pede sugestão; terminado, não pede mais', () {
      expect(mencaoEmAndamento('oi @br'), 'br');
      expect(mencaoEmAndamento('oi @'), '');
      expect(mencaoEmAndamento('sem arroba'), isNull);
      expect(mencaoEmAndamento('email@x'), isNull);
      expect(completarMencao('oi @br', 'Bruno'), 'oi @Bruno ');
    });
  });

  group('no repositório', () {
    late MemoryRepository repo;

    setUp(() => repo = MemoryRepository());

    Future<Conversation> grupo() async =>
        (await repo.watchConversations('p1').first).firstWhere(
          (c) => c.id == 'grupo',
        );

    test('a mensagem guarda quem ela menciona', () async {
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p1',
        text: '@Pessoa 2 vem?',
        mentions: {'p2'},
      );
      final m = (await repo.watchMessages('grupo').first).single;
      expect(m.mentions, {'p2'});
    });

    test('fixar põe no topo; desafixar tira', () async {
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p1',
        text: 'IP: 10.0.0.1',
      );
      final m = (await repo.watchMessages('grupo').first).single;
      await repo.pinMessage(conversationId: 'grupo', messageId: m.id);
      expect((await grupo()).pinnedMessageId, m.id);
      await repo.pinMessage(conversationId: 'grupo', messageId: null);
      expect((await grupo()).pinnedMessageId, isNull);
    });

    test('não fixa mensagem de outra conversa', () async {
      await repo.sendText(
        conversationId: 'p1-p2',
        authorId: 'p1',
        text: 'só entre nós',
      );
      final m = (await repo.watchMessages('p1-p2').first).single;
      await expectLater(
        repo.pinMessage(conversationId: 'grupo', messageId: m.id),
        throwsArgumentError,
      );
    });

    test('apagar a fixada tira ela do topo', () async {
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p1',
        text: 'vai sumir',
      );
      final m = (await repo.watchMessages('grupo').first).single;
      await repo.pinMessage(conversationId: 'grupo', messageId: m.id);
      await repo.deleteMessage(messageId: m.id, userId: 'p1');
      expect((await grupo()).pinnedMessageId, isNull);
    });

    test('o recado de voz tem resumo na lista de conversas', () {
      final recado = Message(
        id: 'm',
        conversationId: 'grupo',
        authorId: 'p1',
        createdAt: DateTime(2026, 10, 5),
        attachment: const Attachment(path: 'x', kind: AttachmentKind.audio),
      );
      expect(messageSummary(recado), '🎤 Recado de voz');
    });
  });

  group('telas', () {
    testWidgets('o arroba sugere os nomes, e a menção vai junto', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await tester.tap(find.text('Os 3'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Mensagem'),
        'bora @Pes',
      );
      await tester.pump();
      expect(find.widgetWithText(ActionChip, 'Pessoa 2'), findsOneWidget);
      expect(find.widgetWithText(ActionChip, 'Pessoa 3'), findsOneWidget);

      await tester.tap(find.widgetWithText(ActionChip, 'Pessoa 2'));
      await tester.pump();
      await tester.tap(find.byTooltip('Enviar'));
      await tester.pumpAndSettle();

      final repo = container.read(repositoryProvider);
      final enviada = (await tester.runAsync(
        () => repo.watchMessages('grupo').first,
      ))!.single;
      expect(enviada.text, 'bora @Pessoa 2');
      expect(enviada.mentions, {'p2'});
    });

    testWidgets('a mensagem fixada aparece no topo da conversa', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await container
          .read(repositoryProvider)
          .sendText(
            conversationId: 'grupo',
            authorId: 'p2',
            text: 'servidor: 10.0.0.1',
          );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Os 3'));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('servidor: 10.0.0.1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fixar no topo'));
      await tester.pumpAndSettle();
      expect(find.text('Fixada · Pessoa 2'), findsOneWidget);

      await tester.tap(find.byTooltip('Desafixar'));
      await tester.pumpAndSettle();
      expect(find.text('Fixada · Pessoa 2'), findsNothing);
    });
  });
}
