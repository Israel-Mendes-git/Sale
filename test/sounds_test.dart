import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/data/repository.dart';
import 'package:sale/domain/sounds.dart';
import 'package:sale/state/providers.dart';

import 'helpers.dart';

/// Um arquivo de som de mentira: o que importa aqui é o que o app faz com ele.
Uint8List _arquivo([int bytes = 64]) => Uint8List(bytes);

void main() {
  // A chave de um som do app vive em quatro lugares, e os quatro precisam
  // combinar: os dois arquivos, a lista do app e a linha do banco. Esquecer um
  // só dá um Chamado calado — ou um som que não existe na lista.
  group('os sons que vêm no app', () {
    test('cada um tem os dois arquivos, com o nome da chave', () {
      for (final chave in builtInSounds.keys) {
        expect(
          File('assets/sons/$chave.ogg').existsSync(),
          isTrue,
          reason: 'falta assets/sons/$chave.ogg (a prévia no app)',
        );
        expect(
          File('android/app/src/main/res/raw/$chave.ogg').existsSync(),
          isTrue,
          reason: 'falta res/raw/$chave.ogg (o som da notificação)',
        );
      }
    });

    test('a pasta dos sons não tem arquivo sobrando', () {
      final arquivos = Directory('assets/sons')
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last);
      expect(
        arquivos,
        unorderedEquals([for (final chave in builtInSounds.keys) '$chave.ogg']),
      );
    });

    test('são os mesmos que o banco cadastra', () {
      final sql = File('supabase/migrations/20261003230000_sons_do_chamado.sql')
          .readAsStringSync();
      // As linhas do `insert into public.sounds (name, file) values`.
      final doBanco = {
        for (final achado in RegExp(
          r"\('([^']+)', '([^']+)'\)",
        ).allMatches(sql))
          achado.group(2)!: achado.group(1)!,
      };
      expect(doBanco, builtInSounds);
    });

    test('o pubspec leva a pasta dos sons para dentro do APK', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('assets/sons/'));
    });
  });

  group('a lista de sons', () {
    late MemoryRepository repo;

    setUp(() => repo = MemoryRepository());

    Future<List<Sound>> sounds() => repo.watchSounds().first;

    test('nasce com os sons que vêm no app', () async {
      final list = await sounds();
      expect(list.map((s) => s.name), builtInSounds.values);
      expect(list.every((s) => s.builtIn), isTrue);
    });

    test('o som do app toca pelo nome do arquivo', () async {
      final batsinal = (await sounds()).first;
      expect(batsinal.key, defaultSoundKey);
    });

    test('som do grupo entra na lista e toca pelo id', () async {
      final buzina = await repo.addSound(
        name: 'Buzina',
        fileName: 'buzina.ogg',
        bytes: _arquivo(),
      );
      expect(buzina.builtIn, isFalse);
      expect(buzina.key, buzina.id);
      expect((await sounds()).map((s) => s.name), contains('Buzina'));
      expect(await repo.soundBytes(buzina), hasLength(64));
    });

    test('nome repetido não entra, nem trocando a caixa', () async {
      await repo.addSound(
        name: 'Buzina',
        fileName: 'buzina.ogg',
        bytes: _arquivo(),
      );
      await expectLater(
        repo.addSound(name: 'buzina', fileName: 'outra.ogg', bytes: _arquivo()),
        throwsStateError,
      );
      // Nem com o nome de um que vem no app.
      await expectLater(
        repo.addSound(
          name: 'Sirene',
          fileName: 'sirene.mp3',
          bytes: _arquivo(),
        ),
        throwsStateError,
      );
    });

    test('nome vazio e arquivo grande demais não entram', () async {
      await expectLater(
        repo.addSound(name: '  ', fileName: 'x.ogg', bytes: _arquivo()),
        throwsArgumentError,
      );
      await expectLater(
        repo.addSound(
          name: 'Gigante',
          fileName: 'x.ogg',
          bytes: _arquivo(maxSoundBytes + 1),
        ),
        throwsStateError,
      );
    });

    test('som do grupo sai da lista; o do app, não', () async {
      final buzina = await repo.addSound(
        name: 'Buzina',
        fileName: 'buzina.ogg',
        bytes: _arquivo(),
      );
      await repo.removeSound(buzina.id);
      expect((await sounds()).map((s) => s.name), isNot(contains('Buzina')));

      final sirene = (await sounds()).firstWhere((s) => s.name == 'Sirene');
      await expectLater(repo.removeSound(sirene.id), throwsStateError);
      expect((await sounds()).map((s) => s.name), contains('Sirene'));
    });
  });

  group('o som de cada um', () {
    late MemoryRepository repo;

    setUp(() => repo = MemoryRepository());

    test('escolher grava no perfil, e som fora da lista é recusado', () async {
      final sirene = (await repo.watchSounds().first).firstWhere(
        (s) => s.file == 'sirene',
      );
      await repo.setProfileSound('p1', sirene.id);
      expect(repo.profile('p1').soundId, sirene.id);

      await repo.setProfileSound('p1', null);
      expect(repo.profile('p1').soundId, isNull);
      await expectLater(
        repo.setProfileSound('p1', 'som-que-não-existe'),
        throwsArgumentError,
      );
    });

    test('som apagado volta o perfil para o som da marca', () async {
      final buzina = await repo.addSound(
        name: 'Buzina',
        fileName: 'buzina.ogg',
        bytes: _arquivo(),
      );
      await repo.setProfileSound('p2', buzina.id);
      await repo.removeSound(buzina.id);
      expect(repo.profile('p2').soundId, isNull);
    });
  });

  group('o som no Chamado', () {
    late MemoryRepository repo;

    setUp(() => repo = MemoryRepository());

    test('quem chama escolhe, e o Chamado guarda a chave', () async {
      final sirene = (await repo.watchSounds().first).firstWhere(
        (s) => s.file == 'sirene',
      );
      final chamado = await repo.sendChamado(
        conversationId: 'grupo',
        authorId: 'p1',
        targetIds: const ['p2'],
        soundId: sirene.id,
      );
      expect(chamado.soundKey, 'sirene');
    });

    test('som do grupo vai pelo id', () async {
      final buzina = await repo.addSound(
        name: 'Buzina',
        fileName: 'buzina.ogg',
        bytes: _arquivo(),
      );
      final chamado = await repo.sendChamado(
        conversationId: 'grupo',
        authorId: 'p1',
        targetIds: const ['p2'],
        soundId: buzina.id,
      );
      expect(chamado.soundKey, buzina.id);
    });

    test('sem escolha, o Chamado toca o som da marca', () async {
      final chamado = await repo.sendChamado(
        conversationId: 'grupo',
        authorId: 'p1',
        targetIds: const ['p2'],
      );
      expect(chamado.soundKey, isNull);
    });

    test('som que não está na lista não dispara Chamado', () async {
      await expectLater(
        repo.sendChamado(
          conversationId: 'grupo',
          authorId: 'p1',
          targetIds: const ['p2'],
          soundId: 'som-que-não-existe',
        ),
        throwsArgumentError,
      );
    });
  });

  group('telas', () {
    testWidgets('o som escolhido na hora vai com o Chamado', (tester) async {
      final container = await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await tester.tap(find.text('Os 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Chamado'));
      await tester.pumpAndSettle();

      // Sem escolher nada, o Chamado já nasce com um som: o da marca.
      await scrollTo(tester, find.widgetWithText(ChoiceChip, 'Sirene'));
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Batsinal'))
            .selected,
        isTrue,
      );

      await tester.tap(find.widgetWithText(ChoiceChip, 'Sirene'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disparar'));
      await tester.pumpAndSettle();

      final historico = (await tester.runAsync(
        () => container.read(repositoryProvider).watchHistory('p1').first,
      ))!;
      expect(historico.single.soundKey, 'sirene');
    });

    testWidgets('o som do perfil é o que já vem marcado', (tester) async {
      await pumpApp(tester);
      await signInAs(tester, 'Pessoa 1');
      await tester.tap(find.byTooltip('Meu perfil'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Batsinal · o som que toca'), findsOneWidget);
      await tester.tap(find.text('Som do Chamado'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Radar'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Radar · o som que toca'), findsOneWidget);

      // E é ele que a tela do Chamado já traz marcado.
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Os 3'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Chamado'));
      await tester.pumpAndSettle();
      await scrollTo(tester, find.widgetWithText(ChoiceChip, 'Radar'));
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Radar'))
            .selected,
        isTrue,
      );
    });
  });
}
