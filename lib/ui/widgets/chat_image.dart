import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';

/// A imagem de uma mensagem, do tamanho que cabe na bolha.
///
/// O arquivo é baixado uma vez por aparelho (o repositório guarda) e fica no
/// provider enquanto a conversa está aberta, para rolar a conversa para cima e
/// para baixo não pedir a mesma imagem de novo.
///
/// Enquanto ela não chega, o espaço dela já está reservado: a mensagem guarda
/// o tamanho da imagem, então a conversa não salta quando o arquivo termina.
class ChatImage extends ConsumerWidget {
  const ChatImage({super.key, required this.attachment, this.onTap});

  final Attachment attachment;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = ref.watch(attachmentProvider(attachment.path));

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          // Sem o tamanho (imagem de versão antiga do app), um retrato comum.
          aspectRatio: attachment.aspectRatio ?? 3 / 4,
          child: switch (bytes) {
            AsyncData(:final value) => Image.memory(value, fit: BoxFit.cover),
            AsyncError() => ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Center(
                child: IconButton(
                  tooltip: 'Tentar de novo',
                  icon: const Icon(Icons.refresh),
                  onPressed: () =>
                      ref.invalidate(attachmentProvider(attachment.path)),
                ),
              ),
            ),
            _ => ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: const Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          },
        ),
      ),
    );
  }
}

/// A imagem sozinha na tela, para ver de perto: dá para aproximar e arrastar.
class FullImageScreen extends ConsumerWidget {
  const FullImageScreen({
    super.key,
    required this.attachment,
    required this.author,
    this.caption,
  });

  final Attachment attachment;
  final String author;
  final String? caption;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(attachmentProvider(attachment.path)).value;
    final legenda = caption;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        foregroundColor: Colors.white,
        title: Text(author),
      ),
      body: Center(
        child: bytes == null
            ? const CircularProgressIndicator()
            : InteractiveViewer(
                maxScale: 6,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
      ),
      bottomNavigationBar: legenda == null || legenda.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  legenda,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
    );
  }
}

/// Os bytes de um anexo, pelo caminho dele no Storage.
final attachmentProvider = FutureProvider.family<Uint8List, String>(
  (ref, path) => ref.watch(repositoryProvider).attachmentBytes(path),
);
