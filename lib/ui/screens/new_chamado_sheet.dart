import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/avatar.dart';

/// Minutos a partir de agora; nulo = agora.
const _whenOptions = <int?>[null, 15, 30, 60];

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
  final _game = TextEditingController();
  final _note = TextEditingController();
  int? _inMinutes;
  var _sending = false;

  @override
  void dispose() {
    _game.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _clean(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _fire() async {
    setState(() => _sending = true);
    await ref
        .read(repositoryProvider)
        .sendChamado(
          conversationId: widget.conversation.id,
          authorId: widget.userId,
          targetIds: _targets.toList(),
          game: _clean(_game),
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
            TextField(
              controller: _game,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Jogo',
                hintText: 'Vazio = qualquer coisa',
              ),
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
