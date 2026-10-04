import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/domain/models.dart';
import 'package:sale/state/providers.dart';

import 'helpers.dart';

void main() {
  group('a reação', () {
    late MemoryRepository repo;
    late String mensagemId;

    setUp(() async {
      repo = MemoryRepository();
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p1',
        text: 'ganhei',
      );
      mensagemId = (await repo.watchMessages('grupo').first).single.id;
    });

    Future<Message> mensagem() async =>
        (await repo.watchMessages('grupo').first).single;

    test('fica na mensagem, por pessoa', () async {
      await repo.react(messageId: mensagemId, userId: 'p2', emoji: '🔥');
      await repo.react(messageId: mensagemId, userId: 'p3', emoji: '🔥');
      expect((await mensagem()).reactions, {'p2': '🔥', 'p3': '🔥'});
      expect((await mensagem()).reactionCounts, [('🔥', 2)]);
    });

    test('reagir de novo troca a sua, não empilha', () async {
      await repo.react(messageId: mensagemId, userId: 'p2', emoji: '🔥');
      await repo.react(messageId: mensagemId, userId: 'p2', emoji: '👍');
      expect((await mensagem()).reactions, {'p2': '👍'});
    });

    test('sem emoji, a reação sai', () async {
      await repo.react(messageId: mensagemId, userId: 'p2', emoji: '🔥');
      await repo.react(messageId: mensagemId, userId: 'p2', emoji: null);
      expect((await mensagem()).reactions, isEmpty);
    });

    test('a contagem vem do mais reagido para o menos', () async {
      await repo.react(messageId: mensagemId, userId: 'p1', emoji: '👍');
      await repo.react(messageId: mensagemId, userId: 'p2', emoji: '🔥');
      await repo.react(messageId: mensagemId, userId: 'p3', emoji: '🔥');
      expect((await mensagem()).reactionCounts, [('🔥', 2), ('👍', 1)]);
    });

    test('mensagem que não existe não recebe reação', () async {
      await expectLater(
        repo.react(messageId: 'msg-que-não-existe', userId: 'p2', emoji: '🔥'),
        throwsArgumentError,
      );
    });
  });

  group('telas', () {
    testWidgets('reagir aparece na bolha, e tocar de novo tira', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await container
          .read(repositoryProvider)
          .sendText(
            conversationId: 'p1-p2',
            authorId: 'p2',
            text: 'ganhei de novo',
          );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pessoa 2'));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('ganhei de novo'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reagir com 🔥'));
      await tester.pumpAndSettle();

      // O emoji sozinho na bolha: uma reação não precisa de contagem.
      expect(find.text('🔥'), findsOneWidget);

      await tester.tap(find.text('🔥'));
      await tester.pumpAndSettle();
      expect(find.text('🔥'), findsNothing);
    });

    testWidgets('a reação de quem já reagiu conta junto', (tester) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      final repo = container.read(repositoryProvider);
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p2',
        text: 'olha isso',
      );
      // Fora do relógio falso do teste: esperar o stream direto trava o
      // toque seguinte (ver `calendarOf` em helpers.dart).
      final mensagem = (await tester.runAsync(
        () => repo.watchMessages('grupo').first,
      ))!.single;
      await repo.react(messageId: mensagem.id, userId: 'p3', emoji: '😂');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Os 3'));
      await tester.pumpAndSettle();
      expect(find.text('😂'), findsOneWidget);

      // A Pessoa 1 reage com o mesmo: agora são duas.
      await tester.tap(find.text('😂'));
      await tester.pumpAndSettle();
      expect(find.text('😂 2'), findsOneWidget);
    });
  });
}
