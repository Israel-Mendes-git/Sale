import 'dart:math';

import 'package:flutter/foundation.dart';

const maxGameNameLength = 40;
const maxPlayersLimit = 32;

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

  String get playersLabel => minPlayers == maxPlayers
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
