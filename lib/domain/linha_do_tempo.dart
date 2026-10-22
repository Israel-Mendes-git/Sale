/// O que a conversa mostra entre as bolhas: o dia que começa, onde começam
/// as mensagens que você ainda não tinha visto, e quais bolhas emendam na de
/// cima (a mesma pessoa, logo em seguida, sem repetir o nome).
library;

import 'models.dart';

/// Mensagens da mesma pessoa com até este intervalo viram uma sequência.
const emendaAte = Duration(minutes: 5);

sealed class ItemDaConversa {
  const ItemDaConversa();
}

/// O dia que começa, à meia-noite do horário do aparelho.
class InicioDoDia extends ItemDaConversa {
  const InicioDoDia(this.dia);
  final DateTime dia;
}

/// "N mensagens novas": daqui para baixo, o que chegou desde a última vez.
class MensagensNovas extends ItemDaConversa {
  const MensagensNovas(this.quantas);
  final int quantas;
}

class Bolha extends ItemDaConversa {
  const Bolha(this.message, {required this.emendada});
  final Message message;

  /// Continua a bolha de cima: mesma pessoa, mesmo dia, logo depois.
  final bool emendada;
}

DateTime _dia(DateTime t) {
  final local = t.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// A conversa em ordem, da mais antiga para a mais nova, com os separadores.
///
/// [lidaAte] é até onde [userId] tinha visto ao abrir a conversa: a faixa de
/// novas vai antes da primeira mensagem de outra pessoa depois disso. Nulo —
/// nunca abriu — não marca nada, porque seria a conversa inteira.
List<ItemDaConversa> linhaDoTempo(
  List<Message> mensagens, {
  required String userId,
  DateTime? lidaAte,
}) {
  final itens = <ItemDaConversa>[];
  final novas = lidaAte == null
      ? 0
      : mensagens
            .where((m) => m.authorId != userId && m.createdAt.isAfter(lidaAte))
            .length;
  var faixaPosta = novas == 0;
  Message? anterior;
  for (final m in mensagens) {
    final dia = _dia(m.createdAt);
    final novoDia = anterior == null || _dia(anterior.createdAt) != dia;
    if (novoDia) itens.add(InicioDoDia(dia));
    var quebrou = novoDia;
    if (!faixaPosta && m.authorId != userId && m.createdAt.isAfter(lidaAte!)) {
      itens.add(MensagensNovas(novas));
      faixaPosta = true;
      quebrou = true;
    }
    final emendada =
        !quebrou &&
        anterior != null &&
        !m.isChamado &&
        !anterior.isChamado &&
        anterior.authorId == m.authorId &&
        m.createdAt.difference(anterior.createdAt) <= emendaAte;
    itens.add(Bolha(m, emendada: emendada));
    anterior = m;
  }
  return itens;
}
