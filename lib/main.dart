import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'state/providers.dart';
import 'state/settings.dart';
import 'ui/screens/group_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/login_screen.dart';
import 'ui/theme.dart';
import 'ui/widgets/brand.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (AppConfig.hasBackend) {
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseKey,
    );
  }
  // O tema escolhido já vem lido do aparelho, para o app não piscar na cor
  // errada ao abrir.
  final settings = await PrefsSettingsStore.open();
  runApp(
    ProviderScope(
      overrides: [settingsStoreProvider.overrideWithValue(settings)],
      child: const SaleApp(),
    ),
  );
}

class SaleApp extends ConsumerWidget {
  const SaleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserProvider);
    final appearance = ref.watch(appearanceProvider);
    return MaterialApp(
      title: 'Sale?',
      debugShowCheckedModeBanner: false,
      theme: saleTheme(appearance.palette, Brightness.light),
      darkTheme: saleTheme(appearance.palette, Brightness.dark),
      themeMode: appearance.mode,
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
          Marca(size: 56),
          SizedBox(height: 20),
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
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
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
