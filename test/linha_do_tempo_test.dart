import 'package:flutter_test/flutter_test.dart';
import 'package:sale/domain/linha_do_tempo.dart';
import 'package:sale/domain/models.dart';
import 'package:sale/ui/format.dart';

Message msg(String id, String autor, DateTime quando, {String? chamado}) =>
    Message(
      id: id,
      conversationId: 'grupo',
      authorId: autor,
      createdAt: quando,
      text: chamado == null ? id : null,
      chamadoId: chamado,
    );

void main() {
  final seg = DateTime(2026, 10, 19, 21);

  group('a linha do tempo da conversa', () {
    test('cada dia abre com o separador', () {
      final itens = linhaDoTempo([
        msg('a', 'p1', seg),
        msg('b', 'p2', seg.add(const Duration(hours: 1))),
        msg('c', 'p1', seg.add(const Duration(days: 1))),
      ], userId: 'p1');
      expect(itens.whereType<InicioDoDia>().map((d) => d.dia), [
        DateTime(2026, 10, 19),
        DateTime(2026, 10, 20),
      ]);
      expect(itens.first, isA<InicioDoDia>());
    });

    test('a mesma pessoa em seguida emenda; passou de 5 min, não', () {
      final itens = linhaDoTempo([
        msg('a', 'p1', seg),
        msg('b', 'p1', seg.add(const Duration(minutes: 2))),
        msg('c', 'p1', seg.add(const Duration(minutes: 9))),
        msg('d', 'p2', seg.add(const Duration(minutes: 10))),
      ], userId: 'p1');
      final emendas = {
        for (final b in itens.whereType<Bolha>()) b.message.id: b.emendada,
      };
      expect(emendas, {'a': false, 'b': true, 'c': false, 'd': false});
    });

    test('Chamado no meio quebra a sequência', () {
      final itens = linhaDoTempo([
        msg('a', 'p1', seg),
        msg('ch', 'p1', seg.add(const Duration(minutes: 1)), chamado: 'x'),
        msg('b', 'p1', seg.add(const Duration(minutes: 2))),
      ], userId: 'p1');
      expect(itens.whereType<Bolha>().every((b) => !b.emendada), isTrue);
    });

    test('a faixa de novas vai antes da primeira que eu não tinha visto', () {
      final itens = linhaDoTempo(
        [
          msg('vista', 'p2', seg),
          msg('minha', 'p1', seg.add(const Duration(minutes: 1))),
          msg('nova1', 'p2', seg.add(const Duration(minutes: 2))),
          msg('nova2', 'p2', seg.add(const Duration(minutes: 3))),
        ],
        userId: 'p1',
        lidaAte: seg.add(const Duration(seconds: 30)),
      );
      final i = itens.indexWhere((x) => x is MensagensNovas);
      expect((itens[i] as MensagensNovas).quantas, 2);
      expect((itens[i + 1] as Bolha).message.id, 'nova1');
      // Depois da faixa, a bolha recomeça com o nome.
      expect((itens[i + 1] as Bolha).emendada, isFalse);
    });

    test('sem nada novo, ou nunca aberta, não há faixa', () {
      final lista = [msg('a', 'p2', seg)];
      expect(
        linhaDoTempo(
          lista,
          userId: 'p1',
          lidaAte: seg,
        ).whereType<MensagensNovas>(),
        isEmpty,
      );
      expect(
        linhaDoTempo(lista, userId: 'p1').whereType<MensagensNovas>(),
        isEmpty,
      );
    });
  });

  group('o nome do dia', () {
    final agora = DateTime(2026, 10, 22, 15); // quinta

    test('hoje, ontem, a semana e a data', () {
      expect(rotuloDoDia(DateTime(2026, 10, 22), agora), 'Hoje');
      expect(rotuloDoDia(DateTime(2026, 10, 21), agora), 'Ontem');
      expect(rotuloDoDia(DateTime(2026, 10, 19), agora), 'Segunda');
      expect(rotuloDoDia(DateTime(2026, 10, 12), agora), '12/10');
      expect(rotuloDoDia(DateTime(2025, 12, 31), agora), '31/12/2025');
    });
  });
}
