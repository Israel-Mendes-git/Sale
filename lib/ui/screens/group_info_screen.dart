import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/repository.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../widgets/avatar.dart';
import '../widgets/chat_image.dart';
import 'chat_screen.dart';
import 'discord_screen.dart';

/// Os dados do grupo: foto, nome, descrição, mídia, quem está nele, o
/// convite, o Discord e o "Sair do grupo".
///
/// Nome, foto e descrição qualquer um muda; remover alguém, nomear admin e
/// trocar o convite é de admin. O servidor confere tudo de novo.
class GroupInfoScreen extends ConsumerWidget {
  const GroupInfoScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupsProvider(userId)).value?.firstOrNull;
    // Saiu do grupo (ou foi removido) com a tela aberta: volta.
    if (group == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Você não está mais neste grupo.')),
      );
    }
    final theme = Theme.of(context);
    final souAdmin = group.isAdmin(userId);
    final conversa = ref
        .watch(conversationsProvider(userId))
        .value
        ?.where((c) => c.kind == ConversationKind.group)
        .firstOrNull;
    final descricao = group.description;

    return Scaffold(
      appBar: AppBar(title: const Text('Dados do grupo')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const SizedBox(height: 16),
          Center(
            child: Stack(
              children: [
                GestureDetector(
                  onTap: () => _trocarFoto(context, ref, group),
                  child: GroupAvatar(radius: 56, photoPath: group.photoPath),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: IconButton.filled(
                    tooltip: 'Trocar a foto do grupo',
                    iconSize: 20,
                    onPressed: () => _trocarFoto(context, ref, group),
                    icon: const Icon(Icons.photo_camera_outlined),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              group.name,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
          ),
          Text(
            group.memberIds.length == 1
                ? 'Só você'
                : '${group.memberIds.length} participantes',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(
              descricao ?? 'Adicionar descrição',
              style: descricao == null
                  ? TextStyle(color: theme.colorScheme.primary)
                  : null,
            ),
            subtitle: descricao == null
                ? const Text('O IP do servidor, as regras da casa…')
                : const Text('Nome e descrição'),
            onTap: () => _editar(context, ref, group),
          ),
          const Divider(height: 24),
          if (conversa != null) _Midia(conversa: conversa),
          _Participantes(group: group, userId: userId),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.link),
            title: Text('Código de convite: ${group.inviteCode}'),
            subtitle: const Text(
              'Quem tem o código entra no grupo e vê as conversas, os jogos '
              'e o encontro fixo.',
            ),
            trailing: IconButton(
              tooltip: 'Copiar o código',
              icon: const Icon(Icons.copy),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: group.inviteCode));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Código copiado.')),
                );
              },
            ),
          ),
          if (souAdmin)
            ListTile(
              leading: const Icon(Icons.autorenew),
              title: const Text('Gerar código novo'),
              subtitle: const Text(
                'Para quando o código vazou: o antigo para de valer.',
              ),
              onTap: () => _novoCodigo(context, ref, group),
            ),
          ListTile(
            leading: const Icon(Icons.headset_mic_outlined),
            title: const Text('Discord do grupo'),
            subtitle: Text(
              group.discordServidor == null
                  ? 'Quem está na call, jogando o quê, e o tempo de call.'
                  : 'Ligado: quem está na call agora e o tempo de call.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => group.discordServidor == null
                    ? DiscordScreen(group: group, userId: userId)
                    : DiscordAoVivoScreen(group: group, userId: userId),
              ),
            ),
          ),
          const Divider(height: 24),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(
              'Sair do grupo',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () => _sair(context, ref, group),
          ),
        ],
      ),
    );
  }

  Future<void> _acao(
    BuildContext context,
    Future<void> Function() acao, {
    String? feito,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await acao();
      if (feito != null) {
        messenger.showSnackBar(SnackBar(content: Text(feito)));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(_mensagem(e))));
    }
  }

  Future<void> _editar(BuildContext context, WidgetRef ref, Group group) async {
    final editado = await showDialog<({String nome, String descricao})>(
      context: context,
      builder: (_) => _EditarGrupo(group: group),
    );
    if (editado == null || !context.mounted) return;
    await _acao(
      context,
      () => ref
          .read(repositoryProvider)
          .editGroup(
            groupId: group.id,
            name: editado.nome,
            description: editado.descricao,
          ),
    );
  }

  Future<void> _trocarFoto(
    BuildContext context,
    WidgetRef ref,
    Group group,
  ) async {
    final de = await showModalBottomSheet<ImageSource?>(
      context: context,
      showDragHandle: true,
      builder: (folha) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tirar foto'),
              onTap: () => Navigator.pop(folha, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Escolher da galeria'),
              onTap: () => Navigator.pop(folha, ImageSource.gallery),
            ),
            if (group.photoPath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Tirar a foto'),
                onTap: () {
                  Navigator.pop(folha);
                  _acao(
                    context,
                    () =>
                        ref.read(repositoryProvider).removeGroupPhoto(group.id),
                  );
                },
              ),
          ],
        ),
      ),
    );
    if (de == null || !context.mounted) return;
    final Uint8List bytes;
    final String nome;
    try {
      // Foto de grupo aparece pequena: 800 pixels sobram.
      final escolha = await ImagePicker().pickImage(
        source: de,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 85,
      );
      if (escolha == null) return;
      nome = escolha.name;
      bytes = await escolha.readAsBytes();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não deu para abrir a imagem: $e')),
      );
      return;
    }
    if (!context.mounted) return;
    await _acao(
      context,
      () => ref
          .read(repositoryProvider)
          .setGroupPhoto(groupId: group.id, bytes: bytes, fileName: nome),
    );
  }

  Future<void> _novoCodigo(
    BuildContext context,
    WidgetRef ref,
    Group group,
  ) async {
    final ok = await _confirmar(
      context,
      titulo: 'Gerar código novo?',
      texto:
          'O código ${group.inviteCode} para de valer. Quem já está no grupo '
          'continua.',
      acao: 'Gerar',
    );
    if (!ok || !context.mounted) return;
    await _acao(
      context,
      () => ref
          .read(repositoryProvider)
          .newInviteCode(groupId: group.id, by: userId),
      feito: 'Código novo gerado.',
    );
  }

  Future<void> _sair(BuildContext context, WidgetRef ref, Group group) async {
    final sozinho = group.memberIds.length == 1;
    final ok = await _confirmar(
      context,
      titulo: 'Sair de ${group.name}?',
      texto: sozinho
          ? 'Você é o último: o grupo é apagado, com as conversas e os jogos.'
          : 'Você deixa de ver a conversa do grupo, os jogos e a semana. Para '
                'voltar, só com o código de convite.',
      acao: sozinho ? 'Sair e apagar' : 'Sair',
    );
    if (!ok || !context.mounted) return;
    final navigator = Navigator.of(context);
    await _acao(
      context,
      () => ref
          .read(repositoryProvider)
          .leaveGroup(groupId: group.id, userId: userId),
    );
    // Sem grupo, o app volta para a tela de criar ou entrar num grupo.
    navigator.popUntil((r) => r.isFirst);
  }
}

