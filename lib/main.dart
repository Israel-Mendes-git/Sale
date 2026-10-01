import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'state/providers.dart';
import 'ui/screens/group_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.hasBackend) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseKey,
    );
  }
  runApp(const ProviderScope(child: SaleApp()));
}

class SaleApp extends ConsumerWidget {
  const SaleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserProvider);
    return MaterialApp(
      title: 'Sale?',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: userId == null ? const LoginScreen() : _Logged(userId: userId),
    );
  }
}

/// Com o Supabase, espera o repositório carregar e pede um grupo antes de
/// abrir as abas. Em memória, o grupo já existe e vai direto.
class _Logged extends ConsumerWidget {
  const _Logged({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A chave recria a navegação ao trocar de usuário.
    final home = HomeScreen(key: ValueKey(userId), userId: userId);
    if (!AppConfig.hasBackend) return home;

    return switch (ref.watch(backendReadyProvider)) {
      AsyncError(:final error) => _Broken(message: '$error'),
      AsyncData() => GroupGate(userId: userId, child: home),
      _ => const _Connecting(),
    };
  }
}

class _Connecting extends StatelessWidget {
  const _Connecting();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('🦇', style: TextStyle(fontSize: 48)),
          SizedBox(height: 16),
          CircularProgressIndicator(),
        ],
      ),
    ),
  );
}

/// Sem servidor não dá para mostrar nada: resta tentar de novo ou sair.
class _Broken extends ConsumerWidget {
  const _Broken({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📡', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            const Text(
              'Não deu para falar com o servidor.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => ref.invalidate(backendReadyProvider),
              child: const Text('Tentar de novo'),
            ),
            TextButton(
              onPressed: () => ref.read(currentUserProvider.notifier).signOut(),
              child: const Text('Sair'),
            ),
          ],
        ),
      ),
    ),
  );
}
