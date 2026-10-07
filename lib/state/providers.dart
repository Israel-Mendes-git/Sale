import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../data/discord.dart';
import '../data/memory_repository.dart';
import '../data/repository.dart';
import '../data/supabase_repository.dart';
import '../domain/calendar.dart';
import '../domain/conquistas.dart';
import '../domain/do_dia.dart';
import '../domain/games.dart';
import '../domain/models.dart';
import '../domain/sounds.dart';
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

/// Quem do grupo está com o app aberto agora.
final onlineProvider = StreamProvider.family<Set<String>, String>(
  (ref, userId) => ref.watch(repositoryProvider).watchOnline(userId),
);

/// Quem digita ou grava na conversa. Some junto com a tela da conversa: o
/// canal dela só fica aberto enquanto alguém está olhando.
final activityProvider = StreamProvider.autoDispose
    .family<Map<String, ChatActivity>, String>(
      (ref, conversationId) =>
          ref.watch(repositoryProvider).watchActivity(conversationId),
    );

/// A do dia da conversa do grupo: a disputa de hoje e o Hall.
final doDiaProvider = StreamProvider.family<DoDia, String>(
  (ref, conversationId) =>
      ref.watch(repositoryProvider).watchDoDia(conversationId),
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

/// As conquistas de [userId]: dos Chamados e das vezes em que foi a do dia.
final conquistasProvider = Provider.family<List<Conquista>?, String>((
  ref,
  userId,
) {
  final historico = ref.watch(_historicoProvider(userId)).value;
  if (historico == null) return null;
  final grupo = ref
      .watch(conversationsProvider(userId))
      .value
      ?.where((c) => c.kind == ConversationKind.group)
      .firstOrNull;
  var vitorias = 0;
  if (grupo != null) {
    final hall = ref.watch(doDiaProvider(grupo.id)).value?.hall ?? const [];
    final mensagens = ref.watch(messagesProvider(grupo.id)).value ?? const [];
    final minhas = {
      for (final m in mensagens)
        if (m.authorId == userId) m.id,
    };
    vitorias = hall.where((d) => minhas.contains(d.messageId)).length;
  }
  // A call do Discord só conta para quem disse o nome dela lá.
  int? minutosDeCall;
  final eu = ref.watch(repositoryProvider).profile(userId);
  final meuGrupo = ref.watch(groupsProvider(userId)).value?.firstOrNull;
  if (eu.discordNome != null && meuGrupo?.discordServidor != null) {
    final tempos = ref
        .watch(tempoDeCallProvider((grupo: meuGrupo!.id, dias: null)))
        .value;
    minutosDeCall =
        tempos?.where((t) => t.userId == userId).firstOrNull?.minutos ?? 0;
  }
  return conquistasDe(
    userId,
    historico,
    vitoriasDoDia: vitorias,
    minutosDeCall: minutosDeCall,
  );
});

final _historicoProvider = StreamProvider.family<List<Chamado>, String>(
  (ref, userId) => ref.watch(repositoryProvider).watchHistory(userId),
);

/// O servidor do Discord agora — quem está em cada call, quem está online e
/// jogando o quê —, relido a cada 30 segundos enquanto alguém olha. Nulo =
/// widget desligado ou fora do ar.
final discordAoVivoProvider = StreamProvider.autoDispose
    .family<ServidorDoDiscord?, String>((ref, servidor) async* {
      while (true) {
        yield await buscarServidor(servidor);
        await Future<void>.delayed(const Duration(seconds: 30));
      }
    });

/// Quanto cada um ficou na call do Discord do grupo nos últimos [dias] (nulo
/// = desde sempre), anotado pelo servidor a cada minuto.
final tempoDeCallProvider = FutureProvider.autoDispose
    .family<List<TempoDeCall>, ({String grupo, int? dias})>((ref, chave) {
      final desde = chave.dias == null
          ? DateTime.utc(2000)
          : DateTime.now().subtract(Duration(days: chave.dias!));
      return ref.watch(repositoryProvider).callTime(chave.grupo, desde);
    });

final gamesProvider = StreamProvider<GameLibrary>(
  (ref) => ref.watch(repositoryProvider).watchGames(),
);

/// A lista de sons do Chamado: os que vêm no app mais os do grupo.
final soundsProvider = StreamProvider<List<Sound>>(
  (ref) => ref.watch(repositoryProvider).watchSounds(),
);
