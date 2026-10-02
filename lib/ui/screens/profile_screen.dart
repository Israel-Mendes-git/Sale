import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repository.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';
import '../../update/update_providers.dart';
import '../../update/update_ui.dart';
import '../icons.dart';
import '../widgets/avatar.dart';
import '../widgets/sheet.dart';
import 'appearance_screen.dart';
import 'stats_screen.dart';

/// Nome e respostas próprias: cada pessoa conta as situações dela.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final _name = TextEditingController(text: _me.named ? _me.name : '');
  // Recria a tela ao mudar algo no repositório (nome, respostas).
  var _version = 0;

  Profile get _me => ref.read(repositoryProvider).profile(widget.userId);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(repositoryProvider)
          .renameProfile(widget.userId, _name.text);
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _version++);
      messenger.showSnackBar(const SnackBar(content: Text('Nome salvo.')));
    } on ArgumentError {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('O nome precisa ter de 1 a $maxNameLength letras.'),
        ),
      );
    }
  }

  Future<void> _addReply() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewReplySheet(userId: widget.userId),
    );
    if (created == true) setState(() => _version++);
  }

  Future<void> _remove(QuickReply r) async {
    await ref.read(repositoryProvider).removeQuickReply(r.id);
    setState(() => _version++);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ref.watch(repositoryProvider);
    final me = _me;
    final mine = [
      for (final r in repo.quickRepliesFor(widget.userId))
        if (r.ownerId == widget.userId) r,
    ];

    return Scaffold(
      key: ValueKey(_version),
      appBar: AppBar(title: const Text('Meu perfil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Avatar(me, radius: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  me.named ? me.name : 'Sem nome ainda',
                  style: theme.textTheme.headlineSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Como o grupo te chama', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            maxLength: maxNameLength,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Seu nome'),
            onSubmitted: (_) => _saveName(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _saveName,
              child: const Text('Salvar nome'),
            ),
          ),
          const Divider(height: 32),
          _GroupCard(userId: widget.userId),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.emoji_events_outlined),
            title: const Text('Placar'),
            subtitle: const Text(
              'Atraso, quem mais chama e o jogo mais chamado',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => StatsScreen(userId: widget.userId),
              ),
            ),
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.palette_outlined),
            title: const Text('Aparência'),
            subtitle: Text(
              '${ref.watch(appearanceProvider).palette.name} · '
              'escolha o tema do app',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AppearanceScreen())),
          ),
          const Divider(height: 32),
          Text('Suas respostas', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'As situações que são só suas. Viram botão quando alguém te chamar, '
            'junto com "Bora!", "Chego em…" e "Hoje não".',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          if (mine.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Nenhuma ainda. Ex.: "No trabalho", "Passeando com o cachorro".',
              ),
            ),
          for (final r in mine)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(replyIcon(r.icon), size: 26),
              title: Text(r.label),
              subtitle: Text(_kindLabel(r.kind)),
              trailing: IconButton(
                tooltip: 'Remover "${r.label}"',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _remove(r),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('Nova resposta'),
            onPressed: _addReply,
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('Verificar atualização'),
            subtitle: Text(
              ref.watch(installedVersionProvider).value == null
                  ? 'Sale?'
                  : 'Versão ${ref.watch(installedVersionProvider).value}',
            ),
            onTap: () => checkUpdateNow(context, ref),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(
              'Sair',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () => ref.read(currentUserProvider.notifier).signOut(),
          ),
        ],
      ),
    );
  }
}

String _kindLabel(ReplyKind kind) => switch (kind) {
  ReplyKind.yes => 'vou já',
  ReplyKind.later => 'vou, mas depois (pergunta quanto tempo)',
  ReplyKind.no => 'não vou',
  ReplyKind.snooze => 'me chama depois',
};

class _NewReplySheet extends ConsumerStatefulWidget {
  const _NewReplySheet({required this.userId});

  final String userId;

  @override
  ConsumerState<_NewReplySheet> createState() => _NewReplySheetState();
}

class _NewReplySheetState extends ConsumerState<_NewReplySheet> {
  final _label = TextEditingController();
  var _icon = choosableReplyIcons.first;
  var _kind = ReplyKind.later;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(repositoryProvider)
          .addQuickReply(
            ownerId: widget.userId,
            icon: _icon,
            label: _label.text,
            kind: _kind,
          );
      if (mounted) Navigator.pop(context, true);
    } on ArgumentError {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Escreva a situação (até $maxReplyLength letras).'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SheetBody(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nova resposta', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _label,
              autofocus: true,
              maxLength: maxReplyLength,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Situação',
                hintText: 'Tô jantando',
              ),
            ),
            const SizedBox(height: 8),
            Text('Desenho', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            // Grade de ícones: o mesmo desenho aparece igual em todo celular.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in choosableReplyIcons)
                  _IconChoice(
                    name: name,
                    chosen: name == _icon,
                    onTap: () => setState(() => _icon = name),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Isso quer dizer', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (kind, label) in const [
                  (ReplyKind.yes, 'Vou já'),
                  (ReplyKind.later, 'Vou, mas depois'),
                  (ReplyKind.no, 'Não vou'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (_kind == ReplyKind.later)
              Text(
                'Na hora de responder, o app pergunta em quanto tempo você chega.',
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: const Text('Salvar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// O grupo e o código que convida alguém novo.
class _GroupCard extends ConsumerWidget {
  const _GroupCard({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final group = ref.watch(groupsProvider(userId)).value?.firstOrNull;
    if (group == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Seu grupo', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Quem tem o código entra no grupo e passa a ver as conversas, os '
          'jogos e o encontro fixo.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(group.name),
          subtitle: Text('Código: ${group.inviteCode}'),
          trailing: IconButton(
            tooltip: 'Copiar o código',
            icon: const Icon(Icons.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: group.inviteCode));
              if (!context.mounted) return;
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('Código copiado.')));
            },
          ),
        ),
      ],
    );
  }
}

/// Um ícone da grade de escolha, com o escolhido em destaque.
class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.name,
    required this.chosen,
    required this.onTap,
  });

  final String name;
  final bool chosen;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: chosen ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          replyIcon(name),
          color: chosen ? scheme.onPrimary : scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
