import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/games.dart';
import '../../domain/models.dart';
import '../../domain/sounds.dart';
import '../../domain/steam.dart';
import '../../push/sons.dart';
import '../../state/providers.dart';
import '../../state/tutorial.dart';
import '../widgets/avatar.dart';
import '../widgets/brand.dart';
import '../widgets/dica.dart';

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

  /// A biblioteca inteira, com busca pelo nome.
  Future<void> _escolherOutroJogo(List<Game> playable) async {
    final escolhido = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.85,
        child: _BuscaDeJogo(jogos: playable),
      ),
    );
    if (escolhido != null && mounted) setState(() => _choice = escolhido);
  }

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
    // Com a biblioteca da Steam inteira, todos os jogos não cabem na tela: à
    // vista ficam os chamados por último, e o escolhido na busca.
    final historico = [...?ref.watch(historicoProvider(widget.userId)).value]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final aVista = jogosAVista(playable, [
      for (final c in historico)
        if (c.conversationId == widget.conversation.id) ?c.gameId,
    ]);
    if (playable.where((g) => g.id == choice).firstOrNull case final g?
        when !aVista.contains(g)) {
      aVista.insert(0, g);
    }

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
            const DicaCard(
              dica: Dica.chamado,
              margin: EdgeInsets.only(bottom: 12),
              texto:
                  'Toque nos nomes para escolher quem chamar. No jogo, '
                  '"🎲 Sortear" escolhe entre os que todos os chamados têm, e '
                  'cada um pode vetar o sorteado uma vez. Em "Quando", marque '
                  'para mais tarde: o app dispara sozinho na hora.',
            ),
            Text('Chamar', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            // Sem ninguém para escolher, o "Disparar" nunca acende; diz por quê.
            if (others.isEmpty)
              Text(
                switch (ref
                    .watch(groupsProvider(widget.userId))
                    .value
                    ?.firstOrNull) {
                  final grupo? =>
                    'Só tem você no grupo. Convide o pessoal com o código '
                        '${grupo.inviteCode} (Meu perfil → Seu grupo).',
                  null => 'Só tem você aqui. Convide o pessoal para o grupo.',
                },
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
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
                for (final g in aVista)
                  ChoiceChip(
                    label: Text(g.name),
                    selected: choice == g.id,
                    onSelected: (_) => setState(() => _choice = g.id),
                  ),
                if (playable.length > aVista.length)
                  ActionChip(
                    avatar: const Icon(Icons.search, size: 18),
                    label: Text('Outro jogo (${playable.length})'),
                    onPressed: () => _escolherOutroJogo(playable),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              playable.isEmpty
                  ? 'Nenhum jogo que todos aqui têm. Marque os seus na aba Jogos.'
                  : _targets.isEmpty
                  ? 'Só aparecem os jogos que você tem e que dá para jogar '
                        'sozinho.'
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

/// A busca de "Outro jogo": um campo e a lista filtrada pelo nome, sem caixa
/// nem pontuação.
class _BuscaDeJogo extends StatefulWidget {
  const _BuscaDeJogo({required this.jogos});

  final List<Game> jogos;

  @override
  State<_BuscaDeJogo> createState() => _BuscaDeJogoState();
}

class _BuscaDeJogoState extends State<_BuscaDeJogo> {
  var _busca = '';

  @override
  Widget build(BuildContext context) {
    final termo = normalizarNome(_busca);
    final jogos = [
      for (final g in widget.jogos)
        if (normalizarNome(g.name).contains(termo)) g,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar jogo',
              ),
              onChanged: (t) => setState(() => _busca = t),
            ),
          ),
          Expanded(
            child: jogos.isEmpty
                ? Center(child: Text('Nenhum jogo com "$_busca".'))
                : ListView.builder(
                    itemCount: jogos.length,
                    itemBuilder: (context, i) => ListTile(
                      title: Text(jogos[i].name),
                      subtitle: Text(jogos[i].playersLabel),
                      onTap: () => Navigator.pop(context, jogos[i].id),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
