import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/data/repository.dart';
import 'package:sale/domain/models.dart';
import 'package:sale/state/providers.dart';
import 'package:sale/ui/widgets/chat_image.dart';

import 'helpers.dart';

/// Um PNG de 1 pixel: imagem de verdade, para o widget ter o que decodificar.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVR42mNk'
  'YAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

void main() {
  group('a imagem na conversa', () {
    late MemoryRepository repo;

    setUp(() => repo = MemoryRepository());

    Future<Message> unica() async =>
        (await repo.watchMessages('grupo').first).single;

    test('vira mensagem com anexo, e a legenda é opcional', () async {
      await repo.sendImage(
        conversationId: 'grupo',
        authorId: 'p1',
        bytes: _png,
        fileName: 'print.png',
        width: 1080,
        height: 1920,
      );
      final mensagem = await unica();
      expect(mensagem.isImage, isTrue);
      expect(mensagem.text, isNull);
      expect(mensagem.attachment!.aspectRatio, 1080 / 1920);
      expect(await repo.attachmentBytes(mensagem.attachment!.path), _png);
    });

    test('o caminho do anexo começa na conversa', () async {
      await repo.sendImage(
        conversationId: 'grupo',
        authorId: 'p1',
        bytes: _png,
        fileName: 'print.png',
      );
      expect((await unica()).attachment!.path, startsWith('grupo/'));
    });

    test('legenda em branco não vira texto', () async {
      await repo.sendImage(
        conversationId: 'grupo',
        authorId: 'p1',
        bytes: _png,
        fileName: 'print.png',
        caption: '   ',
      );
      expect((await unica()).text, isNull);
    });

    test('sem tamanho, a bolha não tem proporção para usar', () async {
      await repo.sendImage(
        conversationId: 'grupo',
        authorId: 'p1',
        bytes: _png,
        fileName: 'print.png',
      );
      expect((await unica()).attachment!.aspectRatio, isNull);
    });

    test('imagem grande demais não sobe', () async {
      await expectLater(
        repo.sendImage(
          conversationId: 'grupo',
          authorId: 'p1',
          bytes: Uint8List(maxImageBytes + 1),
          fileName: 'enorme.png',
        ),
        throwsStateError,
      );
      expect(await repo.watchMessages('grupo').first, isEmpty);
    });

    test('anexo que este aparelho não tem avisa em vez de mentir', () async {
      await expectLater(
        repo.attachmentBytes('grupo/sumiu.png'),
        throwsStateError,
      );
    });
  });

  group('telas', () {
    testWidgets('a imagem aparece na bolha e abre em tela cheia', (
      tester,
    ) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');

      // A Pessoa 2 manda a foto na conversa individual.
      await container
          .read(repositoryProvider)
          .sendImage(
            conversationId: 'p1-p2',
            authorId: 'p2',
            bytes: _png,
            fileName: 'jogada.png',
            width: 1080,
            height: 1080,
            caption: 'olha essa jogada',
          );
      await tester.pumpAndSettle();

      // A lista de conversas conta que veio foto, com a legenda.
      expect(find.textContaining('📷 olha essa jogada'), findsOneWidget);

      await tester.tap(find.text('Pessoa 2'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatImage), findsOneWidget);
      expect(find.text('olha essa jogada'), findsOneWidget);

      await tester.tap(find.byType(ChatImage));
      await tester.pumpAndSettle();
      expect(find.byType(FullImageScreen), findsOneWidget);
      expect(find.text('Pessoa 2'), findsWidgets);
    });

    testWidgets('foto sem legenda aparece como foto na lista', (tester) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await container
          .read(repositoryProvider)
          .sendImage(
            conversationId: 'p1-p2',
            authorId: 'p2',
            bytes: _png,
            fileName: 'print.png',
          );
      await tester.pumpAndSettle();
      expect(find.textContaining('📷 Foto'), findsOneWidget);
    });
  });
}
