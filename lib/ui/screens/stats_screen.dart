import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../domain/stats.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../widgets/avatar.dart';

/// Placar e estatísticas do grupo.
///
/// O placar do atraso compara o que cada um prometeu ("chego em 20 min") com
/// a hora em que marcou "Cheguei". O resto é contagem dos Chamados: quem mais
/// chama, quem mais diz "hoje não" e o jogo que mais sai.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider(userId));
    return Scaffold(
      appBar: AppBar(title: const Text('Placar')),
      body: switch (stats) {
        AsyncError(:final error) => Center(child: Text('Erro: $error')),
        AsyncData(:final value) => _Board(stats: value, userId: userId),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Board extends ConsumerWidget {
  const _Board({required this.stats, required this.userId});

  final Stats stats;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (stats.isEmpty) return const _Empty();

    final theme = Theme.of(context);
    final repo = ref.watch(repositoryProvider);
    String name(String id) => id == userId ? 'Você' : repo.profile(id).name;

    final punctuality = stats.byPunctuality;
    final calls = stats.byCalls;
    final refusals = stats.byRefusals;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _Section(
          title: 'Placar do atraso',
          hint: 'A diferença entre o "chego em X min" e o "Cheguei".',
          child: punctuality.isEmpty
              ? const Text(
                  'Ninguém marcou "Cheguei" ainda. O botão aparece no card do '
                  'Chamado depois de você responder que vem.',
                )
              : Column(
                  children: [
                    for (final (i, p) in punctuality.indexed)
                      _PlayerRow(
                        profile: repo.profile(p.userId),
                        name: name(p.userId),
                        position: i,
                        value: lateLabel(p.averageLate!),
                        detail: _arrivalsDetail(p),
                      ),
                  ],
                ),
        ),
        _Section(
          title: 'Quem mais chama',
          child: Column(
            children: [
              for (final p in calls)
                _PlayerRow(
                  profile: repo.profile(p.userId),
                  name: name(p.userId),
                  value: '${p.called}',
                  bar: p.called / calls.first.called,
                ),
            ],
          ),
        ),
        _Section(
          title: 'Quem mais diz "hoje não"',
          child: refusals.isEmpty
              ? const Text('Ninguém recusou um Chamado ainda.')
              : Column(
                  children: [
                    for (final p in refusals)
                      _PlayerRow(
                        profile: repo.profile(p.userId),
                        name: name(p.userId),
                        value: '${p.refused}',
                        bar: p.refused / refusals.first.refused,
                        detail:
                            'de ${p.answered} '
                            '${p.answered == 1 ? 'resposta' : 'respostas'}',
                      ),
                  ],
                ),
        ),
        _Section(
          title: 'Jogo mais chamado',
          hint: 'Chamado de "qualquer coisa" não conta jogo.',
          child: stats.games.isEmpty
              ? const Text('Nenhum Chamado saiu com jogo escolhido.')
              : Column(
                  children: [
                    for (final g in stats.games)
                      _BarRow(
                        label: g.name,
                        value: '${g.times}',
                        bar: g.times / stats.games.first.times,
                      ),
                  ],
                ),
        ),
        Text(
          'Contando ${stats.chamados} '
          '${stats.chamados == 1 ? 'Chamado' : 'Chamados'}.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  String _arrivalsDetail(PlayerStats p) {
    final chegadas =
        '${p.arrivals} ${p.arrivals == 1 ? 'chegada' : 'chegadas'}';
    final worst = p.worstLate;
    // Com uma chegada só, a pior é a média: não vale repetir.
    if (worst == null || p.arrivals < 2) return chegadas;
    return '$chegadas · pior: ${lateLabel(worst)}';
  }
}

/// Um bloco do placar: título, explicação e conteúdo.
class _Section extends StatelessWidget {
  const _Section({required this.title, this.hint, required this.child});

  final String title;
  final String? hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (hint != null) Text(hint!, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// Linha de uma pessoa: lugar no placar, rosto, nome e o número que importa.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({
    required this.profile,
    required this.name,
    required this.value,
    this.position,
    this.detail,
    this.bar,
  });

  final Profile profile;
  final String name;
  final String value;

  /// Lugar no placar, começando em zero; nulo = sem numeração.
  final int? position;
  final String? detail;

  /// Tamanho da barra, de 0 a 1; nula = sem barra.
  final double? bar;

  @override
  Widget build(BuildContext context) {
    return _BarRow(
      label: name,
      value: value,
      detail: detail,
      bar: bar,
      leading: Row(
        children: [
          if (position != null)
            SizedBox(
              width: 26,
              child: Text(
                position == 0 ? '🥇' : '${position! + 1}º',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          Avatar(profile, radius: 14),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// Linha genérica: o que é à esquerda, o número à direita e a barra embaixo.
class _BarRow extends StatelessWidget {
  const _BarRow({
    required this.label,
    required this.value,
    this.detail,
    this.bar,
    this.leading,
  });

  final String label;
  final String value;
  final String? detail;
  final double? bar;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ?leading,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      value,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                if (bar != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(
                      value: bar!.clamp(0, 1),
                      minHeight: 6,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                if (detail != null)
                  Text(detail!, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.emoji_events_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            const Text(
              'O placar começa no primeiro Chamado.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(
              'Quem mais chama, quem mais recusa e quem chega atrasado: '
              'tudo aparece aqui conforme o grupo joga.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
