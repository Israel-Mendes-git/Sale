import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/discord.dart';
import 'package:sale/data/memory_repository.dart';

void main() {
  group('o widget do Discord', () {
    test('na call é quem tem canal de voz', () {
      expect(
        quemEstaNaCall({
          'members': [
            {'username': 'ana', 'channel_id': '123'},
            {'username': 'bruno', 'status': 'online'},
            {'username': 'caio', 'channel_id': '123'},
          ],
        }),
        ['ana', 'caio'],
      );
    });

    test('sem ninguém, ou widget vazio, é lista vazia', () {
      expect(quemEstaNaCall(const {}), isEmpty);
      expect(quemEstaNaCall({'members': <Object>[]}), isEmpty);
    });
  });

  group('o formato', () {
    test('do webhook', () {
      expect(
        formatoDoWebhook.hasMatch(
          'https://discord.com/api/webhooks/123456/abc_DEF-9',
        ),
        isTrue,
      );
      expect(formatoDoWebhook.hasMatch('https://exemplo.com/x'), isFalse);
    });

    test('do servidor', () {
      expect(formatoDoServidor.hasMatch('112233445566778899'), isTrue);
      expect(formatoDoServidor.hasMatch('abc'), isFalse);
    });
  });

  group('no repositório', () {
    test('o grupo guarda o Discord, e nulo tira', () async {
      final repo = MemoryRepository();
      await repo.setGroupDiscord(
        groupId: 'g1',
        webhook: 'https://discord.com/api/webhooks/1/abc',
        servidor: '112233445566',
      );
      final grupo = (await repo.watchGroups('p1').first).single;
      expect(grupo.discordWebhook, 'https://discord.com/api/webhooks/1/abc');
      expect(grupo.discordServidor, '112233445566');

      await repo.setGroupDiscord(groupId: 'g1');
      expect(
        (await repo.watchGroups('p1').first).single.discordWebhook,
        isNull,
      );
    });

    test('formato errado não entra', () async {
      await expectLater(
        MemoryRepository().setGroupDiscord(groupId: 'g1', webhook: 'oi'),
        throwsArgumentError,
      );
    });
  });
}
