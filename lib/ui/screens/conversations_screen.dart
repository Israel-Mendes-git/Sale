import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config.dart';
import '../../domain/calendar.dart';
import '../../domain/lista_de_conversas.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../state/tutorial.dart';
import '../format.dart';
import '../widgets/avatar.dart';
import '../widgets/brand.dart';
import '../widgets/dica.dart';
import '../widgets/message_ticks.dart';
import '../widgets/rsvp_choice.dart';
import 'chat_screen.dart';
import 'group_screen.dart';
import 'incoming_chamado_screen.dart';
import 'profile_screen.dart';

/// O lembrete de "Cheguei" vale enquanto o Chamado é de agora: passadas umas
/// horas, quem não marcou já não vai marcar, e o aviso só atrapalharia.
const _arrivalWindow = Duration(hours: 3);

/// Dos Chamados em que a pessoa prometeu vir, os que ainda cabem no lembrete.
List<Chamado> _recentPromises(
  List<Chamado> waiting,
  String userId,
  DateTime now,
) {
  final recent = <Chamado>[];
  for (final chamado in waiting) {
    final promised = chamado.promisedBy(userId);
    if (promised != null && now.difference(promised) < _arrivalWindow) {
      recent.add(chamado);
    }
  }
  return recent;
}

class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<ConversationsScreen> createState() =>
      _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  String get userId => widget.userId;

  /// O filtro escolhido nos chips e o que se digitou na busca.
  var _filtro = FiltroDeConversas.todas;
  final _busca = TextEditingController();
  String _termo = '';

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  void _openProfileScreen(BuildContext context) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => ProfileScreen(userId: userId)));

  /// Escolhe alguém dos seus grupos e abre a conversa a dois com a pessoa.
  Future<void> _novaConversa() async {
    final repo = ref.read(repositoryProvider);
    final grupos = ref.read(groupsProvider(userId)).value ?? const <Group>[];
    final pessoas =
        {for (final g in grupos) ...g.memberIds}
            .where((id) => id != userId)
            .map(repo.profile)
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
    final escolhido = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (folha) => SafeArea(
        child: pessoas.isEmpty
            ? const Padding(
                padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Text(
                  'Ainda não tem ninguém nos seus grupos. Mande o código de '
                  'convite para alguém entrar.',
                ),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  const ListTile(title: Text('Conversar com')),
                  for (final p in pessoas)
                    ListTile(
                      leading: Avatar(p),
                      title: Text(p.name),
                      onTap: () => Navigator.pop(folha, p.id),
                    ),
                ],
              ),
      ),
    );
    if (escolhido == null || !mounted) return;
    await abrirConversaCom(context, ref, userId: userId, otherId: escolhido);
  }

  /// A barra de busca e os chips do filtro, em cima da lista.
  Widget _buscaEFiltro() {
    const nomes = {
      FiltroDeConversas.todas: 'Todas',
      FiltroDeConversas.naoLidas: 'Não lidas',
      FiltroDeConversas.grupos: 'Grupos',
      FiltroDeConversas.individuais: 'A dois',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          TextField(
            controller: _busca,
            decoration: InputDecoration(
              hintText: 'Buscar conversa',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: _termo.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Limpar busca',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _busca.clear();
                        setState(() => _termo = '');
                      },
                    ),
            ),
            onChanged: (v) => setState(() => _termo = semAcento(v.trim())),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final MapEntry(key: filtro, value: nome) in nomes.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(nome),
                      selected: _filtro == filtro,
                      onSelected: (_) => setState(() => _filtro = filtro),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A lista já filtrada, com as fixadas em cima.
  Widget _lista(List<Conversation> todas) {
    final repo = ref.watch(repositoryProvider);
    final lista = conversasDaLista(
      todas,
      filtro: _filtro,
      busca: _termo,
      titulo: (c) => semAcento(conversationTitle(repo, c, userId)),
      naoLida: (c) =>
          c.markedUnread ||
          c.unreadFor(userId, ref.watch(messagesProvider(c.id)).value ?? []) >
              0,
    );
    if (lista.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _termo.isNotEmpty
                ? 'Nenhuma conversa com esse nome.'
                : _filtro == FiltroDeConversas.naoLidas
                ? 'Tudo lido por aqui.'
                : 'Nenhuma conversa aqui ainda.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final fixadas = todas.where((c) => c.isPinned).length;
    return ListView.separated(
      itemCount: lista.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _ConversationTile(
        conversation: lista[i],
        userId: userId,
        podeFixar: fixadas < maxPinnedConversations,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    final me = repo.profile(userId);
    final conversations = ref.watch(conversationsProvider(userId));
    final pending = ref.watch(pendingChamadosProvider(userId)).value ?? [];
    final now = ref.watch(clockProvider)();
    final toArrive = _recentPromises(
      ref.watch(arrivalPendingProvider(userId)).value ?? const [],
      userId,
      now,
    );
    // O encontro que está chegando e ainda espera a sua confirmação. É a
    // mesma conta do lembrete que o servidor manda por push.
    final calendar = ref.watch(calendarProvider(userId)).value;
    final meeting = calendar == null
        ? null
        : meetingAwaitingRsvp(calendar, userId: userId, now: now);

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Marca(size: 22),
            SizedBox(width: 8),
            Flexible(child: Text('Sale?', overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          // Trocar de pessoa sem login só existe no backend em memória.
          if (!AppConfig.hasBackend)
            PopupMenuButton<String>(
              tooltip: 'Trocar usuário (desenvolvimento)',
              icon: const Icon(Icons.swap_horiz),
              onSelected: (id) =>
                  ref.read(currentUserProvider.notifier).signIn(id),
              itemBuilder: (context) => [
                for (final p in repo.profiles)
                  PopupMenuItem(
                    value: p.id,
                    enabled: p.id != userId,
                    child: Text('Entrar como ${p.name}'),
                  ),
              ],
            ),
          _TrocaDeGrupo(userId: userId),
          IconButton(
            tooltip: 'Nova conversa',
            icon: const Icon(Icons.add_comment_outlined),
            onPressed: _novaConversa,
          ),
          // Nome, respostas, tema, grupo, versão e sair moram no perfil; a
          // barra guarda só o caminho até ele.
          IconButton(
            tooltip: 'Meu perfil',
            icon: Avatar(me, radius: 16),
            onPressed: () => _openProfileScreen(context),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (!me.named)
            Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: const Text('Como o grupo te chama?'),
                subtitle: const Text('Escolha seu nome e suas respostas.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openProfileScreen(context),
              ),
            ),
          for (final c in pending) _PendingBanner(chamado: c, userId: userId),
          for (final c in toArrive) _ArrivalBanner(chamado: c, userId: userId),
          if (meeting != null)
            _MeetingBanner(occurrence: meeting, userId: userId),
          const DicaCard(
            dica: Dica.conversas,
            texto:
                'Toque numa conversa para abrir; segure para fixar no topo, '
                'silenciar ou marcar como não lida. A bolinha verde é quem '
                'está com o app aberto agora; o número, as mensagens que você '
                'não leu. Para chamar o grupo sem abrir o app, segure o ícone '
                'do Sale? na tela inicial.',
          ),
          Expanded(
            child: conversations.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: $e')),
              data: (list) => Column(
                children: [
                  if (list.isNotEmpty) _buscaEFiltro(),
                  Expanded(child: _lista(list)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// O grupo ativo no topo, e a troca entre os grupos da pessoa. O menu
/// também leva a criar ou entrar em outro grupo.
class _TrocaDeGrupo extends ConsumerWidget {
  const _TrocaDeGrupo({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grupos = ref.watch(groupsProvider(userId)).value ?? const <Group>[];
    final ativo = ref.watch(activeGroupProvider(userId));
    if (ativo == null) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Trocar de grupo',
      onSelected: (escolha) {
        if (escolha == _outro) {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => GroupScreen(userId: userId, outro: true),
            ),
          );
        } else {
          ref.read(activeGroupIdProvider.notifier).choose(escolha);
        }
      },
      itemBuilder: (context) => [
        for (final g in grupos)
          CheckedPopupMenuItem(
            value: g.id,
            checked: g.id == ativo.id,
            child: Text(g.name),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _outro,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.group_add_outlined),
            title: Text('Criar ou entrar em outro grupo'),
          ),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GroupAvatar(radius: 14, photoPath: ativo.photoPath),
            // Com um grupo só, o nome já está na conversa do grupo.
            if (grupos.length > 1) ...[
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 72),
                child: Text(ativo.name, overflow: TextOverflow.ellipsis),
              ),
            ],
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  static const _outro = '__outro__';
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({
    required this.conversation,
    required this.userId,
    required this.podeFixar,
  });

  final Conversation conversation;
  final String userId;

  /// Ainda cabe mais uma no topo.
  final bool podeFixar;

  /// O menu do toque longo: fixar, silenciar, marcar como lida ou não lida.
  Future<void> _menu(BuildContext context, WidgetRef ref, int unread) async {
    final repo = ref.read(repositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final agora = ref.read(clockProvider)();
    final calada = conversation.isMutedAt(agora);
    final temOQueLer = conversation.markedUnread || unread > 0;
    final escolha = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (folha) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                conversationTitle(repo, conversation, userId),
                style: Theme.of(folha).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: Icon(
                conversation.isPinned
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
              ),
              title: Text(
                conversation.isPinned ? 'Desafixar' : 'Fixar no topo',
              ),
              onTap: () => Navigator.pop(folha, 'fixar'),
            ),
            ListTile(
              leading: Icon(
                calada ? Icons.volume_up_outlined : Icons.volume_off_outlined,
              ),
              title: Text(calada ? 'Reativar o som' : 'Silenciar'),
              subtitle: calada
                  ? Text(_ateQuando(conversation.mutedUntil!, agora))
                  : const Text('Menção e Chamado tocam mesmo assim'),
              onTap: () => Navigator.pop(folha, 'silenciar'),
            ),
            ListTile(
              leading: Icon(
                temOQueLer
                    ? Icons.mark_chat_read_outlined
                    : Icons.mark_chat_unread_outlined,
              ),
              title: Text(
                temOQueLer ? 'Marcar como lida' : 'Marcar como não lida',
              ),
              onTap: () => Navigator.pop(folha, 'lida'),
            ),
          ],
        ),
      ),
    );
    if (escolha == null || !context.mounted) return;
    try {
      switch (escolha) {
        case 'fixar':
          if (!conversation.isPinned && !podeFixar) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Dá para fixar até $maxPinnedConversations conversas.',
                ),
              ),
            );
            return;
          }
          await repo.pinConversation(
            conversationId: conversation.id,
            userId: userId,
            pinned: !conversation.isPinned,
          );
        case 'silenciar':
          if (calada) {
            await repo.muteConversation(
              conversationId: conversation.id,
              userId: userId,
            );
          } else {
            final ate = await _escolherSilencio(context, agora);
            if (ate == null) return;
            await repo.muteConversation(
              conversationId: conversation.id,
              userId: userId,
              until: ate,
            );
          }
        case 'lida':
          if (temOQueLer) {
            await repo.markRead(
              conversationId: conversation.id,
              userId: userId,
            );
          } else {
            await repo.markUnread(
              conversationId: conversation.id,
              userId: userId,
            );
          }
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Não deu: $e')));
    }
  }

  /// Por quanto tempo silenciar, como no WhatsApp.
  Future<DateTime?> _escolherSilencio(BuildContext context, DateTime agora) =>
      showModalBottomSheet<DateTime>(
        context: context,
        showDragHandle: true,
        builder: (folha) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Silenciar por')),
              for (final (rotulo, ate) in [
                ('8 horas', agora.add(const Duration(hours: 8))),
                ('1 semana', agora.add(const Duration(days: 7))),
                ('Sempre', mutedForever),
              ])
                ListTile(
                  title: Text(rotulo),
                  onTap: () => Navigator.pop(folha, ate),
                ),
            ],
          ),
        ),
      );

  /// "Silenciada até 23:10", "até qui 29/10" ou "até você reativar".
  static String _ateQuando(DateTime ate, DateTime agora) {
    if (!ate.isBefore(mutedForever)) return 'Silenciada até você reativar';
    final local = ate.toLocal();
    final mesmoDia =
        local.year == agora.year &&
        local.month == agora.month &&
        local.day == agora.day;
    return 'Silenciada até ${mesmoDia ? hhmm(local) : dayLabel(local)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final messages = ref.watch(messagesProvider(conversation.id)).value ?? [];
    final last = messages.isEmpty ? null : messages.last;

    final online = ref.watch(onlineProvider(userId)).value ?? const <String>{};
    // A bolinha verde: alguém da conversa (fora eu) está com o app aberto.
    final alguemPorAi = conversation.memberIds.any(
      (id) => id != userId && online.contains(id),
    );
    final Widget leading;
    if (conversation.kind == ConversationKind.group) {
      leading = ComPresenca(
        online: alguemPorAi,
        child: GroupAvatar(
          photoPath: ref
              .watch(groupOfProvider((userId, conversation.groupId)))
              ?.photoPath,
        ),
      );
    } else {
      final otherId = conversation.memberIds.firstWhere((id) => id != userId);
      leading = ComPresenca(
        online: alguemPorAi,
        child: Avatar(repo.profile(otherId)),
      );
    }

    String preview = 'Sem mensagens';
    if (last != null) {
      final author = last.authorId == userId
          ? 'Você'
          : repo.profile(last.authorId).name;
      preview = '$author: ${messageSummary(last)}';
    }

    // Mensagem que chegou depois da última vez que esta pessoa abriu a
    // conversa. O Chamado tem o aviso dele, em cima de tudo.
    final unread = conversation.unreadFor(userId, messages);
    final calada = conversation.isMutedAt(ref.watch(clockProvider)());
    final scheme = Theme.of(context).colorScheme;

    // O que ficou meio escrito aparece no lugar da última mensagem.
    final rascunho = ref.watch(rascunhoProvider(conversation.id)).trim();

    return ListTile(
      leading: leading,
      title: Text(conversationTitle(repo, conversation, userId)),
      subtitle: Row(
        children: [
          if (rascunho.isNotEmpty)
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Rascunho: ',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextSpan(text: rascunho.replaceAll('\n', ' ')),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else ...[
            if (last != null && last.isChamado) ...[
              Marca(size: 14, color: Theme.of(context).colorScheme.secondary),
              const SizedBox(width: 4),
            ]
            // A marquinha da última mensagem minha, a mesma da conversa aberta.
            else if (last != null && last.authorId == userId) ...[
              MessageTicks(conversation.statusOf(last), size: 13),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                preview,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: unread == 0
                    ? null
                    : const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ],
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (last != null) Text(hhmm(last.createdAt)),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (calada)
                Icon(
                  Icons.volume_off,
                  size: 16,
                  semanticLabel: 'Silenciada',
                  color: scheme.outline,
                ),
              if (conversation.isPinned)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    Icons.push_pin,
                    size: 16,
                    semanticLabel: 'Fixada',
                    color: scheme.outline,
                  ),
                ),
              // Silenciada, o número fica cinza: tem o que ler, mas sem
              // pressa.
              if (unread > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Badge(
                    label: Text('$unread'),
                    backgroundColor: calada ? scheme.outline : null,
                  ),
                )
              else if (conversation.markedUnread)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Badge(
                    smallSize: 12,
                    backgroundColor: calada ? scheme.outline : null,
                  ),
                ),
            ],
          ),
        ],
      ),
      onLongPress: () => _menu(context, ref, unread),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ChatScreen(conversation: conversation, userId: userId),
        ),
      ),
    );
  }
}

