import 'dart:math';

import 'package:flutter/foundation.dart';

const maxGameNameLength = 40;
const maxPlayersLimit = 32;

/// Recusa a faixa de jogadores que não faz sentido: invertida, abaixo de 1 ou
/// acima de [maxPlayersLimit].
void checarFaixaDeJogadores(int minPlayers, int maxPlayers) {
  if (minPlayers < 1 ||
      maxPlayers > maxPlayersLimit ||
      minPlayers > maxPlayers) {
    throw ArgumentError(
      'Jogadores de $minPlayers a $maxPlayers não faz sentido.',
    );
  }
}

@immutable
class Game {
  const Game({
    required this.id,
    required this.name,
    required this.minPlayers,
    required this.maxPlayers,
  }) : assert(minPlayers >= 1 && minPlayers <= maxPlayers);

  final String id;
  final String name;
  final int minPlayers;
  final int maxPlayers;

  bool fits(int players) => players >= minPlayers && players <= maxPlayers;

  String get playersLabel => maxPlayers == 1
      ? '1 jogador'
      : minPlayers == maxPlayers
      ? '$minPlayers jogadores'
      : '$minPlayers a $maxPlayers jogadores';
}

/// Os jogos do grupo e quem tem cada um.
@immutable
class GameLibrary {
  const GameLibrary({required this.games, required this.owners});

  final List<Game> games;

  /// id do jogo → quem tem.
  final Map<String, Set<String>> owners;

  Set<String> ownersOf(String gameId) => owners[gameId] ?? const {};

  Game? byId(String id) => games.where((g) => g.id == id).firstOrNull;

  /// Jogos que todos em [players] têm e que cabem nesse número de pessoas,
  /// em ordem alfabética.
  List<Game> playableBy(Iterable<String> players) {
    final group = players.toSet();
    return [
      for (final g in games)
        if (group.isNotEmpty &&
            g.fits(group.length) &&
            ownersOf(g.id).containsAll(group))
          g,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }
}

/// Sorteia um jogo de [options] que não esteja em [excluded]. Nulo se não
/// sobrar nenhum.
Game? drawGame(
  List<Game> options,
  Random random, {
  Set<String> excluded = const {},
}) {
  final left = [
    for (final g in options)
      if (!excluded.contains(g.id)) g,
  ];
  if (left.isEmpty) return null;
  return left[random.nextInt(left.length)];
}

/// Os jogos que o Chamado mostra à vista, no máximo [limite]: primeiro os que
/// o grupo chamou por último ([recentes], ids do mais novo para o mais velho,
/// com repetição), depois os outros em ordem alfabética. Com a biblioteca da
/// Steam inteira, a lista toda não cabia na tela; o resto fica na busca.
List<Game> jogosAVista(
  List<Game> jogaveis,
  Iterable<String> recentes, {
  int limite = 6,
}) {
  final porId = {for (final g in jogaveis) g.id: g};
  final escolhidos = <Game>[];
  for (final id in recentes) {
    if (escolhidos.length == limite) return escolhidos;
    final g = porId.remove(id);
    if (g != null) escolhidos.add(g);
  }
  final resto = porId.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return [...escolhidos, ...resto.take(limite - escolhidos.length)];
}