String _mensagem(Object e) => switch (e) {
  StateError(:final message) => message,
  ArgumentError(:final message) => '$message',
  _ => 'Não deu certo. Tente de novo.',
};

Future<bool> _confirmar(
  BuildContext context, {
  required String titulo,
  required String texto,
  required String acao,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialogo) => AlertDialog(
        title: Text(titulo),
        content: Text(texto),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogo, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogo, true),
            child: Text(acao),
          ),
        ],
      ),
    ) ??
    false;

/// Nome e descrição, num diálogo só. Tem estado para cuidar dos controllers.
class _EditarGrupo extends StatefulWidget {
  const _EditarGrupo({required this.group});

  final Group group;

  @override
  State<_EditarGrupo> createState() => _EditarGrupoState();
}

class _EditarGrupoState extends State<_EditarGrupo> {
  late final _nome = TextEditingController(text: widget.group.name);
  late final _descricao = TextEditingController(
    text: widget.group.description ?? '',
  );

  @override
  void dispose() {
    _nome.dispose();
    _descricao.dispose();
    super.dispose();
  }

  void _salvar() {
    if (_nome.text.trim().isEmpty) return;
    Navigator.pop(context, (nome: _nome.text, descricao: _descricao.text));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Editar grupo'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nome,
            autofocus: true,
            maxLength: maxGroupNameLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Nome do grupo'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _descricao,
            maxLength: maxGroupDescriptionLength,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descrição',
              hintText: 'O IP do servidor, as regras da casa…',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(onPressed: _salvar, child: const Text('Salvar')),
    ],
  );
}

/// As fotos mandadas na conversa do grupo: uma faixa com as últimas e o
/// "Ver tudo" para a grade inteira.
class _Midia extends ConsumerWidget {
  const _Midia({required this.conversa});

  final Conversation conversa;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fotos = fotosDaConversa(
      ref.watch(messagesProvider(conversa.id)).value ?? const [],
    );
    if (fotos.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text('Mídia (${fotos.length})'),
          trailing: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => GroupMediaScreen(conversa: conversa),
              ),
            ),
            child: const Text('Ver tudo'),
          ),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: fotos.length.clamp(0, 10),
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) => SizedBox.square(
              dimension: 96,
              child: _Miniatura(mensagem: fotos[i]),
            ),
          ),
        ),
        const Divider(height: 24),
      ],
    );
  }
}

/// As fotos de uma conversa, da mais nova para a mais velha, sem as apagadas.
List<Message> fotosDaConversa(List<Message> mensagens) => [
  for (final m in mensagens.reversed)
    if (m.isImage) m,
];

