/// O que a lista de conversas mostra, e em que ordem: as fixadas no topo, e
/// o filtro e a busca de quem está procurando uma conversa.
library;

import 'models.dart';

enum FiltroDeConversas { todas, naoLidas, grupos, individuais }

/// As conversas de [lista] que passam no [filtro] e na [busca], com as
/// fixadas em cima (a fixada por último primeiro) e o resto na ordem em que
/// vieram — a da mensagem mais recente.
///
/// [titulo] é o nome que a lista mostra da conversa, já sem acento e em
/// minúsculas, do mesmo jeito que [busca]; [naoLida] diz se a conversa tem o
/// que ler.
List<Conversation> conversasDaLista(
  List<Conversation> lista, {
  FiltroDeConversas filtro = FiltroDeConversas.todas,
  String busca = '',
  required String Function(Conversation) titulo,
  required bool Function(Conversation) naoLida,
}) {
  bool passa(Conversation c) {
    if (busca.isNotEmpty && !titulo(c).contains(busca)) return false;
    return switch (filtro) {
      FiltroDeConversas.todas => true,
      FiltroDeConversas.naoLidas => naoLida(c),
      FiltroDeConversas.grupos => c.kind == ConversationKind.group,
      FiltroDeConversas.individuais => c.kind == ConversationKind.direct,
    };
  }

  final fixadas = [
    for (final c in lista)
      if (c.isPinned && passa(c)) c,
  ]..sort((a, b) => b.pinnedAt!.compareTo(a.pinnedAt!));
  return [
    ...fixadas,
    for (final c in lista)
      if (!c.isPinned && passa(c)) c,
  ];
}
