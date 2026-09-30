import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';

/// Biblioteca de jogos do grupo: cada um marca os que tem.
class GamesScreen extends ConsumerStatefulWidget {
  const GamesScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<GamesScreen> createState() => _GamesScreenState();
}

class _GamesScreenState extends ConsumerState<GamesScreen> {
  /// Mostrar só os que todo o grupo tem.
  var _onlyShared = false;

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(gamesProvider);
    final group = (ref.watch(conversationsProvider(widget.userId)).value ?? [])
        .where((c) => c.kind == ConversationKind.group)
        .firstOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Jogos')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Adicionar jogo'),
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _NewGameSheet(userId: widget.userId),
        ),
      ),
      body: library.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (lib) {
          final all = [...lib.games]
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );
          final shared = [
            for (final g in all)
              if (group != null &&
                  lib.ownersOf(g.id).containsAll(group.memberIds))
                g,
          ];
          final shown = _onlyShared ? shared : all;

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'Marque os jogos que você tem. O Chamado e o sorteio usam só '
                  'os que todos os chamados têm.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (group != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text('Todos (${all.length})'),
                        selected: !_onlyShared,
                        onSelected: (_) => setState(() => _onlyShared = false),
                      ),
                      ChoiceChip(
                        label: Text('Que todo o grupo tem (${shared.length})'),
                        selected: _onlyShared,
                        onSelected: (_) => setState(() => _onlyShared = true),
                      ),
                    ],
                  ),
                ),
              if (shown.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Nenhum jogo aqui ainda.'),
                ),
              for (final g in shown)
                _GameTile(game: g, library: lib, userId: widget.userId),
            ],
          );
        },
      ),
    );
  }
}

class _GameTile extends ConsumerWidget {
  const _GameTile({
    required this.game,
    required this.library,
    required this.userId,
  });

  final Game game;
  final GameLibrary library;
  final String userId;

  Future<void> _confirmRemove(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remover ${game.name}?'),
        content: const Text('Sai da biblioteca do grupo inteiro.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(repositoryProvider).removeGame(game.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final owners = library.ownersOf(game.id);
    final mine = owners.contains(userId);
    final others = [
      for (final id in owners)
        if (id != userId) repo.profile(id).name,
    ]..sort();

    final who = [if (mine) 'você', ...others];
    return ListTile(
      title: Text(game.name),
      subtitle: Text(
        '${game.playersLabel} · '
        '${who.isEmpty ? 'ninguém marcou' : 'têm: ${who.join(', ')}'}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilterChip(
            label: const Text('Eu tenho'),
            selected: mine,
            onSelected: (on) =>
                repo.setOwnsGame(gameId: game.id, userId: userId, owns: on),
          ),
          PopupMenuButton<void>(
            tooltip: 'Opções de ${game.name}',
            itemBuilder: (_) => [
              PopupMenuItem(
                onTap: () => _confirmRemove(context, ref),
                child: const Text('Remover da biblioteca'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NewGameSheet extends ConsumerStatefulWidget {
  const _NewGameSheet({required this.userId});

  final String userId;

  @override
  ConsumerState<_NewGameSheet> createState() => _NewGameSheetState();
}

class _NewGameSheetState extends ConsumerState<_NewGameSheet> {
  final _name = TextEditingController();
  var _min = 1;
  var _max = 5;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await ref
          .read(repositoryProvider)
          .addGame(
            name: _name.text,
            minPlayers: _min,
            maxPlayers: _max,
            addedBy: widget.userId,
          );
      if (mounted) Navigator.pop(context);
    } on ArgumentError {
      setState(() => _error = 'Escreva o nome do jogo.');
    } on StateError catch (e) {
      setState(() => _error = e.message);
    }
  }

  Widget _stepper(
    String label,
    int value,
    int min,
    int max,
    void Function(int) set,
  ) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          tooltip: 'Menos ($label)',
          onPressed: value > min ? () => setState(() => set(value - 1)) : null,
          icon: const Icon(Icons.remove),
        ),
        SizedBox(width: 32, child: Text('$value', textAlign: TextAlign.center)),
        IconButton(
          tooltip: 'Mais ($label)',
          onPressed: value < max ? () => setState(() => set(value + 1)) : null,
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Novo jogo', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: maxGameNameLength,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Nome do jogo',
                errorText: _error,
              ),
            ),
            _stepper('Mínimo de jogadores', _min, 1, _max, (v) => _min = v),
            _stepper(
              'Máximo de jogadores',
              _max,
              _min,
              maxPlayersLimit,
              (v) => _max = v,
            ),
            const SizedBox(height: 8),
            Text(
              'Entra marcado como seu. Os outros marcam se também tiverem.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: const Text('Salvar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
