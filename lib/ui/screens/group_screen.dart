import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repository.dart';
import '../../state/providers.dart';

/// Ninguém usa o app sozinho: sem grupo, a primeira coisa é criar um ou
/// entrar no de um amigo. Com grupo, mostra [child].
class GroupGate extends ConsumerWidget {
  const GroupGate({super.key, required this.userId, required this.child});

  final String userId;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(groupsProvider(userId))) {
      AsyncData(:final value) =>
        value.isEmpty ? const GroupScreen() : child,
      AsyncError(:final error) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(groupsProvider(userId)),
                  child: const Text('Tentar de novo'),
                ),
              ],
            ),
          ),
        ),
      ),
      _ => const Scaffold(body: Center(child: CircularProgressIndicator())),
    };
  }
}

/// Criar o grupo ou entrar no de alguém pelo código do convite.
class GroupScreen extends ConsumerStatefulWidget {
  const GroupScreen({super.key});

  @override
  ConsumerState<GroupScreen> createState() => _GroupScreenState();
}

class _GroupScreenState extends ConsumerState<GroupScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  var _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  /// Roda a ação com o botão travado e põe o erro na tela como ele veio do
  /// banco ("código de convite inválido").
  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        final message = switch (e) {
          StateError(:final message) => message,
          ArgumentError(:final message) => '$message',
          _ => '$e',
        };
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ref.watch(repositoryProvider);

    return Scaffold(
      body: SafeArea(
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
                    Text(
                      'Seu grupo',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Crie o grupo e passe o código para os amigos, ou entre '
                      'com o código que te mandaram.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _name,
                      maxLength: maxGroupNameLength,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'Nome do grupo',
                        hintText: 'Os 3',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() => repo.createGroup(_name.text)),
                      child: const Text('Criar grupo'),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'ou',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 32),
                    TextField(
                      controller: _code,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Código do convite',
                        hintText: 'A1B2C3D4',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: _busy
                          ? null
                          : () => _run(() => repo.joinGroup(_code.text)),
                      child: const Text('Entrar no grupo'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () =>
                                ref.read(currentUserProvider.notifier).signOut(),
                      child: const Text('Sair'),
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
