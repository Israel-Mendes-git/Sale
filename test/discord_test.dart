import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/discord.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/data/seed.dart';
import 'package:sale/domain/conquistas.dart';
import 'package:sale/state/providers.dart';
import 'package:sale/ui/screens/discord_screen.dart';
import 'package:sale/ui/screens/stats_screen.dart';

/// Um widget de servidor como o Discord devolve: duas calls, gente fora de
/// call jogando, e o convite.
final _widget = <String, dynamic>{
  'name': 'Os 3',
  'instant_invite': 'https://discord.com/invite/abc',
  'channels': [
    {'id': '10', 'name': 'Geral', 'position': 0},
    {'id': '11', 'name': 'Ranked', 'position': 1},
    {'id': '12', 'name': 'Vazia', 'position': 2},
  ],
  'members': [
    {
      'username': 'ana',
      'status': 'online',
      'channel_id': '10',
      'self_mute': true,
    },
    {
      'username': 'bruno',
      'status': 'idle',
      'game': {'name': 'Valorant'},
    },
    {'username': 'caio', 'status': 'dnd', 'channel_id': '11', 'deaf': true},
    {'username': '', 'channel_id': '10'},
  ],
};

void main() {
  group('o widget do Discord', () {
    test('lê as calls por canal, quem está fora e o que está jogando', () {
      final s = lerWidget(_widget);
      expect(s.nome, 'Os 3');
      expect(s.convite, 'https://discord.com/invite/abc');
      expect(s.membros.length, 3, reason: 'sem nome fica de fora');
      expect([for (final c in s.calls) c.nome], ['Geral', 'Ranked']);
      expect([for (final m in s.naCall) m.nome], ['ana', 'caio']);

      final ana = s.membros.firstWhere((m) => m.nome == 'ana');
      expect((ana.mudo, ana.surdo), (true, false));
      final caio = s.membros.firstWhere((m) => m.nome == 'caio');
      expect((caio.mudo, caio.surdo, caio.status), (false, true, 'dnd'));
      final bruno = s.membros.firstWhere((m) => m.nome == 'bruno');
      expect((bruno.naCall, bruno.jogo), (false, 'Valorant'));
    });

    test('widget vazio não quebra', () {
      final s = lerWidget(const {});
      expect(s.calls, isEmpty);
      expect(s.naCall, isEmpty);
      expect(s.convite, isNull);
    });

    test('o ID do servidor é só números', () {
      expect(formatoDoServidor.hasMatch('112233445566778899'), isTrue);
      expect(formatoDoServidor.hasMatch('abc'), isFalse);
    });

    test('a duração escrita como no resumo', () {
      expect(duracaoEmTexto(45), '45 min');
      expect(duracaoEmTexto(120), '2 h');
      expect(duracaoEmTexto(135), '2 h 15');
      expect(duracaoEmTexto(61), '1 h 01');
    });
  });

  group('no repositório', () {
    test('o grupo guarda o servidor, e nulo tira', () async {
      final repo = MemoryRepository();
      await repo.setGroupDiscord(groupId: 'g1', servidor: '112233445566');
      expect(
        (await repo.watchGroups('p1').first).single.discordServidor,
        '112233445566',
      );
      await repo.setGroupDiscord(groupId: 'g1');
      expect(
        (await repo.watchGroups('p1').first).single.discordServidor,
        isNull,
      );
    });

    test('servidor em formato errado não entra', () async {
      await expectLater(
        MemoryRepository().setGroupDiscord(groupId: 'g1', servidor: 'oi'),
        throwsArgumentError,
      );
    });

    test('o nome no Discord liga o tempo de call a quem é', () async {
      final repo = MemoryRepository();
      await repo.setDiscordName('p2', ' Pessoa2 ');
      expect(repo.profile('p2').discordNome, 'Pessoa2');
      final tempos = await repo.callTime('g1', DateTime(2000));
      expect(tempos.first.nome, 'pessoa2');
      expect(tempos.first.userId, 'p2');
      expect(tempos.last.userId, isNull);

      await repo.setDiscordName('p2', '');
      expect(repo.profile('p2').discordNome, isNull);
    });
  });

  group('a conquista da call', () {
    test('só aparece para quem tem a call ligada', () {
      expect(
        conquistasDe('p1', const []).any((c) => c.titulo == 'Morador da call'),
        isFalse,
      );
      final perto = conquistasDe(
        'p1',
        const [],
        minutosDeCall: 599,
      ).firstWhere((c) => c.titulo == 'Morador da call');
      expect((perto.ganhou, perto.progresso), (false, '9/10'));
      expect(
        conquistasDe(
          'p1',
          const [],
          minutosDeCall: 600,
        ).firstWhere((c) => c.titulo == 'Morador da call').ganhou,
        isTrue,
      );
    });
  });

  group('telas', () {
    Future<ProviderContainer> abrir(WidgetTester tester, Widget tela) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final container = ProviderContainer(
        overrides: [
          discordAoVivoProvider.overrideWith(
            (ref, servidor) => Stream.value(lerWidget(_widget)),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container
          .read(repositoryProvider)
          .setGroupDiscord(groupId: 'g1', servidor: '112233445566');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(home: tela),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('ao vivo: calls, quem joga o quê e o tempo da semana', (
      tester,
    ) async {
      final grupo = seedGroup.withDiscord('112233445566');
      await abrir(tester, DiscordAoVivoScreen(group: grupo, userId: 'p1'));

      expect(find.text('🔊 Geral'), findsOneWidget);
      expect(find.text('🔊 Ranked'), findsOneWidget);
      expect(find.text('Jogando Valorant'), findsOneWidget);
      expect(find.byIcon(Icons.mic_off), findsOneWidget);
      expect(find.text('Abrir no Discord'), findsOneWidget);
      expect(find.text('Tempo de call na semana'), findsOneWidget);
      expect(find.text('5 h 40'), findsOneWidget);
    });

    testWidgets('o Placar mostra quem mais fica em call', (tester) async {
      await abrir(tester, const StatsScreen(userId: 'p1'));
      await tester.scrollUntilVisible(find.text('Quem mais fica em call'), 200);
      expect(find.text('Quem mais fica em call'), findsOneWidget);
      expect(find.text('pessoa2'), findsOneWidget);
    });
  });
}
