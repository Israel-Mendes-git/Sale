import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/steam.dart';
import '../../state/providers.dart';
import '../widgets/sheet.dart';

/// A importação da Steam, do começo ao fim: pede o perfil, busca os jogos e
/// mostra o que marcar e o que trazer para a biblioteca do grupo.
Future<void> importarDaSteam(
  BuildContext context,
  WidgetRef ref, {
  required String userId,
}) async {
  final perfil = await showDialog<String>(
    context: context,
    builder: (_) => const _PerfilDaSteam(),
  );
  if (perfil == null || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    const SnackBar(content: Text('Buscando os seus jogos na Steam…')),
  );
  final List<JogoDaSteam> jogos;
  try {
    jogos = await ref.read(repositoryProvider).steamLibrary(perfil);
  } catch (e) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(_mensagem(e))));
    return;
  }
  messenger.hideCurrentSnackBar();
  if (!context.mounted) return;
  if (jogos.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('A Steam não mostrou nenhum jogo.')),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.85,
      child: _Importacao(jogos: jogos, userId: userId),
    ),
  );
}

String _mensagem(Object e) =>
    e is StateError ? e.message : 'Não deu para falar com a Steam.';

/// Pede o perfil: o link, o ID ou o nome personalizado.
class _PerfilDaSteam extends StatefulWidget {
  const _PerfilDaSteam();

  @override
  State<_PerfilDaSteam> createState() => _PerfilDaSteamState();
}

class _PerfilDaSteamState extends State<_PerfilDaSteam> {
  final _campo = TextEditingController();

  @override
  void dispose() {
    _campo.dispose();
    super.dispose();
  }

  void _seguir() {
    final perfil = lerPerfilDaSteam(_campo.text);
    if (perfil != null) Navigator.pop(context, perfil);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Importar da Steam'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cole o link do seu perfil, ou só o nome personalizado. O perfil e a '
          'lista de jogos precisam estar públicos na Steam.',
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _campo,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'steamcommunity.com/id/…',
          ),
          onSubmitted: (_) => _seguir(),
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _seguir, child: const Text('Buscar')),
    ],
  );
}

/// O que veio da Steam: os jogos que já estão na biblioteca (marcados para
/// "tenho") e os que não estão (para trazer, escolhendo).
class _Importacao extends ConsumerStatefulWidget {
  const _Importacao({required this.jogos, required this.userId});

  final List<JogoDaSteam> jogos;
  final String userId;

  @override
  ConsumerState<_Importacao> createState() => _ImportacaoState();
}

class _ImportacaoState extends ConsumerState<_Importacao> {
  /// Os da biblioteca que vão ser marcados como meus, e os de fora que vão
  /// entrar nela, pelo nome.
  Set<String>? _marcar;
  final _trazer = <String>{};
  var _importando = false;

