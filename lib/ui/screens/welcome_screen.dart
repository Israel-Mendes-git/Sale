import 'package:flutter/material.dart';

import '../widgets/brand.dart';

/// A apresentação da primeira abertura: o Chamado, as abas e onde mora o
/// resto. Volta pelo "Como usar" do perfil.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onDone});

  /// Chamado no "Começar" e no "Pular".
  final VoidCallback onDone;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _pages = PageController();
  var _page = 0;

  static const _total = 4;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _total - 1) {
      widget.onDone();
      return;
    }
    _pages.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final last = _page == _total - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Visibility(
                visible: !last,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: TextButton(
                  onPressed: widget.onDone,
                  child: const Text('Pular'),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _Pagina(
                    figura: const Marca(size: 96),
                    titulo: 'Bem-vindo ao Sale?',
                    texto:
                        'O app para chamar os amigos pra jogar. Um toque e o '
                        'celular de todo mundo toca.',
                  ),
                  _Pagina(
                    figura: Marca(size: 96, color: scheme.secondary),
                    titulo: 'O Chamado',
                    texto:
                        'Na conversa, o botão com a marca, ao lado do campo de '
                        'texto, dispara o Chamado: escolha quem chamar, o jogo '
                        '(ou sorteie) e quando. Ele toca como uma ligação, até '
                        'com o celular bloqueado.\n\n'
                        'Quem é chamado responde com um toque — "Bora!", '
                        '"Chego em 20", "Hoje não" —, até pela própria '
                        'notificação.',
                  ),
                  const _Pagina(
                    figura: _Abas(),
                    titulo: 'Três abas',
                    texto:
                        'Conversas: o chat com o grupo e com cada um.\n\n'
                        'Semana: o encontro fixo e os horários em que todo '
                        'mundo está livre.\n\n'
                        'Jogos: a biblioteca do grupo, que o Chamado e o '
                        'sorteio usam.\n\n'
                        'Seu nome, sons, tema, Placar e o grupo ficam na sua '
                        'foto, no canto de cima.',
                  ),
                  const _Pagina(
                    figura: Icon(Icons.touch_app_outlined, size: 96),
                    titulo: 'Segure para mais',
                    texto:
                        'Muita coisa mora no toque longo e nos três '
                        'pontinhos: responder, reagir, fixar e editar '
                        'mensagens, indicar para a do dia, ajustar um jogo.\n\n'
                        'Na primeira vez em cada tela, uma dica mostra o que '
                        'tem lá. Para rever tudo: sua foto → Como usar.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  for (var i = 0; i < _total; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 6),
                      width: i == _page ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page
                            ? scheme.primary
                            : scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    child: Text(last ? 'Começar' : 'Próximo'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pagina extends StatelessWidget {
  const _Pagina({
    required this.figura,
    required this.titulo,
    required this.texto,
  });

  final Widget figura;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
      child: Column(
        children: [
          const SizedBox(height: 24),
          figura,
          const SizedBox(height: 32),
          Text(
            titulo,
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            texto,
            style: theme.textTheme.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// Os ícones das abas, iguais aos da barra de baixo.
class _Abas extends StatelessWidget {
  const _Abas();

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final icone in const [
          Icons.chat_bubble_outline,
          Icons.calendar_view_week_outlined,
          Icons.sports_esports_outlined,
        ])
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(icone, size: 56, color: cor),
          ),
      ],
    );
  }
}
