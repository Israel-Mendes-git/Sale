import 'package:flutter/foundation.dart';

/// A do dia: o grupo elege a frase, o momento ou o áudio do dia.
///
/// Qualquer um indica uma mensagem do dia na conversa do grupo, cada um tem um
/// voto (que pode trocar) e, quando o dia vira, a mais votada fica no Hall das
/// do dia. As regras moram no banco (migração `a_do_dia`); aqui fica o que as
/// telas precisam para mostrar a disputa.

/// O dia vira às 6h da manhã, não à meia-noite: o momento das 23h50 ainda é de
/// hoje para quem está jogando de madrugada.
const viradaDoDia = Duration(hours: 6);

/// O dia da disputa a que um instante pertence (só a data, sem hora).
DateTime diaDoDestaque(DateTime instante) {
  final local = instante.toLocal().subtract(viradaDoDia);
  return DateTime(local.year, local.month, local.day);
}

/// Uma vencedora do Hall.
@immutable
class Destaque {
  const Destaque({required this.dia, required this.messageId, this.votos = 0});

  final DateTime dia;

  /// Nula quando a mensagem foi apagada depois: o dia fica no Hall.
  final String? messageId;
  final int votos;
}

/// A disputa de hoje e as que já ganharam, na conversa do grupo.
@immutable
class DoDia {
  const DoDia({
    required this.hoje,
    this.indicadas = const {},
    this.votos = const {},
    this.hall = const [],
  });

  /// O dia da disputa aberta.
  final DateTime hoje;

  /// As indicadas de hoje: mensagem -> quem indicou, na ordem em que vieram.
  final Map<String, String> indicadas;

  /// Os votos de hoje: pessoa -> mensagem.
  final Map<String, String> votos;

  /// As que já ganharam, da mais nova para a mais antiga.
  final List<Destaque> hall;

  int votosDe(String messageId) =>
      votos.values.where((m) => m == messageId).length;

  /// A do dia que [messageId] ganhou, se ganhou alguma.
  Destaque? vitoriaDe(String messageId) =>
      hall.where((d) => d.messageId == messageId).firstOrNull;
}
