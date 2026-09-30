import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/memory_repository.dart';
import '../data/repository.dart';
import '../domain/models.dart';

final repositoryProvider = Provider<SaleRepository>(
  (ref) => MemoryRepository(),
);

/// Usuário logado. Nulo = tela de login.
///
/// Enquanto não há login de verdade, o seletor de desenvolvimento troca
/// quem está usando o app para testar as três pontas de um Chamado.
final currentUserProvider = NotifierProvider<CurrentUser, String?>(
  CurrentUser.new,
);

class CurrentUser extends Notifier<String?> {
  @override
  String? build() => null;

  void signIn(String userId) => state = userId;
  void signOut() => state = null;
}

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