  Future<void> _importar(
    ({Map<String, JogoDaSteam> naBiblioteca, List<JogoDaSteam> fora}) cruzado,
  ) async {
    setState(() => _importando = true);
    final repo = ref.read(repositoryProvider);
    // Um jogo que dá errado não segura os outros: cada um tenta sozinho, e
    // o aviso do fim conta o que ficou de fora.
    final falhas = <String>[];
    var trazidos = 0;
    try {
      for (final gameId in _marcar ?? const <String>{}) {
        try {
          await repo.setOwnsGame(
            gameId: gameId,
            userId: widget.userId,
            owns: true,
          );
        } catch (_) {
          falhas.add(cruzado.naBiblioteca[gameId]?.nome ?? gameId);
        }
      }
      final trazer = [
        for (final jogo in cruzado.fora)
          if (_trazer.contains(jogo.nome)) jogo,
      ];
      final categorias = await _categorias(trazer);
      for (final jogo in trazer) {
        // A faixa de jogadores sai das categorias da loja. Sem elas (a loja
        // não respondeu, o jogo saiu dela), fica a faixa larga, que não tira
        // o jogo de nenhum sorteio. Dá para ajustar depois na biblioteca.
        final faixa =
            faixaPelaSteam(categorias[jogo.appId] ?? const []) ??
            (min: 1, max: 10);
        try {
          await repo.addGame(
            name: nomeParaBiblioteca(jogo.nome),
            minPlayers: faixa.min,
            maxPlayers: faixa.max,
            addedBy: widget.userId,
          );
          trazidos++;
        } catch (_) {
          falhas.add(jogo.nome);
        }
      }
    } finally {
      if (mounted) setState(() => _importando = false);
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    if (falhas.isNotEmpty) {
      messenger.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            '${trazidos > 0 ? 'Trouxe $trazidos. ' : ''}'
            '${falhas.length == 1 ? 'Ficou de fora' : 'Ficaram de fora'}: '
            '${falhas.take(5).join(', ')}'
            '${falhas.length > 5 ? ' e mais ${falhas.length - 5}' : ''}.',
          ),
        ),
      );
    }
  }

  /// As categorias da loja de todos os jogos a trazer. O servidor atende 30
  /// por pedido (a loja segura quem pede demais), então vai em levas; leva que
  /// falha só deixa aqueles jogos com a faixa larga.
  Future<Map<int, List<int>>> _categorias(List<JogoDaSteam> jogos) async {
    final repo = ref.read(repositoryProvider);
    final ids = [for (final j in jogos) ?j.appId];
    final todas = <int, List<int>>{};
    for (var i = 0; i < ids.length; i += 30) {
      final leva = ids.sublist(i, (i + 30).clamp(0, ids.length));
      todas.addAll(
        await repo.steamCategories(leva).catchError((_) => <int, List<int>>{}),
      );
    }
    return todas;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final biblioteca = ref.watch(gamesProvider).value;
    if (biblioteca == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final cruzado = cruzarComBiblioteca(widget.jogos, biblioteca.games);
    final jaTenho = {
      for (final id in cruzado.naBiblioteca.keys)
        if (biblioteca.ownersOf(id).contains(widget.userId)) id,
    };
    // Na primeira vez, tudo o que está na biblioteca e eu não marquei.
    final marcar = _marcar ??= {
      for (final id in cruzado.naBiblioteca.keys)
        if (!jaTenho.contains(id)) id,
    };
    final podeMarcar = [
      for (final id in cruzado.naBiblioteca.keys)
        if (!jaTenho.contains(id)) id,
    ];
    String nomeNoGrupo(String id) =>
        biblioteca.games.firstWhere((g) => g.id == id).name;

    return SheetBody(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                Text(
                  'Achei ${widget.jogos.length} jogos na sua Steam',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                if (cruzado.naBiblioteca.isNotEmpty) ...[
                  _Secao(
                    titulo: 'Já estão na biblioteca do grupo',
                    todos: podeMarcar.every(marcar.contains),
                    onTodos: podeMarcar.isEmpty
                        ? null
                        : (todos) => setState(
                            () => todos
                                ? marcar.addAll(podeMarcar)
                                : marcar.removeAll(podeMarcar),
                          ),
                  ),
                  for (final id in cruzado.naBiblioteca.keys)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: jaTenho.contains(id) || marcar.contains(id),
                      onChanged: jaTenho.contains(id)
                          ? null
                          : (v) => setState(
                              () => v! ? marcar.add(id) : marcar.remove(id),
                            ),
                      title: Text(nomeNoGrupo(id)),
                      subtitle: Text(
                        jaTenho.contains(id)
                            ? 'Já marcado como seu'
                            : 'Marcar que eu tenho',
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
                if (cruzado.fora.isNotEmpty) ...[
                  _Secao(
                    titulo: 'Trazer para a biblioteca',
                    todos: cruzado.fora.every((j) => _trazer.contains(j.nome)),
                    onTodos: (todos) => setState(
                      () => todos
                          ? _trazer.addAll([
                              for (final j in cruzado.fora) j.nome,
                            ])
                          : _trazer.clear(),
                    ),
                  ),
                  for (final jogo in cruzado.fora)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _trazer.contains(jogo.nome),
                      onChanged: (v) => setState(
                        () => v!
                            ? _trazer.add(jogo.nome)
                            : _trazer.remove(jogo.nome),
                      ),
                      title: Text(jogo.nome),
                      subtitle: Text(_horas(jogo.horas)),
                    ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _importando || (marcar.isEmpty && _trazer.isEmpty)
                  ? null
                  : () => _importar(cruzado),
              child: Text(
                _importando
                    ? 'Importando…'
                    : _rotulo(marcar.length, _trazer.length),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// O título de uma lista, com o "Marcar todos" / "Desmarcar todos" do lado.
class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.todos, this.onTodos});

  final String titulo;
  final bool todos;

  /// Nulo quando não há nada a marcar na lista.
  final ValueChanged<bool>? onTodos;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(titulo, style: Theme.of(context).textTheme.titleSmall),
      ),
      if (onTodos != null)
        TextButton(
          onPressed: () => onTodos!(!todos),
          child: Text(todos ? 'Desmarcar todos' : 'Marcar todos'),
        ),
    ],
  );
}

String _horas(int h) => h == 0
    ? 'nunca jogado'
    : h == 1
    ? '1 hora jogada'
    : '$h horas jogadas';

/// O texto do botão; sem nada escolhido, ele diz o que falta em vez de
/// ficar vazio.
String _rotulo(int marcar, int trazer) => marcar == 0 && trazer == 0
    ? 'Escolha o que importar'
    : [if (marcar > 0) 'marcar $marcar', if (trazer > 0) 'trazer $trazer']
          .join(' e ')
          .replaceFirstMapped(RegExp('^.'), (m) => m[0]!.toUpperCase());
