import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/discord.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';

/// O Discord do grupo: o canal onde o Chamado é postado e o servidor de onde
/// sai quem está na call.
class DiscordScreen extends ConsumerStatefulWidget {
  const DiscordScreen({super.key, required this.group});

  final Group group;

  @override
  ConsumerState<DiscordScreen> createState() => _DiscordScreenState();
}

class _DiscordScreenState extends ConsumerState<DiscordScreen> {
  late final _webhook = TextEditingController(
    text: widget.group.discordWebhook ?? '',
  );
  late final _servidor = TextEditingController(
    text: widget.group.discordServidor ?? '',
  );
  var _salvando = false;
  var _testando = false;

  @override
  void dispose() {
    _webhook.dispose();
    _servidor.dispose();
    super.dispose();
  }

  String? get _erroDoWebhook {
    final t = _webhook.text.trim();
    if (t.isEmpty || formatoDoWebhook.hasMatch(t)) return null;
    return 'Não parece um webhook do Discord.';
  }

  String? get _erroDoServidor {
    final t = _servidor.text.trim();
    if (t.isEmpty || formatoDoServidor.hasMatch(t)) return null;
    return 'O ID do servidor é só números.';
  }

  void _avisar(String texto) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(texto)));

  Future<void> _testar() async {
    setState(() => _testando = true);
    final ok = await testarWebhook(_webhook.text.trim());
    if (!mounted) return;
    setState(() => _testando = false);
    _avisar(
      ok
          ? 'Mensagem de teste enviada: confira o canal.'
          : 'O Discord recusou. Confira a URL do webhook.',
    );
  }

  Future<void> _salvar() async {
    if (_erroDoWebhook != null || _erroDoServidor != null) return;
    setState(() => _salvando = true);
    try {
      final webhook = _webhook.text.trim();
      final servidor = _servidor.text.trim();
      await ref
          .read(repositoryProvider)
          .setGroupDiscord(
            groupId: widget.group.id,
            webhook: webhook.isEmpty ? null : webhook,
            servidor: servidor.isEmpty ? null : servidor,
          );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _avisar('Não deu para salvar: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final webhookValido =
        _webhook.text.trim().isNotEmpty && _erroDoWebhook == null;
    return Scaffold(
      appBar: AppBar(title: const Text('Discord do grupo')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Canal dos Chamados', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Cada Chamado do grupo é postado neste canal. No Discord: '
            'Editar canal → Integrações → Webhooks → Novo webhook → Copiar '
            'URL do webhook.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _webhook,
            decoration: InputDecoration(
              labelText: 'URL do webhook',
              hintText: 'https://discord.com/api/webhooks/…',
              errorText: _erroDoWebhook,
            ),
            onChanged: (_) => setState(() {}),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: webhookValido && !_testando ? _testar : null,
              icon: const Icon(Icons.send_outlined),
              label: Text(_testando ? 'Testando…' : 'Mandar um teste'),
            ),
          ),
          const SizedBox(height: 16),
          Text('Quem está na call', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Com o widget do servidor ligado, a conversa do grupo mostra quem '
            'está numa call agora. No Discord: Configurações do servidor → '
            'Widget → Ativar widget do servidor; o ID do servidor está ali.',
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
          FilledButton(
            onPressed: _salvando ? null : _salvar,
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
