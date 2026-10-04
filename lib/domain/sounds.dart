import 'package:flutter/foundation.dart';

/// Os sons que vêm no app, da chave para o nome que a pessoa lê.
///
/// A chave é o nome do arquivo em dois lugares: `assets/sons/<chave>.ogg`, de
/// onde sai a prévia, e `android/app/src/main/res/raw/<chave>.ogg`, de onde a
/// notificação toca. Os mesmos cinco estão na tabela `sounds` do banco, com
/// `group_id` nulo (ver a migração dos sons do Chamado).
const builtInSounds = {
  'batsinal': 'Batsinal',
  'sirene': 'Sirene',
  'telefone': 'Telefone',
  'alarme': 'Alarme',
  'radar': 'Radar',
};

/// O som de quem não escolheu nenhum, e também o do encontro fixo, que não
/// tem ninguém chamando: o da marca.
const defaultSoundKey = 'batsinal';

/// O arquivo da prévia de um som que vem no app.
String soundAsset(String key) => 'assets/sons/$key.ogg';

/// Um som da lista do grupo: os cinco que vêm no app mais os que o grupo
/// subiu.
@immutable
class Sound {
  const Sound({
    required this.id,
    required this.name,
    required this.file,
    this.groupId,
  });

  final String id;
  final String name;

  /// Som do app: o nome do arquivo (sem extensão). Som do grupo: o caminho
  /// dele no Storage, `<grupo>/<arquivo>`.
  final String file;

  /// Nulo = som que vem no app, igual para todos os grupos.
  final String? groupId;

  bool get builtIn => groupId == null;

  /// Com que nome este som é conhecido fora do banco: o canal de notificação
  /// no aparelho (`chamado_<chave>`) e o `sound_key` que o Chamado guarda.
  ///
  /// O som do app usa o nome do arquivo porque ele é o mesmo em todo aparelho;
  /// o do grupo usa o id, que é o que ele tem de único.
  String get key => builtIn ? file : id;

  /// A extensão do arquivo do grupo (`.ogg`, `.mp3`), para o aparelho salvar
  /// o download com ela. Vazio quando o caminho não tem extensão.
  String get extension {
    final dot = file.lastIndexOf('.');
    return dot == -1 ? '' : file.substring(dot);
  }
}
