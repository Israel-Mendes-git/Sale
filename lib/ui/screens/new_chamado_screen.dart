import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../domain/sounds.dart';
import '../../push/sons.dart';
import '../../state/providers.dart';
import '../widgets/avatar.dart';
import '../widgets/brand.dart';

/// Minutos a partir de agora; nulo = agora.
const _whenOptions = <int?>[null, 15, 30, 60];

/// Escolha de jogo: nulo = qualquer coisa; [_draw] = sortear; senão, o id.
const _draw = '__sortear__';

/// Monta o Chamado: quem, qual jogo, quando e o recado.
///
/// Tela cheia, e não uma folha subindo do rodapé: são quatro escolhas, e a
/// lista de jogos cresce junto com a biblioteca do grupo. Na folha o
/// "Disparar" terminava rente aos botões do celular, difícil de acertar;
/// aqui ele fica parado no rodapé, com o conteúdo rolando atrás.
class NewChamadoScreen extends ConsumerStatefulWidget {
  const NewChamadoScreen({
    super.key,
    required this.conversation,
    required this.userId,
  });

  final Conversation conversation;
  final String userId;

  @override
  ConsumerState<NewChamadoScreen> createState() => _NewChamadoScreenState();
}

class _NewChamadoScreenState extends ConsumerState<NewChamadoScreen> {
  late final Set<String> _targets = {
    for (final id in widget.conversation.memberIds)
      if (id != widget.userId) id,
  };
  String? _choice;
  final _note = TextEditingController();
  int? _inMinutes;
  var _sending = false;

  /// O som escolhido para este Chamado; nulo = o de "Meu perfil → Som do
  /// Chamado".
  String? _sound;

  @override
  void dispose() {
    _note.dispose();
    pararSom();
    super.dispose();
  }

  /// O som que vai tocar: o escolhido aqui, o do perfil, ou o da marca,
  /// nessa ordem.
  Sound? _chosenSound(List<Sound> sounds) {
    final id =
        _sound ?? ref.read(repositoryProvider).profile(widget.userId).soundId;
    return sounds.where((s) => s.id == id).firstOrNull ??
        sounds.where((s) => s.builtIn && s.file == defaultSoundKey).firstOrNull;
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
    final sound = _chosenSound(ref.read(soundsProvider).value ?? const []);
    setState(() => _sending = true);
    // Sem esperar: o Chamado não fica na mão de quem toca o som da prévia.
    unawaited(pararSom());
    await ref
        .read(repositoryProvider)
        .sendChamado(
          conversationId: widget.conversation.id,
          authorId: widget.userId,
          targetIds: _targets.toList(),
          soundId: sound?.id,
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
    final online =
        ref.watch(onlineProvider(widget.userId)).value ?? const <String>{};
    final scheme = theme.colorScheme;
    final others = [
      for (final id in widget.conversation.memberIds)
        if (id != widget.userId) repo.profile(id),
    ];
    ref.watch(gamesProvider);
    final playable = _playable;
    final choice = _effectiveChoice(playable);
    final sounds = ref.watch(soundsProvider).value ?? const <Sound>[];
    final sound = _chosenSound(sounds);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Marca(size: 22, color: scheme.secondary),
            const SizedBox(width: 8),
            const Text('Novo Chamado'),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chamar', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final p in others)
                  FilterChip(
                    avatar: ComPresenca(
                      online: online.contains(p.id),
                      size: 8,
                      child: Avatar(p, radius: 10),
                    ),
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
              runSpacing: 6,
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
            Text('Som', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final s in sounds)
                  ChoiceChip(
                    label: Text(s.name),
                    selected: sound?.id == s.id,
                    // Escolher é ouvir: ninguém escolhe som no escuro.
                    onSelected: (_) {
                      setState(() => _sound = s.id);
                      ouvirSom(s, baixar: repo.soundBytes);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'É este que toca no celular de quem você chama. Toque para '
              'ouvir; os do grupo ficam em "Meu perfil → Som do Chamado".',
              style: theme.textTheme.bodySmall,
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
          ],
        ),
      ),
      // Parado no rodapé, longe dos botões do celular: o Scaffold cuida de
      // levantá-lo quando o teclado abre.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _targets.isEmpty || _sending ? null : _fire,
              icon: Marca(size: 20, color: scheme.onPrimary),
              label: const Text('Disparar'),
            ),
          ),
        ),
      ),
    );
  }
}
