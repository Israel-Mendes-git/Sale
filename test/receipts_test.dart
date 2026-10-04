import 'package:flutter_test/flutter_test.dart';
import 'package:sale/domain/models.dart';

final _vinte = DateTime(2026, 10, 1, 20);

Message _mensagem(String autor, DateTime quando) => Message(
  id: 'm-${quando.millisecondsSinceEpoch}-$autor',
  conversationId: 'grupo',
  authorId: autor,
  createdAt: quando,
  text: 'bora?',
);

/// O grupo dos três, com as marcas que vierem.
Conversation _grupo(Map<String, Receipt> receipts) => Conversation(
  id: 'grupo',
  kind: ConversationKind.group,
  memberIds: const ['p1', 'p2', 'p3'],
  receipts: receipts,
);

void main() {
  final minha = _mensagem('p1', _vinte);

  test('sem marca nenhuma a mensagem está só no servidor', () {
    expect(_grupo(const {}).statusOf(minha), MessageStatus.sent);
  });

  test('a marca é a do último: um só recebeu ainda é um tique', () {
    final conversa = _grupo({'p2': Receipt(deliveredUntil: _vinte)});
    expect(conversa.statusOf(minha), MessageStatus.sent);
  });

  test('recebida pelos dois, dois tiques', () {
    final conversa = _grupo({
      'p2': Receipt(deliveredUntil: _vinte),
      'p3': Receipt(deliveredUntil: _vinte.add(const Duration(minutes: 5))),
    });
    expect(conversa.statusOf(minha), MessageStatus.delivered);
  });

  test('um leu e o outro não: continua entregue', () {
    final conversa = _grupo({
      'p2': Receipt(deliveredUntil: _vinte, readUntil: _vinte),
      'p3': Receipt(deliveredUntil: _vinte),
    });
    expect(conversa.statusOf(minha), MessageStatus.delivered);
  });

  test('os dois leram, mensagem lida', () {
    final conversa = _grupo({
      'p2': Receipt(deliveredUntil: _vinte, readUntil: _vinte),
      'p3': Receipt(deliveredUntil: _vinte, readUntil: _vinte),
    });
    expect(conversa.statusOf(minha), MessageStatus.read);
  });

  test('marca de antes da mensagem não vale para ela', () {
    final antes = _vinte.subtract(const Duration(minutes: 1));
    final conversa = _grupo({
      'p2': Receipt(deliveredUntil: antes, readUntil: antes),
      'p3': Receipt(deliveredUntil: antes, readUntil: antes),
    });
    expect(conversa.statusOf(minha), MessageStatus.sent);
  });

  test('a minha própria marca não entra na conta', () {
    // p1 escreveu e obviamente já viu; quem manda são p2 e p3.
    final conversa = _grupo({
      'p1': Receipt(deliveredUntil: _vinte, readUntil: _vinte),
    });
    expect(conversa.statusOf(minha), MessageStatus.sent);
  });

  group('mensagens novas', () {
    final mensagens = [
      _mensagem('p1', _vinte),
      _mensagem('p2', _vinte.add(const Duration(minutes: 1))),
      _mensagem('p3', _vinte.add(const Duration(minutes: 2))),
    ];

    test('quem nunca abriu tem todas as dos outros por ler', () {
      expect(_grupo(const {}).unreadFor('p1', mensagens), 2);
    });

    test('as minhas nunca contam', () {
      expect(_grupo(const {}).unreadFor('p2', mensagens), 2);
    });

    test('conta só o que chegou depois da última vez que abriu', () {
      final conversa = _grupo({
        'p1': Receipt(readUntil: _vinte.add(const Duration(minutes: 1))),
      });
      expect(conversa.unreadFor('p1', mensagens), 1);
    });

    test('quem abriu depois da última mensagem está em dia', () {
      final conversa = _grupo({
        'p1': Receipt(readUntil: _vinte.add(const Duration(hours: 1))),
      });
      expect(conversa.unreadFor('p1', mensagens), 0);
    });
  });
}
