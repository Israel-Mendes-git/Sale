import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../widgets/avatar.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profiles = ref.watch(repositoryProvider).profiles;

    return Scaffold(
      body: SafeArea(
        // Rola só quando falta altura (celular deitado, fonte grande).
        child: CustomScrollView(
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Spacer(),
                    const Text(
                      '🦇',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 72),
                    ),
                    Text(
                      'Sale?',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.displayMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Chame os amigos pra jogar',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    const Spacer(),
                    // Login real entra com o Supabase.
                    const FilledButton.tonal(
                      onPressed: null,
                      child: Text('Entrar com Discord (em breve)'),
                    ),
                    const SizedBox(height: 8),
                    const FilledButton.tonal(
                      onPressed: null,
                      child: Text('Entrar com Google (em breve)'),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Desenvolvimento: entrar como',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    // Quebra linha: os nomes são digitados e podem ser longos.
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      children: [
                        for (final p in profiles)
                          InkWell(
                            borderRadius: BorderRadius.circular(32),
                            onTap: () => ref
                                .read(currentUserProvider.notifier)
                                .signIn(p.id),
                            child: Padding(
                              padding: const EdgeInsets.all(8),
                              child: SizedBox(
                                width: 88,
                                child: Column(
                                  children: [
                                    Avatar(p, radius: 28),
                                    const SizedBox(height: 4),
                                    Text(
                                      p.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
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
