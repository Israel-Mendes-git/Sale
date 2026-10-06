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
    try {
      for (final gameId in _marcar ?? const <String>{}) {
        await repo.setOwnsGame(
          gameId: gameId,
          userId: widget.userId,
          owns: true,
        );
      }
      final trazer = [
        for (final jogo in cruzado.fora)
          if (_trazer.contains(jogo.nome)) jogo,
      ];
      // A faixa de jogadores sai das categorias da loja. Sem elas (a loja
      // não respondeu, o jogo saiu dela), fica a faixa larga, que não tira o
      // jogo de nenhum sorteio. Dá para ajustar depois na biblioteca.
      final categorias = await repo
          .steamCategories([for (final j in trazer) ?j.appId])
          .catchError((_) => <int, List<int>>{});
      for (final jogo in trazer) {
        final faixa =
            faixaPelaSteam(categorias[jogo.appId] ?? const []) ??
            (min: 1, max: 10);
        await repo.addGame(
          name: jogo.nome,
          minPlayers: faixa.min,
          maxPlayers: faixa.max,
          addedBy: widget.userId,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Não deu para importar: $e')));
      }
    } finally {
      if (mounted) setState(() => _importando = false);
    }
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
                  Text(
                    'Já estão na biblioteca do grupo',
                    style: theme.textTheme.titleSmall,
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
                  Text(
                    'Trazer para a biblioteca',
                    style: theme.textTheme.titleSmall,
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

String _horas(int h) => h == 0
    ? 'nunca jogado'
    : h == 1
    ? '1 hora jogada'
    : '$h horas jogadas';

String _rotulo(int marcar, int trazer) => [
  if (marcar > 0) 'marcar $marcar',
  if (trazer > 0) 'trazer $trazer',
].join(' e ').replaceFirstMapped(RegExp('^.'), (m) => m[0]!.toUpperCase());
