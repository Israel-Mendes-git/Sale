import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../update/update_providers.dart';
import '../../update/update_ui.dart';
import 'conversations_screen.dart';
import 'games_screen.dart';
import 'week_screen.dart';

/// Abas principais: conversas e a semana.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  var _tab = 0;
  late final AppLifecycleListener _lifecycle;
  var _lastUpdateCheck = DateTime.now();

  @override
  void initState() {
    super.initState();
    // App que fica dias em segundo plano também fica sabendo da versão nova.
    _lifecycle = AppLifecycleListener(onResume: _onResume);
    _markDelivered();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _onResume() {
    _recheckUpdate();
    _markDelivered();
  }

  /// App aberto é aparelho conectado: as mensagens que estavam no servidor
  /// chegaram, e quem escreveu ganha o segundo tique. Texto não manda push,
  /// então é aqui que a entrega acontece.
  void _markDelivered() {
    // Fora do build: a marca mexe nos streams que as telas estão montando.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await ref.read(repositoryProvider).markDelivered(widget.userId);
      } catch (_) {
        // Sem rede ninguém recebeu nada mesmo; a próxima abertura tenta de
        // novo.
      }
    });
  }

  void _recheckUpdate() {
    final now = DateTime.now();
    // A API do GitHub sem login aceita 60 consultas por hora.
    if (now.difference(_lastUpdateCheck) < const Duration(minutes: 30)) return;
    _lastUpdateCheck = now;
    ref.invalidate(availableUpdateProvider);
  }

  @override
  Widget build(BuildContext context) {
    final pending =
        ref.watch(pendingChamadosProvider(widget.userId)).value?.length ?? 0;
    return Scaffold(
      body: Column(
        children: [
          const UpdateBanner(),
          Expanded(
            // O aviso já ocupa a área da barra de status.
            child: MediaQuery.removePadding(
              context: context,
              removeTop: ref.watch(updateBannerVisibleProvider),
              child: IndexedStack(
                index: _tab,
                children: [
                  ConversationsScreen(userId: widget.userId),
                  WeekScreen(userId: widget.userId),
                  GamesScreen(userId: widget.userId),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pending > 0,
              label: Text('$pending'),
              child: const Icon(Icons.chat_bubble_outline),
            ),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: 'Conversas',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_view_week_outlined),
            selectedIcon: Icon(Icons.calendar_view_week),
            label: 'Semana',
          ),
          const NavigationDestination(
            icon: Icon(Icons.sports_esports_outlined),
            selectedIcon: Icon(Icons.sports_esports),
            label: 'Jogos',
          ),
        ],
      ),
    );
  }
}
