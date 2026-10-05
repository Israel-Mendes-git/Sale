import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/domain/models.dart';
import 'package:sale/state/providers.dart';
import 'package:sale/ui/format.dart';

import 'helpers.dart';

const _dupla = Conversation(
  id: 'p1-p2',
  kind: ConversationKind.direct,
  memberIds: ['p1', 'p2'],
);
const _grupo = Conversation(
  id: 'grupo',
  kind: ConversationKind.group,
  memberIds: ['p1', 'p2', 'p3'],
  name: 'Os 3',
);

void main() {
  group('a presença no repositório', () {
    late MemoryRepository repo;

    setUp(() => repo = MemoryRepository());

    test('app na frente entra no online; no fundo, sai', () async {
      await repo.setPresent(userId: 'p2', present: true);
      expect(await repo.watchOnline('p1').first, {'p2'});
      await repo.setPresent(userId: 'p2', present: false);
      expect(await repo.watchOnline('p1').first, isEmpty);
    });

    test('digitando e gravando ficam por conversa, e somem ao parar', () async {
      await repo.setActivity(
        conversationId: 'grupo',
        userId: 'p2',
        activity: ChatActivity.typing,
      );
      expect(await repo.watchActivity('grupo').first, {
        'p2': ChatActivity.typing,
      });
      expect(await repo.watchActivity('p1-p2').first, isEmpty);
      await repo.setActivity(conversationId: 'grupo', userId: 'p2');
      expect(await repo.watchActivity('grupo').first, isEmpty);
    });
  });

  group('a linha embaixo do nome da conversa', () {
    final repo = MemoryRepository();

    String status(
      Conversation c, {
      Map<String, ChatActivity> activity = const {},
      Set<String> online = const {},
    }) => conversationStatus(repo, c, 'p1', activity: activity, online: online);

    test('a dois, diz só o que o outro faz', () {
      expect(
        status(_dupla, activity: {'p2': ChatActivity.typing}),
        'digitando…',
      );
      expect(
        status(_dupla, activity: {'p2': ChatActivity.recording}),
        'gravando áudio…',
      );
      expect(status(_dupla, online: {'p2'}), 'online');
      expect(status(_dupla), '');
    });

    test('no grupo, diz quem', () {
      expect(
        status(_grupo, activity: {'p2': ChatActivity.typing}),
        'Pessoa 2 está digitando…',
      );
      expect(
        status(
          _grupo,
          activity: {'p2': ChatActivity.typing, 'p3': ChatActivity.typing},
        ),
        'Pessoa 2 e Pessoa 3 estão digitando…',
      );
      expect(status(_grupo, online: {'p1', 'p2', 'p3'}), '2 online');
    });

    test('gravar vale mais que digitar, e eu não apareço para mim', () {
      expect(
        status(
          _grupo,
          activity: {'p2': ChatActivity.typing, 'p3': ChatActivity.recording},
        ),
        'Pessoa 3 está gravando áudio…',
      );
      expect(
        status(_grupo, activity: {'p1': ChatActivity.typing}, online: {'p1'}),
        '',
      );
    });
  });

  group('telas', () {
    testWidgets('quem está online ganha a bolinha verde na lista', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      expect(find.byKey(const ValueKey('presenca-online')), findsNothing);

      await container
          .read(repositoryProvider)
          .setPresent(userId: 'p2', present: true);
      await tester.pumpAndSettle();
      // Na conversa a dois com a Pessoa 2 e na do grupo.
      expect(find.byKey(const ValueKey('presenca-online')), findsNWidgets(2));
    });

    testWidgets('o topo da conversa conta quando o outro está digitando', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await tester.tap(find.text('Pessoa 2'));
      await tester.pumpAndSettle();

      await container
          .read(repositoryProvider)
          .setActivity(
            conversationId: 'p1-p2',
            userId: 'p2',
            activity: ChatActivity.typing,
          );
      await tester.pumpAndSettle();
      expect(find.text('digitando…'), findsOneWidget);
    });

    testWidgets('teclar conta aos outros que estou digitando', (tester) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await tester.tap(find.text('Pessoa 2'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Mensagem'), 'oi');
      await tester.pump();
      final repo = container.read(repositoryProvider);
      final agora = (await tester.runAsync(
        () => repo.watchActivity('p1-p2').first,
      ))!;
      expect(agora, {'p1': ChatActivity.typing});

      // Quatro segundos parado, o "digitando" desliga sozinho.
      await tester.pump(const Duration(seconds: 5));
      final depois = (await tester.runAsync(
        () => repo.watchActivity('p1-p2').first,
      ))!;
      expect(depois, isEmpty);
    });
  });
}
