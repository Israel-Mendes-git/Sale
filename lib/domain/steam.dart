import 'package:flutter/foundation.dart';

import 'games.dart';

/// A importação da Steam: os jogos de alguém, para marcar na biblioteca do
/// grupo os que a pessoa tem e trazer os que faltam.
///
/// Quem fala com a Steam é o servidor (a Edge Function `steam-biblioteca`,
/// com a chave da Steam Web API); aqui fica o que é conta pura.

/// Um jogo da conta da Steam, com as horas jogadas.
@immutable
class JogoDaSteam {
  const JogoDaSteam({required this.nome, this.horas = 0, this.appId});

  final String nome;
  final int horas;
  final int? appId;
}

/// O perfil como a pessoa colou — o link do perfil, o ID de 17 dígitos ou o
/// nome personalizado — reduzido ao que o servidor procura. Nulo = vazio.
String? lerPerfilDaSteam(String entrada) {
  var t = entrada.trim();
  if (t.isEmpty) return null;
  final link = RegExp(r'steamcommunity\.com/(profiles|id)/([^/?#\s]+)')
      .firstMatch(t);
  if (link != null) t = link.group(2)!;
  return t.isEmpty ? null : t;
}

/// O nome de um jogo sem o que muda de um lugar para outro: caixa, ™ e ®,
/// pontuação e espaços. "Counter-Strike® 2" e "counter strike 2" batem.
String normalizarNome(String nome) => nome
    .toLowerCase()
    .replaceAll(RegExp(r'[™®©]'), '')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

/// Cruza os jogos da Steam com a biblioteca do grupo: os que já estão nela
/// (id do jogo do grupo -> o jogo da Steam) e os que não estão, do mais
/// jogado para o menos.
({Map<String, JogoDaSteam> naBiblioteca, List<JogoDaSteam> fora})
cruzarComBiblioteca(Iterable<JogoDaSteam> jogos, Iterable<Game> biblioteca) {
  final porNome = {for (final g in biblioteca) normalizarNome(g.name): g.id};
  final naBiblioteca = <String, JogoDaSteam>{};
  final fora = <JogoDaSteam>[];
  for (final jogo in jogos) {
    final id = porNome[normalizarNome(jogo.nome)];
    if (id == null) {
      fora.add(jogo);
    } else {
      naBiblioteca[id] = jogo;
    }
  }
  fora.sort((a, b) => b.horas.compareTo(a.horas));
  return (naBiblioteca: naBiblioteca, fora: fora);
}
