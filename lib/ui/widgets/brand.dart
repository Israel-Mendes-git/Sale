import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A marca do app: um controle com o chamado saindo dele.
///
/// O mesmo desenho (`assets/marca.svg`) vira o ícone na tela inicial do
/// celular, então a marca é sempre a mesma coisa em todo lugar. A cor vem de
/// quem usa o widget, para acompanhar o tema escolhido.
class Marca extends StatelessWidget {
  const Marca({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cor = color ?? Theme.of(context).colorScheme.primary;
    return SvgPicture.asset(
      'assets/marca.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(cor, BlendMode.srcIn),
      semanticsLabel: 'Sale?',
    );
  }
}
