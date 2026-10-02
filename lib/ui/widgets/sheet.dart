import 'package:flutter/material.dart';

/// Conteúdo de uma folha (bottom sheet), com espaço em volta.
///
/// O recuo de baixo conta as duas coisas que o Android desenha por cima da
/// tela: o teclado e a barra de botões do celular. Sem contar a barra, o
/// último botão da folha — "Disparar", por exemplo — nasce atrás dos botões
/// do sistema e quase não dá para acertar.
class SheetBody extends StatelessWidget {
  const SheetBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => SafeArea(
    // A folha nasce no meio da tela: em cima não há o que desviar.
    top: false,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: child,
    ),
  );
}
