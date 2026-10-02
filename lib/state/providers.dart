import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../data/memory_repository.dart';
import '../data/repository.dart';
import '../data/supabase_repository.dart';
import '../domain/calendar.dart';
import '../domain/games.dart';
import '../domain/models.dart';
import '../domain/stats.dart';

/// Relógio do app; os testes trocam por uma data fixa.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Com a configuração do Supabase o app fala com o servidor; sem ela, com o
/// backend em memória (testes e desenvolvimento das telas).
final repositoryProvider = Provider<SaleRepository>((ref) {
  final clock = ref.watch(clockProvider);
  if (!AppConfig.hasBackend) return MemoryRepository(clock: clock);

  // Sem login o repositório existe mas não enxerga nada: as regras de
  // acesso devolvem vazio. Vale para o instante entre sair e a tela de
  // login aparecer.
  final repository = SupabaseRepository(
    client: Supabase.instance.client,
    userId: ref.watch(currentUserProvider) ?? '',
    clock: clock,
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// Carrega o que as telas pedem de pronto (perfis, respostas rápidas, grupo)
/// e liga o tempo real, antes de a primeira tela aparecer.
///
/// Com prazo: servidor mudo é erro na tela, com o botão de tentar de novo.
/// Sem isso, o app ficaria girando para sempre, que é o pior jeito de falhar.
final backendReadyProvider = FutureProvider<void>((ref) async {
  final repository = ref.watch(repositoryProvider);
  if (repository is SupabaseRepository) {
    await repository.load().timeout(const Duration(seconds: 20));
  }
});

/// Usuário logado. Nulo = tela de login.
///
/// Com o Supabase, quem manda é a sessão guardada no aparelho; sem ele, o
/// seletor de desenvolvimento troca quem está usando o app para testar as
/// três pontas de um Chamado.
final currentUserProvider = NotifierProvider<CurrentUser, String?>(
  CurrentUser.new,
);

class CurrentUser extends Notifier<String?> {
  @override
  String? build() {
    if (!AppConfig.hasBackend) return null;
    final auth = Supabase.instance.client.auth;
    // Entrar, sair e renovar o token caem todos aqui.
    final subscription = auth.onAuthStateChange.listen(
      (change) => state = change.session?.user.id,
    );
    ref.onDispose(subscription.cancel);
    return auth.currentSession?.user.id;
  }

  /// Só no backend em memória; com o Supabase quem entra é o login.
  void signIn(String userId) => state = userId;

  Future<void> signOut() async {
    if (AppConfig.hasBackend) await Supabase.instance.client.auth.signOut();
    state = null;
  }
}

final groupsProvider = StreamProvider.family<List<Group>, String>(
  (ref, userId) => ref.watch(repositoryProvider).watchGroups(userId),
);

final conversationsProvider = StreamProvider.family<List<Conversation>, String>(
  (ref, userId) => ref.watch(repositoryProvider).watchConversations(userId),
);

final messagesProvider = StreamProvider.family<List<Message>, String>(
  (ref, conversationId) =>
      ref.watch(repositoryProvider).watchMessages(conversationId),
);

final chamadoProvider = StreamProvider.family<Chamado, String>(
  (ref, chamadoId) => ref.watch(repositoryProvider).watchChamado(chamadoId),
);

final pendingChamadosProvider = StreamProvider.family<List<Chamado>, String>(
  (ref, userId) => ref.watch(repositoryProvider).watchPendingFor(userId),
);

final calendarProvider = StreamProvider.family<CalendarData, String>(
  (ref, userId) => ref.watch(repositoryProvider).watchCalendar(userId),
);

/// Chamados em que a pessoa prometeu vir e ainda não marcou "Cheguei".
final arrivalPendingProvider = StreamProvider.family<List<Chamado>, String>(
  (ref, userId) => ref.watch(repositoryProvider).watchArrivalPending(userId),
);

/// Placar e estatísticas, contados a partir do histórico de Chamados.
final statsProvider = StreamProvider.family<Stats, String>((ref, userId) {
  final repository = ref.watch(repositoryProvider);
  return repository
      .watchHistory(userId)
      .map(
        (history) => computeStats(
          history,
          // Quem nunca chamou nem foi chamado também aparece, com zero.
          members: [for (final p in repository.profiles) p.id],
        ),
      );
});

final gamesProvider = StreamProvider<GameLibrary>(
  (ref) => ref.watch(repositoryProvider).watchGames(),
);
