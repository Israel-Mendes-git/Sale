import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/avatar.dart';

/// Minutos a partir de agora; nulo = agora.
const _whenOptions = <int?>[null, 15, 30, 60];

/// Escolha de jogo: nulo = qualquer coisa; [_draw] = sortear; senão, o id.
const _draw = '__sortear__';

class NewChamadoSheet extends ConsumerStatefulWidget {
  const NewChamadoSheet({
    super.key,
    required this.conversation,
    required this.userId,
  });

  final Conversation conversation;
  final String userId;

  @override
  ConsumerState<NewChamadoSheet> createState() => _NewChamadoSheetState();
}

class _NewChamadoSheetState extends ConsumerState<NewChamadoSheet> {
  late final Set<String> _targets = {
    for (final id in widget.conversation.memberIds)
      if (id != widget.userId) id,
  };
  String? _choice;
  final _note = TextEditingController();
  int? _inMinutes;
  var _sending = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  String? _clean(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  /// A escolha vale só se o jogo ainda cabe em quem está sendo chamado.
  String? _effectiveChoice(List<Game> playable) {
    if (_choice == _draw) return playable.isEmpty ? null : _draw;
    if (_choice != null && playable.every((g) => g.id != _choice)) return null;
    return _choice;
  }

  List<Game> get _playable =>
      ref.read(gamesProvider).value?.playableBy({widget.userId, ..._targets}) ??
      const [];

  Future<void> _fire() async {
    // Lê a escolha agora, não a da última montagem da tela.
    final choice = _effectiveChoice(_playable);
    setState(() => _sending = true);
    await ref
        .read(repositoryProvider)
        .sendChamado(
          conversationId: widget.conversation.id,
          authorId: widget.userId,
          targetIds: _targets.toList(),
          gameId: choice == _draw ? null : choice,
          drawGame: choice == _draw,
          note: _clean(_note),
          scheduledFor: _inMinutes == null
              ? null
              : ref.read(clockProvider)().add(Duration(minutes: _inMinutes!)),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final theme = Theme.of(context);
    final others = [
      for (final id in widget.conversation.memberIds)
        if (id != widget.userId) repo.profile(id),
    ];
    ref.watch(gamesProvider);
    final playable = _playable;
    final choice = _effectiveChoice(playable);

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
            Text('🦇 Novo Chamado', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text('Chamar', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final p in others)
                  FilterChip(
                    avatar: Avatar(p, radius: 10),
                    label: Text(p.name),
                    selected: _targets.contains(p.id),
                    onSelected: (on) => setState(
                      () => on ? _targets.add(p.id) : _targets.remove(p.id),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Jogo', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: const Text('Qualquer coisa'),
                  selected: choice == null,
                  onSelected: (_) => setState(() => _choice = null),
                ),
                ChoiceChip(
                  label: const Text('🎲 Sortear'),
                  selected: choice == _draw,
                  onSelected: playable.isEmpty
                      ? null
                      : (_) => setState(() => _choice = _draw),
                ),
                for (final g in playable)
                  ChoiceChip(
                    label: Text(g.name),
                    selected: choice == g.id,
                    onSelected: (_) => setState(() => _choice = g.id),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              playable.isEmpty
                  ? 'Nenhum jogo que todos aqui têm. Marque os seus na aba Jogos.'
                  : 'Só aparecem os jogos que todos aqui têm e que cabem '
                        '${_targets.length + 1} pessoas.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Text('Quando', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              children: [
                for (final m in _whenOptions)
                  ChoiceChip(
                    label: Text(m == null ? 'Agora' : 'Em $m min'),
                    selected: _inMinutes == m,
                    onSelected: (_) => setState(() => _inMinutes = m),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Recado (opcional)',
                hintText: 'Partida rápida, só 1 hora…',
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _targets.isEmpty || _sending ? null : _fire,
                icon: const Text('🦇', style: TextStyle(fontSize: 18)),
                label: const Text('Disparar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