class _Miniatura extends ConsumerWidget {
  const _Miniatura({required this.mensagem});

  final Message mensagem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anexo = mensagem.attachment!;
    final bytes = ref.watch(attachmentProvider(anexo.path)).value;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FullImageScreen(
            attachment: anexo,
            author: ref
                .read(repositoryProvider)
                .profile(mensagem.authorId)
                .name,
            caption: mensagem.text,
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: bytes == null
            ? ColoredBox(color: scheme.surfaceContainerHighest)
            : Image.memory(bytes, fit: BoxFit.cover),
      ),
    );
  }
}

/// Todas as fotos da conversa do grupo, em grade.
class GroupMediaScreen extends ConsumerWidget {
  const GroupMediaScreen({super.key, required this.conversa});

  final Conversation conversa;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fotos = fotosDaConversa(
      ref.watch(messagesProvider(conversa.id)).value ?? const [],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Mídia do grupo')),
      body: fotos.isEmpty
          ? const Center(child: Text('Nenhuma foto na conversa ainda.'))
          : GridView.builder(
              padding: const EdgeInsets.all(4),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemCount: fotos.length,
              itemBuilder: (context, i) => _Miniatura(mensagem: fotos[i]),
            ),
    );
  }
}

/// Quem está no grupo: admins primeiro, depois por ordem de chegada. Admin
/// toca em alguém para nomear admin ou remover; todos podem abrir a conversa
/// com a pessoa.
class _Participantes extends ConsumerWidget {
  const _Participantes({required this.group, required this.userId});

  final Group group;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final online = ref.watch(onlineProvider(userId)).value ?? const <String>{};
    final theme = Theme.of(context);
    final ordem = [
      ...group.memberIds.where(group.isAdmin),
      ...group.memberIds.where((id) => !group.isAdmin(id)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(
            group.memberIds.length == 1
                ? '1 participante'
                : '${group.memberIds.length} participantes',
          ),
          dense: true,
        ),
        for (final id in ordem)
          ListTile(
            leading: ComPresenca(
              online: id != userId && online.contains(id),
              child: Avatar(repo.profile(id)),
            ),
            title: Text(id == userId ? 'Você' : repo.profile(id).name),
            trailing: group.isAdmin(id)
                ? Chip(
                    label: const Text('Admin'),
                    visualDensity: VisualDensity.compact,
                    labelStyle: theme.textTheme.labelSmall,
                  )
                : null,
            onTap: id == userId
                ? null
                : () => _opcoes(context, ref, id, repo.profile(id).name),
          ),
      ],
    );
  }

  Future<void> _opcoes(
    BuildContext context,
    WidgetRef ref,
    String id,
    String nome,
  ) async {
    final souAdmin = group.isAdmin(userId);
    final direta = ref
        .read(conversationsProvider(userId))
        .value
        ?.where(
          (c) => c.kind == ConversationKind.direct && c.memberIds.contains(id),
        )
        .firstOrNull;
    final escolha = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (folha) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (direta != null)
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline),
                title: Text('Conversar com $nome'),
                onTap: () => Navigator.pop(folha, 'conversar'),
              ),
            if (souAdmin)
              ListTile(
                leading: const Icon(Icons.shield_outlined),
                title: Text(
                  group.isAdmin(id) ? 'Tirar o admin' : 'Tornar admin',
                ),
                onTap: () => Navigator.pop(folha, 'admin'),
              ),
            if (souAdmin)
              ListTile(
                leading: Icon(
                  Icons.person_remove_outlined,
                  color: Theme.of(folha).colorScheme.error,
                ),
                title: Text(
                  'Remover $nome do grupo',
                  style: TextStyle(color: Theme.of(folha).colorScheme.error),
                ),
                onTap: () => Navigator.pop(folha, 'remover'),
              ),
          ],
        ),
      ),
    );
    if (escolha == null || !context.mounted) return;
    final repo = ref.read(repositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    Future<void> tentar(Future<void> Function() acao) async {
      try {
        await acao();
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(_mensagem(e))));
      }
    }

    switch (escolha) {
      case 'conversar':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ChatScreen(conversation: direta!, userId: userId),
          ),
        );
      case 'admin':
        await tentar(
          () => repo.setAdmin(
            groupId: group.id,
            userId: id,
            admin: !group.isAdmin(id),
            by: userId,
          ),
        );
      case 'remover':
        final ok = await _confirmar(
          context,
          titulo: 'Remover $nome?',
          texto:
              '$nome sai do grupo e da conversa do grupo. Para voltar, só com '
              'o código de convite.',
          acao: 'Remover',
        );
        if (ok) {
          await tentar(
            () => repo.removeMember(groupId: group.id, userId: id, by: userId),
          );
        }
    }
  }
}
