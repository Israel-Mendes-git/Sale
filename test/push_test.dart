import 'package:flutter_test/flutter_test.dart';
import 'package:sale/push/push.dart';

void main() {
  group('os botões da notificação do Chamado', () {
    test('são as três respostas comuns, nessa ordem', () {
      expect(acoesDoChamado.map((a) => a.id), [
        'responder:yes:',
        'responder:later:20',
        'responder:no:',
      ]);
    });

    test('cada botão diz o tipo e o tempo da resposta', () {
      expect(lerRespostaDaAcao('responder:yes:'), (tipo: 'yes', minutos: null));
      expect(lerRespostaDaAcao('responder:later:20'), (
        tipo: 'later',
        minutos: 20,
      ));
      expect(lerRespostaDaAcao('responder:no:'), (tipo: 'no', minutos: null));
    });

    test('o que não é botão de responder fica de fora', () {
      expect(lerRespostaDaAcao(null), isNull);
      expect(lerRespostaDaAcao(''), isNull);
      expect(lerRespostaDaAcao('abrir'), isNull);
      expect(lerRespostaDaAcao('responder::'), isNull);
      expect(lerRespostaDaAcao('responder:yes'), isNull);
    });
  });
}
