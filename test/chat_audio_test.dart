import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/data/repository.dart';
import 'package:sale/domain/models.dart';
import 'package:sale/state/providers.dart';

import 'helpers.dart';

void main() {
  group('o recado de voz', () {
    late MemoryRepository repo;

    setUp(() => repo = MemoryRepository());

    Future<Message> unica() async =>
        (await repo.watchMessages('grupo').first).single;

    test('vira mensagem de áudio com a duração', () async {
      await repo.sendAudio(
        conversationId: 'grupo',
        authorId: 'p1',
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'recado.m4a',
        duration: 7,
      );
      final m = await unica();
      expect(m.isAudio, isTrue);
      expect(m.attachment!.kind, AttachmentKind.audio);
      expect(m.attachment!.duration, 7);
      // Recado não tem legenda.
      expect(m.text, isNull);
    });

    test('o arquivo baixa pelo attachmentBytes', () async {
      final bytes = Uint8List.fromList([9, 8, 7]);
      await repo.sendAudio(
        conversationId: 'grupo',
        authorId: 'p1',
        bytes: bytes,
        fileName: 'recado.m4a',
        duration: 2,
      );
      expect(
        await repo.attachmentBytes((await unica()).attachment!.path),
        bytes,
      );
    });

    test('recado grande demais não vai', () async {
      await expectLater(
        repo.sendAudio(
          conversationId: 'grupo',
          authorId: 'p1',
          bytes: Uint8List(maxAudioBytes + 1),
          fileName: 'recado.m4a',
          duration: 3,
        ),
        throwsStateError,
      );
    });

    test('o recado também cita', () async {
      await repo.sendText(
        conversationId: 'grupo',
        authorId: 'p2',
        text: 'manda áudio',
      );
      final pedido = await unica();
      await repo.sendAudio(
        conversationId: 'grupo',
        authorId: 'p1',
        bytes: Uint8List.fromList([1]),
        fileName: 'r.m4a',
        duration: 1,
        replyTo: pedido.id,
      );
      final recado = (await repo.watchMessages('grupo').first).firstWhere(
        (m) => m.isAudio,
      );
      expect(recado.replyTo, pedido.id);
    });
  });

  group('o compositor', () {
    testWidgets('vazio oferece gravar; com texto, enviar', (tester) async {
      await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await tester.tap(find.text('Pessoa 2'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Gravar recado'), findsOneWidget);
      expect(find.byTooltip('Enviar'), findsNothing);

      await tester.enterText(find.widgetWithText(TextField, 'Mensagem'), 'oi');
      await tester.pump();
      expect(find.byTooltip('Enviar'), findsOneWidget);
      expect(find.byTooltip('Gravar recado'), findsNothing);
    });
  });
}
