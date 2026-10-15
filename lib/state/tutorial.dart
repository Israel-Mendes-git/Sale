import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings.dart';

/// As partes do tutorial: a apresentação da primeira abertura e uma dica por
/// tela, cada uma mostrada uma vez só.
enum Dica { boasVindas, conversas, chat, chamado, semana, jogos }

/// O que esta pessoa já viu, guardado no aparelho. Quem já usava o app antes
/// do tutorial também o vê uma vez: a chave é nova.
final tutorialProvider = NotifierProvider<Tutorial, Set<Dica>>(Tutorial.new);

class Tutorial extends Notifier<Set<Dica>> {
  static const chave = 'tutorial.visto';

  @override
  Set<Dica> build() {
    final salvo = ref.watch(settingsStoreProvider).read(chave) ?? '';
    return {
      for (final nome in salvo.split(',')) ?Dica.values.asNameMap()[nome],
    };
  }

  bool viu(Dica dica) => state.contains(dica);

  Future<void> marcar(Dica dica) async {
    if (viu(dica)) return;
    state = {...state, dica};
    await _salvar();
  }

  /// "Como usar", no perfil: as dicas voltam a aparecer. A apresentação o
  /// perfil abre por conta própria; se voltasse a valer aqui, ela tomaria o
  /// lugar das abas por baixo do perfil.
  Future<void> rever() async {
    state = {if (viu(Dica.boasVindas)) Dica.boasVindas};
    await _salvar();
  }

  Future<void> _salvar() => ref
      .read(settingsStoreProvider)
      .write(chave, [for (final d in state) d.name].join(','));
}
