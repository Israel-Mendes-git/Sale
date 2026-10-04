import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/sounds.dart';
import 'push.dart';

/// O som do grupo neste aparelho: baixar, deixar o Android enxergar e tocar a
/// prévia.
///
/// O som que vem no app já está dentro do APK (em `res/raw` para a notificação
/// e em `assets/sons` para a prévia). O do grupo mora no Storage, e cada
/// aparelho precisa baixá-lo uma vez: a notificação é montada pelo sistema, e
/// ele não lê a pasta privada do app — daí o registro no acervo de sons
/// (`MainActivity.kt`) e o canal de notificação com o endereço de lá.
///
/// Som que este aparelho ainda não baixou não tem canal, e o Chamado dele toca
/// o som da marca. Não é erro: é o app ainda não tendo aberto desde que o som
/// entrou na lista.

const _nativo = MethodChannel('sale/sons');

/// Os sons do grupo que este aparelho já registrou, pela chave do som.
const _jaRegistrados = 'sons_registrados';

final _player = AudioPlayer();

Future<Directory> _pasta() async {
  final documentos = await getApplicationDocumentsDirectory();
  final pasta = Directory('${documentos.path}/sons');
  if (!await pasta.exists()) await pasta.create(recursive: true);
  return pasta;
}

/// O arquivo de um som do grupo neste aparelho. O nome leva o prefixo do app
/// porque ele também é o nome que aparece no acervo de sons do aparelho.
Future<File> _arquivo(Sound som) async =>
    File('${(await _pasta()).path}/sale-${som.id}${som.extension}');

/// Deixa os sons do grupo prontos para tocar: baixa o que falta, registra no
/// acervo do aparelho e cria o canal de notificação de cada um.
///
/// Chamar de novo é barato — o que já foi registrado não volta a baixar. Falha
/// de um som não atrapalha os outros: cada um tenta de novo na próxima
/// abertura do app.
Future<void> prepararSons(
  List<Sound> sons,
  Future<Uint8List> Function(Sound) baixar,
) async {
  final doGrupo = [
    for (final som in sons)
      if (!som.builtIn) som,
  ];

  final guardadas = await SharedPreferences.getInstance();
  final registrados = guardadas.getStringList(_jaRegistrados) ?? const [];
  final chaves = {for (final som in doGrupo) som.key};

  // Som que saiu da lista do grupo também sai daqui: o canal dele ficaria
  // para sempre nas configurações do aparelho, com nome de som que não existe.
  final sairam = [
    for (final k in registrados)
      if (!chaves.contains(k)) k,
  ];
  for (final chave in sairam) {
    try {
      await apagarCanalDoSom(chave);
      await _apagarArquivo(chave);
    } catch (e) {
      debugPrint('O som "$chave" não saiu deste aparelho: $e');
    }
  }
  if (sairam.isNotEmpty) {
    await guardadas.setStringList(_jaRegistrados, [
      for (final k in registrados)
        if (chaves.contains(k)) k,
    ]);
  }

  final jaTem = [
    for (final k in registrados)
      if (chaves.contains(k)) k,
  ];
  final novos = <String>[];

  for (final som in doGrupo) {
    if (jaTem.contains(som.key)) continue;
    try {
      final arquivo = await _arquivo(som);
      if (!await arquivo.exists()) {
        await arquivo.writeAsBytes(await baixar(som));
      }
      final endereco = await _nativo.invokeMethod<String>(
        'registrar',
        arquivo.path,
      );
      if (endereco == null) continue;
      await criarCanalDoSom(chave: som.key, nome: som.name, uri: endereco);
      novos.add(som.key);
    } catch (e) {
      debugPrint('O som "${som.name}" não ficou pronto neste aparelho: $e');
    }
  }

  if (novos.isNotEmpty) {
    await guardadas.setStringList(_jaRegistrados, [...jaTem, ...novos]);
  }
}

/// Apaga o arquivo baixado de um som que saiu da lista. O registro no acervo
/// de sons do aparelho fica: ele não duplica (o nome é o mesmo se o som
/// voltar), e quem quiser pode removê-lo pelo gerenciador de arquivos.
Future<void> _apagarArquivo(String chave) async {
  final pasta = await _pasta();
  for (final arquivo in pasta.listSync()) {
    if (arquivo is File && arquivo.path.contains('sale-$chave')) {
      await arquivo.delete();
    }
  }
}

/// Toca o som para a pessoa ouvir antes de escolher. Som do grupo que ainda
/// não está no aparelho é baixado na hora.
///
/// Falhar aqui não é grave — a pessoa só não ouviu —, então o erro fica no log
/// em vez de na tela.
Future<void> ouvirSom(
  Sound som, {
  Future<Uint8List> Function(Sound)? baixar,
}) async {
  try {
    await _player.stop();
    if (som.builtIn) {
      await _player.play(AssetSource('sons/${som.file}.ogg'));
      return;
    }
    final arquivo = await _arquivo(som);
    if (!await arquivo.exists()) {
      if (baixar == null) return;
      await arquivo.writeAsBytes(await baixar(som));
    }
    await _player.play(DeviceFileSource(arquivo.path));
  } catch (e) {
    debugPrint('Não deu para ouvir "${som.name}": $e');
  }
}

/// Para o som da prévia (ao sair da tela, por exemplo).
Future<void> pararSom() async {
  try {
    await _player.stop();
  } catch (e) {
    debugPrint('Não deu para parar o som: $e');
  }
}
