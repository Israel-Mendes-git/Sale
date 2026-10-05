import 'package:flutter/foundation.dart';
import 'package:quick_actions/quick_actions.dart';

/// Os atalhos do ícone do app: segurar o ícone na tela inicial e ir direto ao
/// que interessa, sem passar pela lista de conversas.

/// O atalho que abre o Chamado para o grupo.
const atalhoChamarGrupo = 'chamar_grupo';

/// O atalho tocado, até a tela de cima tratá-lo. Com o app fechado, o toque
/// chega assim que os atalhos são ligados, e espera aqui.
final atalhoTocado = ValueNotifier<String?>(null);

/// Registra os atalhos no ícone do app e passa a escutar os toques.
Future<void> ligarAtalhos() async {
  try {
    const atalhos = QuickActions();
    await atalhos.initialize((tipo) => atalhoTocado.value = tipo);
    await atalhos.setShortcutItems(const [
      ShortcutItem(
        type: atalhoChamarGrupo,
        localizedTitle: 'Chamar o grupo',
        icon: 'ic_atalho_chamar',
      ),
    ]);
  } catch (e) {
    // Sem atalho o app funciona igual: é só um caminho a mais.
    debugPrint('Atalhos desligados: $e');
  }
}
