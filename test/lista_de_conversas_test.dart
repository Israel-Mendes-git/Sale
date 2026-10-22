import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/domain/lista_de_conversas.dart';
import 'package:sale/domain/models.dart';
import 'package:sale/state/providers.dart';

import 'helpers.dart';

Conversation conversa(
  String id, {
  ConversationKind kind = ConversationKind.direct,
  DateTime? pinnedAt,
}) => Conversation(
  id: id,
  kind: kind,
  memberIds: const ['p1', 'p2'],
  pinnedAt: pinnedAt,
);

void main() {
  group('a ordem e o filtro da lista', () {
    final lista = [
      conversa('a'),
      conversa('b', pinnedAt: DateTime(2026, 10, 1)),
      conversa('c', kind: ConversationKind.group),
      conversa('d', pinnedAt: DateTime(2026, 10, 5)),
    ];
    List<String> ids(List<Conversation> l) => [for (final c in l) c.id];

    test('fixadas em cima, a fixada por último primeiro', () {
      expect(
        ids(
          conversasDaLista(lista, titulo: (c) => c.id, naoLida: (_) => false),
        ),
        ['d', 'b', 'a', 'c'],
      );
    });

    test('os filtros', () {
      List<String> com(FiltroDeConversas f) => ids(
        conversasDaLista(
          lista,
          filtro: f,
          titulo: (c) => c.id,
          naoLida: (c) => c.id == 'a' || c.id == 'd',
        ),
      );
      expect(com(FiltroDeConversas.naoLidas), ['d', 'a']);
      expect(com(FiltroDeConversas.grupos), ['c']);
      expect(com(FiltroDeConversas.individuais), ['d', 'b', 'a']);
    });

    test('a busca casa com o título', () {
      expect(
        ids(
          conversasDaLista(
            lista,
            busca: 'b',
            titulo: (c) => c.id,
            naoLida: (_) => false,
          ),
        ),
        ['b'],
      );
    });
  });

  group('as escolhas de cada um', () {
    late MemoryRepository repo;
    setUp(() => repo = MemoryRepository());

    Future<Conversation> de(String userId, String id) async =>
        (await repo.watchConversations(userId).first).firstWhere(
          (c) => c.id == id,
        );

    test('fixar e silenciar valem só para quem escolheu', () async {
      await repo.pinConversation(
        conversationId: 'grupo',
        userId: 'p1',
        pinned: true,
      );
      await repo.muteConversation(
        conversationId: 'grupo',
        userId: 'p1',
        until: mutedForever,
      );
      final minha = await de('p1', 'grupo');
      expect(minha.isPinned, isTrue);
      expect(minha.isMutedAt(DateTime(2030)), isTrue);
      final dela = await de('p2', 'grupo');
      expect(dela.isPinned, isFalse);
      expect(dela.mutedUntil, isNull);
    });

    test('desafixar e reativar o som desfazem', () async {
      await repo.pinConversation(
        conversationId: 'grupo',
        userId: 'p1',
        pinned: true,
      );
      await repo.pinConversation(
        conversationId: 'grupo',
        userId: 'p1',
        pinned: false,
      );
      await repo.muteConversation(
        conversationId: 'grupo',
        userId: 'p1',
        until: DateTime(2030),
      );
      await repo.muteConversation(conversationId: 'grupo', userId: 'p1');
      final c = await de('p1', 'grupo');
      expect(c.isPinned, isFalse);
      expect(c.mutedUntil, isNull);
    });

    test('silêncio vencido não cala mais', () async {
      await repo.muteConversation(
        conversationId: 'grupo',
        userId: 'p1',
        until: DateTime(2026, 10, 22, 10),
      );
      final c = await de('p1', 'grupo');
      expect(c.isMutedAt(DateTime(2026, 10, 22, 9)), isTrue);
      expect(c.isMutedAt(DateTime(2026, 10, 22, 11)), isFalse);
    });

    test('marcada como não lida até abrir de novo', () async {
      await repo.markUnread(conversationId: 'grupo', userId: 'p1');
      expect((await de('p1', 'grupo')).markedUnread, isTrue);
      await repo.markRead(conversationId: 'grupo', userId: 'p1');
      expect((await de('p1', 'grupo')).markedUnread, isFalse);
    });

    test('quem não está na conversa não escolhe nada nela', () async {
      await expectLater(
        repo.pinConversation(
          conversationId: 'p1-p2',
          userId: 'p3',
          pinned: true,
        ),
        throwsStateError,
      );
    });

    test('a encaminhada chega marcada', () async {
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p1',
        text: 'olha isso',
        forwarded: true,
      );
      final m = (await repo.watchMessages('grupo').first).last;
      expect(m.forwarded, isTrue);
    });
  });

  group('telas', () {
    /// O toque longo na conversa, e uma opção do menu.
    Future<void> menuDa(WidgetTester tester, String nome, String opcao) async {
      await tester.longPress(find.text(nome));
      await tester.pumpAndSettle();
      await tester.tap(find.text(opcao));
      await tester.pumpAndSettle();
    }

    double alturaDe(WidgetTester tester, String nome) =>
        tester.getTopLeft(find.text(nome)).dy;

    testWidgets('fixar leva a conversa para o topo', (tester) async {
      final c = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      // Pessoa 2 falou por último: ela está em cima.
      await c
          .read(repositoryProvider)
          .sendText(conversationId: 'p1-p2', authorId: 'p2', text: 'oi');
      await tester.pumpAndSettle();
      expect(
        alturaDe(tester, 'Pessoa 3'),
        greaterThan(alturaDe(tester, 'Pessoa 2')),
      );

      await menuDa(tester, 'Pessoa 3', 'Fixar no topo');
      expect(
        alturaDe(tester, 'Pessoa 3'),
        lessThan(alturaDe(tester, 'Pessoa 2')),
      );
      expect(find.byIcon(Icons.push_pin), findsOneWidget);

      await menuDa(tester, 'Pessoa 3', 'Desafixar');
      expect(find.byIcon(Icons.push_pin), findsNothing);
    });

    testWidgets('silenciar mostra o alto-falante cortado', (tester) async {
      await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');

      await menuDa(tester, 'Os 3', 'Silenciar');
      await tester.tap(find.text('8 horas'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.volume_off), findsOneWidget);

      await menuDa(tester, 'Os 3', 'Reativar o som');
      expect(find.byIcon(Icons.volume_off), findsNothing);
    });

    testWidgets('marcar como não lida põe a bolinha, e abrir tira', (
      tester,
    ) async {
      final c = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');

      await menuDa(tester, 'Pessoa 2', 'Marcar como não lida');
      final conversa = (await tester.runAsync(
        () => c.read(repositoryProvider).watchConversations('p1').first,
      ))!.firstWhere((x) => x.id == 'p1-p2');
      expect(conversa.markedUnread, isTrue);
      // No filtro de não lidas, só ela.
      await tester.tap(find.text('Não lidas'));
      await tester.pumpAndSettle();
      expect(find.text('Pessoa 2'), findsOneWidget);
      expect(find.text('Pessoa 3'), findsNothing);

      await tester.tap(find.text('Pessoa 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      // Aberta, deixou de ser não lida: sai do filtro.
      expect(find.text('Pessoa 2'), findsNothing);
    });

    testWidgets('a busca acha a conversa pelo nome, sem acento', (
      tester,
    ) async {
      await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');

      await tester.enterText(
        find.widgetWithText(TextField, 'Buscar conversa'),
        'PESSOA 3',
      );
      await tester.pumpAndSettle();
      expect(find.text('Pessoa 3'), findsOneWidget);
      expect(find.text('Pessoa 2'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'Buscar conversa'),
        'ninguém',
      );
      await tester.pumpAndSettle();
      expect(find.text('Nenhuma conversa com esse nome.'), findsOneWidget);
    });

    testWidgets('encaminhar manda a mensagem para outra conversa', (
      tester,
    ) async {
      final c = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      final repo = c.read(repositoryProvider);
      await repo.sendText(
        conversationId: 'p1-p2',
        authorId: 'p2',
        text: 'o IP é 10.0.0.7',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pessoa 2'));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('o IP é 10.0.0.7'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Encaminhar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Os 3'));
      await tester.pumpAndSettle();
      expect(find.text('Encaminhada para Os 3.'), findsOneWidget);

      final noGrupo = (await tester.runAsync(
        () => repo.watchMessages('grupo').first,
      ))!.last;
      expect(noGrupo.text, 'o IP é 10.0.0.7');
      expect(noGrupo.authorId, 'p1');
      expect(noGrupo.forwarded, isTrue);

      // A bolha avisa que veio de outra conversa.
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Os 3'));
      await tester.pumpAndSettle();
      expect(find.text('Encaminhada'), findsOneWidget);
    });
  });
}
