import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../icons.dart';
import '../format.dart';
import '../respond.dart';
import '../widgets/avatar.dart';

/// Tela cheia de Chamado recebido, no estilo de uma ligação.
///
/// Hoje abre pelo aviso na lista de conversas; com o push, é ela que a
/// notificação de tela cheia vai abrir.
class IncomingChamadoScreen extends ConsumerStatefulWidget {
  const IncomingChamadoScreen({
    super.key,
    required this.chamadoId,
    required this.userId,
  });

  final String chamadoId;
  final String userId;

  @override
  ConsumerState<IncomingChamadoScreen> createState() =>
      _IncomingChamadoScreenState();
}

class _IncomingChamadoScreenState extends ConsumerState<IncomingChamadoScreen>
    with SingleTickerProviderStateMixin {
  late final _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chamado = ref.watch(chamadoProvider(widget.chamadoId)).value;
    if (chamado == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final repo = ref.watch(repositoryProvider);
    final author = repo.profile(chamado.authorId);
    final replies = repo.quickRepliesFor(widget.userId);
    final waiting = chamado.awaits(widget.userId);

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: SafeArea(
        // Rola só quando falta altura (celular deitado, fonte grande).
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    ScaleTransition(
                      scale: Tween(begin: 0.9, end: 1.15).animate(
                        CurvedAnimation(
                          parent: _pulse,
                          curve: Curves.easeInOut,
                        ),
                      ),
                      child: const Text('🦇', style: TextStyle(fontSize: 96)),
                    ),
                    const SizedBox(height: 16),
                    Avatar(author, radius: 32),
                    const SizedBox(height: 8),
                    Text(
                      '${author.name} te chamou pra jogar',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${chamadoGame(chamado)} · ${chamadoWhen(chamado)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    if (chamado.note != null) ...[
                      const SizedBox(height: 8),
                      Text('"${chamado.note}"', textAlign: TextAlign.center),
                    ],
                    const Spacer(),
                    if (!waiting)
                      Text(
                        chamado.isOpen
                            ? 'Resposta enviada.'
                            : 'Chamado encerrado.',
                        style: theme.textTheme.titleMedium,
                      )
                    else
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final r in replies)
                            FilledButton.tonalIcon(
                              icon: Icon(replyIcon(r.icon)),
                              label: Text(r.label),
                              onPressed: () async {
                                final sent = await respondToChamado(
                                  context,
                                  ref,
                                  chamado: chamado,
                                  userId: widget.userId,
                                  reply: r,
                                );
                                if (sent && context.mounted) {
                                  Navigator.pop(context);
                                }
                              },
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
