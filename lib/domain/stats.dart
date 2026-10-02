import 'package:flutter/foundation.dart';

import 'models.dart';

/// Placar e estatísticas: o que o grupo fez com os Chamados até agora.
///
/// Conta puro, sem servidor: recebe os Chamados e devolve os números. O
/// placar do atraso compara o que cada um prometeu ("chego em 20 min") com a
/// hora em que marcou "Cheguei".

/// Os números de uma pessoa.
@immutable
class PlayerStats {
  const PlayerStats({
    required this.userId,
    this.called = 0,
    this.invited = 0,
    this.answered = 0,
    this.accepted = 0,
    this.refused = 0,
    this.ignored = 0,
    this.arrivals = 0,
    this.lateTotal = Duration.zero,
    this.worstLate,
  });

  final String userId;

  /// Chamados que ela disparou.
  final int called;

  /// Vezes em que foi chamada.
  final int invited;

  /// Quantas dessas ela respondeu.
  final int answered;

  /// Respostas de "vou" — na hora ou depois.
  final int accepted;

  /// Respostas de "hoje não".
  final int refused;

  /// Chamados que se encerraram sem ela responder.
  final int ignored;

  /// Chegadas marcadas, entre as vezes em que prometeu ir.
  final int arrivals;

  /// Soma da diferença entre o prometido e a chegada. Chegar antes conta
  /// negativo, e é assim que a pontualidade se paga.
  final Duration lateTotal;

  /// O pior atraso de todos.
  final Duration? worstLate;

  /// Atraso médio de quem já marcou chegada.
  Duration? get averageLate => arrivals == 0
      ? null
      : Duration(seconds: (lateTotal.inSeconds / arrivals).round());
}

/// Quantas vezes um jogo foi o jogo do Chamado.
@immutable
class GameStats {
  const GameStats({required this.name, required this.times});

  final String name;
  final int times;
}

/// Tudo junto, do jeito que a tela do placar mostra.
@immutable
class Stats {
  const Stats({
    required this.players,
    required this.games,
    required this.chamados,
  });

  static const empty = Stats(players: [], games: [], chamados: 0);

  /// Uma entrada por pessoa, na ordem em que foi pedida.
  final List<PlayerStats> players;

  /// Jogos do mais ao menos chamado.
  final List<GameStats> games;

  /// Quantos Chamados entraram na conta.
  final int chamados;

  bool get isEmpty => chamados == 0;

  PlayerStats? forUser(String userId) =>
      players.where((p) => p.userId == userId).firstOrNull;

  /// Placar do atraso: do mais pontual ao mais atrasado. Só entra quem já
  /// prometeu e marcou chegada.
  List<PlayerStats> get byPunctuality {
    final withArrivals = [
      for (final p in players)
        if (p.arrivals > 0) p,
    ];
    withArrivals.sort((a, b) {
      final late = a.averageLate!.compareTo(b.averageLate!);
      return late != 0 ? late : a.userId.compareTo(b.userId);
    });
    return withArrivals;
  }

  /// Quem mais chama.
  List<PlayerStats> get byCalls => _ranking((p) => p.called);

  /// Quem mais diz "hoje não".
  List<PlayerStats> get byRefusals => _ranking((p) => p.refused);

  List<PlayerStats> _ranking(int Function(PlayerStats) value) {
    final ranked = [
      for (final p in players)
        if (value(p) > 0) p,
    ];
    ranked.sort((a, b) {
      final diff = value(b).compareTo(value(a));
      return diff != 0 ? diff : a.userId.compareTo(b.userId);
    });
    return ranked;
  }
}

/// Soma os [chamados]. [members] entra na conta mesmo sem história, para
/// quem nunca chamou nem foi chamado aparecer na lista com zero.
Stats computeStats(
  Iterable<Chamado> chamados, {
  Iterable<String> members = const [],
}) {
  final tallies = <String, _Tally>{};
  _Tally of(String userId) => tallies.putIfAbsent(userId, () => _Tally(userId));
  for (final id in members) {
    of(id);
  }

  final games = <String, int>{};
  var total = 0;

  for (final chamado in chamados) {
    total++;
    of(chamado.authorId).called++;
    final game = chamado.game;
    if (game != null) games[game] = (games[game] ?? 0) + 1;

    for (final entry in chamado.responses.entries) {
      final tally = of(entry.key);
      tally.invited++;
      final response = entry.value;
      if (response == null) {
        // Chamado que já acabou e ela nunca respondeu.
        if (!chamado.isOpen) tally.ignored++;
        continue;
      }
      tally.answered++;
      switch (response.reply.kind) {
        case ReplyKind.yes:
        case ReplyKind.later:
          tally.accepted++;
        case ReplyKind.no:
          tally.refused++;
        case ReplyKind.snooze:
          // "Me chama daqui a pouco" não é sim nem não.
          break;
      }
      final late = chamado.lateBy(entry.key);
      if (late != null) {
        tally.arrivals++;
        tally.lateTotal += late;
        final worst = tally.worstLate;
        if (worst == null || late > worst) tally.worstLate = late;
      }
    }
  }

  final ranking = games.entries.toList()
    ..sort((a, b) {
      final diff = b.value.compareTo(a.value);
      return diff != 0 ? diff : a.key.compareTo(b.key);
    });

  return Stats(
    players: [for (final tally in tallies.values) tally.done()],
    games: [for (final e in ranking) GameStats(name: e.key, times: e.value)],
    chamados: total,
  );
}

/// Caderno de somas de uma pessoa enquanto a conta roda.
class _Tally {
  _Tally(this.userId);

  final String userId;
  var called = 0;
  var invited = 0;
  var answered = 0;
  var accepted = 0;
  var refused = 0;
  var ignored = 0;
  var arrivals = 0;
  var lateTotal = Duration.zero;
  Duration? worstLate;

  PlayerStats done() => PlayerStats(
    userId: userId,
    called: called,
    invited: invited,
    answered: answered,
    accepted: accepted,
    refused: refused,
    ignored: ignored,
    arrivals: arrivals,
    lateTotal: lateTotal,
    worstLate: worstLate,
  );
}
