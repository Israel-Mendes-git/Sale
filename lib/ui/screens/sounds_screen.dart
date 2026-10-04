import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repository.dart';
import '../../domain/sounds.dart';
import '../../push/sons.dart';
import '../../state/providers.dart';
import '../widgets/sheet.dart';

/// "Meu perfil → Som do Chamado": com que som o seu Chamado toca no celular
/// de quem você chama, mais os sons que o grupo subiu.
///
/// O som escolhido aqui é o que já vem marcado na tela do Chamado; lá dá para
/// trocar na hora, sem mexer neste.
class SoundsScreen extends ConsumerStatefulWidget {
  const SoundsScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<SoundsScreen> createState() => _SoundsScreenState();
}

class _SoundsScreenState extends ConsumerState<SoundsScreen> {
  @override
  void dispose() {
    pararSom();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      final message = switch (e) {
        StateError(:final message) => message,
        ArgumentError(:final message) => '$message',
        _ => '$e',
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _choose(Sound sound) => _run(() async {
    // O som toca enquanto a escolha é gravada: quem escolhe ouve na hora.
    _play(sound);
    await ref.read(repositoryProvider).setProfileSound(widget.userId, sound.id);
  });

  /// Só ouvir, sem escolher. Sem esperar, para a tela não travar por causa de
  /// um arquivo que demora a baixar.
  void _play(Sound sound) => unawaited(
    ouvirSom(sound, baixar: ref.read(repositoryProvider).soundBytes),
  );

  Future<void> _remove(Sound sound) =>
      _run(() => ref.read(repositoryProvider).removeSound(sound.id));

  /// Pega um arquivo de áudio do celular e pergunta como chamá-lo.
  Future<void> _add() async {
    final Uint8List bytes;
    final String nome;
    try {
      final arquivo = await FilePicker.pickFile(type: FileType.audio);
      if (arquivo == null) return;
      nome = arquivo.name;
      bytes = await arquivo.readAsBytes();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Não deu para ler o arquivo: $e')));
      return;
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewSoundSheet(fileName: nome, bytes: bytes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sounds = ref.watch(soundsProvider);
    final profile = ref.watch(repositoryProvider).profile(widget.userId);

    return Scaffold(
      appBar: AppBar(title: const Text('Som do Chamado')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.library_music_outlined),
        label: const Text('Som novo'),
        onPressed: _add,
      ),
      body: sounds.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (list) {
          // Quem nunca escolheu toca o som da marca.
          final chosen =
              profile.soundId ??
              list
                  .where((s) => s.builtIn && s.file == defaultSoundKey)
                  .firstOrNull
                  ?.id;

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'O som toca no celular de quem você chama. Na hora de '
                  'disparar dá para trocar, e o som novo que você subir fica '
                  'na lista do grupo.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              for (final sound in list)
                _SoundTile(
                  sound: sound,
                  chosen: sound.id == chosen,
                  onTap: () => _choose(sound),
                  onPlay: () => _play(sound),
                  onRemove: sound.builtIn ? null : () => _remove(sound),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  'Som do grupo toca em cada celular depois que o app abre uma '
                  'vez e o baixa. Até lá, o Chamado dele toca o som da marca.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SoundTile extends StatelessWidget {
  const _SoundTile({
    required this.sound,
    required this.chosen,
    required this.onTap,
    required this.onPlay,
    this.onRemove,
  });

  final Sound sound;
  final bool chosen;
  final VoidCallback onTap;
  final VoidCallback onPlay;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        chosen ? Icons.radio_button_checked : Icons.radio_button_off,
        color: chosen ? scheme.primary : null,
      ),
      title: Text(sound.name),
      subtitle: Text(sound.builtIn ? 'Vem no app' : 'Do grupo'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Ouvir "${sound.name}"',
            icon: const Icon(Icons.play_arrow),
            onPressed: onPlay,
          ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remover "${sound.name}"',
              icon: const Icon(Icons.delete_outline),
              onPressed: onRemove,
            ),
        ],
      ),
      // Escolher também toca: escolher som sem ouvir é escolher no escuro.
      onTap: onTap,
    );
  }
}

/// Como chamar o som que acabou de ser escolhido no celular.
class _NewSoundSheet extends ConsumerStatefulWidget {
  const _NewSoundSheet({required this.fileName, required this.bytes});

  final String fileName;
  final Uint8List bytes;

  @override
  ConsumerState<_NewSoundSheet> createState() => _NewSoundSheetState();
}

class _NewSoundSheetState extends ConsumerState<_NewSoundSheet> {
  late final _name = TextEditingController(text: _sugestao());
  var _busy = false;
  String? _error;

  /// O nome do arquivo sem a extensão serve de palpite.
  String _sugestao() {
    final dot = widget.fileName.lastIndexOf('.');
    final base = dot == -1
        ? widget.fileName
        : widget.fileName.substring(0, dot);
    return base.length > maxSoundNameLength
        ? base.substring(0, maxSoundNameLength)
        : base;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(repositoryProvider)
          .addSound(
            name: _name.text,
            fileName: widget.fileName,
            bytes: widget.bytes,
          );
      if (mounted) Navigator.pop(context);
    } on ArgumentError {
      setState(() => _error = 'Escreva um nome para o som.');
    } on StateError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetBody(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Som novo', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(widget.fileName, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              maxLength: maxSoundNameLength,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Nome do som',
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _busy ? null : _save,
                child: const Text('Subir som'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