/// Chamado esperando resposta, em cima de tudo e na cor do Chamado.
class _PendingBanner extends ConsumerWidget {
  const _PendingBanner({required this.chamado, required this.userId});

  final Chamado chamado;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final author = ref.watch(repositoryProvider).profile(chamado.authorId);
    return Material(
      color: scheme.secondary,
      child: ListTile(
        leading: Marca(size: 30, color: scheme.onSecondary),
        title: Text(
          chamado.automatic
              ? 'Hora do encontro do grupo'
              : '${author.name} te chamou pra jogar',
          style: TextStyle(
            color: scheme.onSecondary,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${chamadoGame(chamado)} · ${chamadoWhen(chamado)}',
          style: TextStyle(color: scheme.onSecondary),
        ),
        trailing: Icon(Icons.chevron_right, color: scheme.onSecondary),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) =>
                IncomingChamadoScreen(chamadoId: chamado.id, userId: userId),
          ),
        ),
      ),
    );
  }
}

/// O encontro fixo chegando: o lembrete de confirmar presença antes da hora,
/// com as mesmas opções da aba Semana.
class _MeetingBanner extends StatelessWidget {
  const _MeetingBanner({required this.occurrence, required this.userId});

  final MeetingOccurrence occurrence;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final game = occurrence.meeting.game;
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.event_available_outlined,
                  color: theme.colorScheme.tertiary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Encontro do grupo às '
                        '${minutesLabel(occurrence.minute)}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(game == null ? 'Você vai?' : '$game · você vai?'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            RsvpChoice(occurrence: occurrence, userId: userId),
          ],
        ),
      ),
    );
  }
}

/// Prometeu e ainda não marcou que chegou: o atalho do "Cheguei", que é de
/// onde sai o placar do atraso.
class _ArrivalBanner extends ConsumerWidget {
  const _ArrivalBanner({required this.chamado, required this.userId});

  final Chamado chamado;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final promised = chamado.promisedBy(userId)!;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: ListTile(
        leading: Icon(Icons.flag_outlined, color: scheme.tertiary),
        title: Text('Você disse que chegava às ${hhmm(promised)}'),
        subtitle: Text('${chamadoGame(chamado)} · avise quando chegar'),
        trailing: FilledButton(
          onPressed: () => ref
              .read(repositoryProvider)
              .markArrived(chamadoId: chamado.id, userId: userId),
          child: const Text('Cheguei'),
        ),
      ),
    );
  }
}
