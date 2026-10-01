import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config.dart';
import '../../state/providers.dart';
import '../widgets/avatar.dart';
import '../widgets/brand.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  var _busy = false;

  /// Abre o navegador no provedor escolhido. A sessão volta sozinha pelo
  /// endereço de retorno ([AppConfig.authRedirect]) e cai no
  /// `onAuthStateChange`, que troca a tela.
  Future<void> _signIn(OAuthProvider provider) async {
    setState(() => _busy = true);
    try {
      await Supabase.instance.client.auth.signInWithOAuth(
        provider,
        redirectTo: AppConfig.authRedirect,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Não deu para entrar: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                    const Center(child: Marca(size: 84)),
                    const SizedBox(height: 8),
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
                    if (AppConfig.hasBackend) ...[
                      FilledButton.tonal(
                        onPressed: _busy
                            ? null
                            : () => _signIn(OAuthProvider.discord),
                        child: const Text('Entrar com Discord'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: _busy
                            ? null
                            : () => _signIn(OAuthProvider.google),
                        child: const Text('Entrar com Google'),
                      ),
                    ] else
                      const _DevelopmentSignIn(),
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

/// Sem backend não há login: o app entra como um dos perfis de teste, para
/// ver as três pontas de um Chamado no mesmo celular.
class _DevelopmentSignIn extends ConsumerWidget {
  const _DevelopmentSignIn();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profiles = ref.watch(repositoryProvider).profiles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                onTap: () => ref.read(currentUserProvider.notifier).signIn(p.id),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(
                    width: 88,
                    child: Column(
                      children: [
                        Avatar(p, radius: 28),
                        const SizedBox(height: 4),
                        Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
