import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/domain/do_dia.dart';
import 'package:sale/state/providers.dart';

import 'helpers.dart';

void main() {
  group('o dia da disputa', () {
    test('vira às 6h, não à meia-noite', () {
      expect(diaDoDestaque(DateTime(2026, 10, 6, 2)), DateTime(2026, 10, 5));
      expect(
        diaDoDestaque(DateTime(2026, 10, 6, 5, 59)),
        DateTime(2026, 10, 5),
      );
      expect(diaDoDestaque(DateTime(2026, 10, 6, 6)), DateTime(2026, 10, 6));
    });
  });

  group('a do dia no repositório', () {
    late DateTime agora;
    late MemoryRepository repo;

    setUp(() {
      agora = DateTime(2026, 10, 5, 20);
      repo = MemoryRepository(clock: () => agora);
    });

    Future<String> manda(String texto, {String autor = 'p1'}) async {
      await repo.sendText(
        conversationId: 'grupo',
        authorId: autor,
        text: texto,
      );
      return (await repo.watchMessages('grupo').first).last.id;
    }

    Future<DoDia> doDia() => repo.watchDoDia('grupo').first;

    test('indica, vota, e cada um tem um voto que pode trocar', () async {
      final a = await manda('frase A');
      final b = await manda('frase B');
      await repo.nominate(messageId: a, userId: 'p2');
      await repo.nominate(messageId: b, userId: 'p3');
      await repo.vote(messageId: a, userId: 'p2');
      await repo.vote(messageId: a, userId: 'p3');
      await repo.vote(messageId: b, userId: 'p3');
      final hoje = await doDia();
      expect(hoje.indicadas.keys, [a, b]);
      expect(hoje.votosDe(a), 1);
      expect(hoje.votosDe(b), 1);
    });

    test('só a conversa do grupo, e só o que foi de hoje', () async {
      await repo.sendText(
        conversationId: 'p1-p2',
        authorId: 'p1',
        text: 'só nós',
      );
      final aDois = (await repo.watchMessages('p1-p2').first).single.id;
      await expectLater(
        repo.nominate(messageId: aDois, userId: 'p1'),
        throwsStateError,
      );

      final ontem = await manda('de ontem');
      agora = agora.add(const Duration(days: 1));
      await expectLater(
        repo.nominate(messageId: ontem, userId: 'p1'),
        throwsStateError,
      );
    });

    test('quando o dia vira, a mais votada vai para o Hall', () async {
      final a = await manda('frase A');
      final b = await manda('frase B');
      await repo.nominate(messageId: a, userId: 'p1');
      await repo.nominate(messageId: b, userId: 'p1');
      await repo.vote(messageId: b, userId: 'p2');
      await repo.vote(messageId: b, userId: 'p3');
      await repo.vote(messageId: a, userId: 'p1');

      agora = DateTime(2026, 10, 6, 7);
      final amanha = await doDia();
      expect(amanha.hoje, DateTime(2026, 10, 6));
      expect(amanha.indicadas, isEmpty);
      expect(amanha.hall.single.messageId, b);
      expect(amanha.hall.single.votos, 2);
      expect(amanha.hall.single.dia, DateTime(2026, 10, 5));
      await expectLater(
        repo.vote(messageId: a, userId: 'p2'),
        throwsStateError,
      );
    });

    test('empate vai para a de mais reações, depois para a primeira', () async {
      final a = await manda('frase A');
      final b = await manda('frase B');
      await repo.nominate(messageId: a, userId: 'p1');
      await repo.nominate(messageId: b, userId: 'p1');
      await repo.react(messageId: b, userId: 'p2', emoji: '😂');

      agora = DateTime(2026, 10, 6, 7);
      expect((await doDia()).hall.single.messageId, b);
    });

    test('a apagada não ganha', () async {
      final a = await manda('vai sumir');
      final b = await manda('fica');
      await repo.nominate(messageId: a, userId: 'p1');
      await repo.nominate(messageId: b, userId: 'p1');
      await repo.vote(messageId: a, userId: 'p2');
      await repo.deleteMessage(messageId: a, userId: 'p1');

      agora = DateTime(2026, 10, 6, 7);
      expect((await doDia()).hall.single.messageId, b);
    });
  });

  group('telas', () {
    testWidgets('indicar no toque longo e votar pela faixa', (tester) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await container
          .read(repositoryProvider)
          .sendText(
            conversationId: 'grupo',
            authorId: 'p2',
            text: 'a frase do ano',
          );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Os 3'));
      await tester.pumpAndSettle();
      expect(find.textContaining('A do dia ·'), findsNothing);

      await tester.longPress(find.text('a frase do ano'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Indicar para a do dia'));
      await tester.pumpAndSettle();
      expect(find.text('A do dia · 1 indicada'), findsOneWidget);
      expect(find.text('⭐ Indicada · 0 votos'), findsOneWidget);

      await tester.tap(find.text('A do dia · 1 indicada'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Votar'));
      await tester.pumpAndSettle();
      expect(find.text('Seu voto'), findsOneWidget);
    });
  });
}
