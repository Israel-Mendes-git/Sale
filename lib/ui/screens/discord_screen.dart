import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/discord.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';

/// O Discord do grupo ao vivo: quem está em cada call, quem está online e o
/// que cada um está jogando, e quanto cada um ficou em call na semana.
class DiscordAoVivoScreen extends ConsumerWidget {
  const DiscordAoVivoScreen({
    super.key,
    required this.group,
    required this.userId,
  });

  final Group group;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final servidor = group.discordServidor;
    final aoVivo = servidor == null
        ? null
        : ref.watch(discordAoVivoProvider(servidor));
    final agora = aoVivo?.value;
    final semana = ref
        .watch(tempoDeCallProvider((grupo: group.id, dias: 7)))
        .value;
    final repo = ref.watch(repositoryProvider);
    final foraDaCall = [
      for (final m in agora?.membros ?? const <MembroDoDiscord>[])
        if (!m.naCall) m,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(agora?.nome ?? 'Discord do grupo'),
        actions: [
          IconButton(
            tooltip: 'Configurar o Discord',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DiscordScreen(group: group, userId: userId),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: agora?.convite == null
          ? null
          : FloatingActionButton.extended(
              icon: const Icon(Icons.headset_mic),
              label: const Text('Abrir no Discord'),
              onPressed: () => launchUrl(
                Uri.parse(agora!.convite!),
                mode: LaunchMode.externalApplication,
              ),
            ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          if (servidor == null)
            const Text(
              'O grupo ainda não ligou um servidor do Discord. Toque na '
              'engrenagem lá em cima.',
            )
          else if (aoVivo!.isLoading && agora == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (agora == null)
            const Text(
              'Não deu para ler o servidor. Confira se o widget está ligado '
              '(Configurações do servidor → Widget).',
            )
          else ...[
            Text('Na call', style: theme.textTheme.titleMedium),
            if (agora.calls.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Ninguém em call agora.'),
              ),
            for (final call in agora.calls) ...[
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '🔊 ${call.nome}',
                  style: theme.textTheme.labelLarge,
                ),
              ),
              for (final m in call.membros) _Membro(m),
            ],
            const SizedBox(height: 16),
            Text(
              'Online no servidor (${agora.membros.length})',
              style: theme.textTheme.titleMedium,
            ),
            if (foraDaCall.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('Todo mundo que está online está em call.'),
              ),
            for (final m in foraDaCall) _Membro(m),
          ],
          if (semana != null && semana.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Tempo de call na semana', style: theme.textTheme.titleMedium),
            for (final t in semana)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                leading: const Icon(Icons.timer_outlined),
                title: Text(
                  t.userId == null
                      ? t.nome
                      : '${repo.profile(t.userId!).name} (${t.nome})',
                ),
                trailing: Text(duracaoEmTexto(t.minutos)),
              ),
          ],
        ],
      ),
    );
  }
}

/// Uma pessoa do servidor: a bolinha do status, o nome, o jogo e, na call,
/// se está com o microfone ou o som desligado.
class _Membro extends StatelessWidget {
  const _Membro(this.membro);

  final MembroDoDiscord membro;

  @override
  Widget build(BuildContext context) {
    final cor = switch (membro.status) {
      'idle' => Colors.amber,
      'dnd' => Colors.red,
      _ => Colors.green,
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 16,
            foregroundImage: membro.avatarUrl == null
                ? null
                : NetworkImage(membro.avatarUrl!),
            child: Text(membro.nome.characters.first.toUpperCase()),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: cor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
      title: Text(membro.nome),
      subtitle: membro.jogo == null ? null : Text('Jogando ${membro.jogo}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (membro.mudo)
            const Icon(Icons.mic_off, size: 18, semanticLabel: 'Mutado'),
          if (membro.surdo)
            const Icon(Icons.headset_off, size: 18, semanticLabel: 'Sem som'),
        ],
      ),
    );
  }
}

/// Configurar o Discord: o servidor do grupo (vale para todo mundo) e o seu
/// nome no Discord (só seu), que liga o tempo de call a você.
class DiscordScreen extends ConsumerStatefulWidget {
  const DiscordScreen({super.key, required this.group, required this.userId});

  final Group group;
  final String userId;

  @override
  ConsumerState<DiscordScreen> createState() => _DiscordScreenState();
}

class _DiscordScreenState extends ConsumerState<DiscordScreen> {
  late final _servidor = TextEditingController(
    text: widget.group.discordServidor ?? '',
  );
  late final _nome = TextEditingController(
    text: ref.read(repositoryProvider).profile(widget.userId).discordNome ?? '',
  );
  var _salvando = false;

  @override
  void dispose() {
    _servidor.dispose();
    _nome.dispose();
    super.dispose();
  }

  String? get _erroDoServidor {
    final t = _servidor.text.trim();
    if (t.isEmpty || formatoDoServidor.hasMatch(t)) return null;
    return 'O ID do servidor é só números.';
  }

  Future<void> _salvar() async {
    if (_erroDoServidor != null) return;
    setState(() => _salvando = true);
    final repo = ref.read(repositoryProvider);
    try {
      final servidor = _servidor.text.trim();
      if (servidor != (widget.group.discordServidor ?? '')) {
        await repo.setGroupDiscord(
          groupId: widget.group.id,
          servidor: servidor.isEmpty ? null : servidor,
        );
      }
      final nome = _nome.text.trim();
      if (nome != (repo.profile(widget.userId).discordNome ?? '')) {
        await repo.setDiscordName(widget.userId, nome);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Não deu para salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Configurar o Discord')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Servidor do grupo', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Com o widget do servidor ligado, o Sale? mostra quem está em cada '
            'call e o que cada um está jogando, guarda o tempo de call e avisa '
            'quando alguém abre uma call. No Discord: Configurações do '
            'servidor → Widget → Ativar widget do servidor; o ID do servidor '
            'está ali. Para o botão "Abrir no Discord", escolha também o canal '
            'de convite.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _servidor,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'ID do servidor',
              errorText: _erroDoServidor,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          Text('Seu nome no Discord', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Do jeito que aparece no servidor. É o que liga o tempo de call a '
            'você — no Placar e na conquista da call — e evita que o aviso '
            '"entrou na call" toque para quem já está lá.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _nome,
            maxLength: 40,
            decoration: const InputDecoration(labelText: 'Nome no Discord'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _salvando ? null : _salvar,
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
