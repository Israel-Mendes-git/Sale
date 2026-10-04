import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'push/push.dart';
import 'push/sons.dart';
import 'state/providers.dart';
import 'state/settings.dart';
import 'ui/screens/chat_screen.dart';
import 'ui/screens/group_screen.dart';
import 'ui/screens/home_screen.dart';
import 'ui/screens/incoming_chamado_screen.dart';
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
      // A notificação do Chamado abre a tela cheia por aqui, de fora de
      // qualquer tela.
      navigatorKey: appNavigator,
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
      AsyncData() => _ComPush(
        userId: userId,
        child: GroupGate(userId: userId, child: home),
      ),
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
            Text(
              message.contains('TimeoutException')
                  ? 'O servidor não respondeu.'
                  : 'Não deu para falar com o servidor.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18),
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

/// Liga o push quando o backend está de pé e abre o Chamado quando a
/// notificação é tocada.
class _ComPush extends ConsumerStatefulWidget {
  const _ComPush({required this.userId, required this.child});

  final String userId;
  final Widget child;

  @override
  ConsumerState<_ComPush> createState() => _ComPushState();
}

class _ComPushState extends ConsumerState<_ComPush> {
  @override
  void initState() {
    super.initState();
    chamadoTocado.addListener(_abrirChamado);
    conversaTocada.addListener(_abrirConversa);
    // Depois do primeiro quadro: pedir permissão precisa de tela na frente.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ligarPush(
        repository: ref.read(repositoryProvider),
        userId: widget.userId,
      );
      _abrirChamado();
      _abrirConversa();
    });
  }

  @override
  void dispose() {
    chamadoTocado.removeListener(_abrirChamado);
    conversaTocada.removeListener(_abrirConversa);
    super.dispose();
  }

  void _abrirChamado() {
    final id = chamadoTocado.value;
    if (id == null) return;
    chamadoTocado.value = null;
    appNavigator.currentState?.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            IncomingChamadoScreen(chamadoId: id, userId: widget.userId),
      ),
    );
  }

  /// Abre a conversa do aviso de mensagem que a pessoa tocou.
  Future<void> _abrirConversa() async {
    final id = conversaTocada.value;
    if (id == null) return;
    conversaTocada.value = null;
    // O app pode ter acabado de abrir pelo aviso: aí a lista de conversas
    // ainda está chegando, e vale esperar a primeira.
    final conversas =
        ref.read(conversationsProvider(widget.userId)).value ??
        await ref
            .read(repositoryProvider)
            .watchConversations(widget.userId)
            .first;
    final conversa = conversas.where((c) => c.id == id).firstOrNull;
    if (conversa == null) return;
    appNavigator.currentState?.push(
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(conversation: conversa, userId: widget.userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Som que o grupo subiu só toca onde o aparelho já o baixou, e quem o
    // baixa é o app aberto. Fica aqui, e não na tela dos sons, porque o
    // Chamado toca com o app fechado — quem nunca entrou na tela dos sons
    // também precisa ouvir o som certo.
    ref.listen(soundsProvider, (_, next) {
      final sons = next.value;
      if (sons == null) return;
      prepararSons(sons, ref.read(repositoryProvider).soundBytes);
    });
    return widget.child;
  }
}
