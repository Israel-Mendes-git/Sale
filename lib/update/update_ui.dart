import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ota_update/ota_update.dart';

import 'update_providers.dart';
import 'update_service.dart';

/// Faixa no topo do app quando há versão nova.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final update = ref.watch(availableUpdateProvider).value;
    if (update == null || !ref.watch(updateBannerVisibleProvider)) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.system_update, color: scheme.onTertiaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Versão ${update.version} disponível',
                  style: TextStyle(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => ref
                    .read(dismissedUpdateProvider.notifier)
                    .dismiss(update.version),
                child: const Text('Depois'),
              ),
              FilledButton(
                onPressed: () => showUpdateDialog(context, update),
                child: const Text('Atualizar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Consulta na hora e mostra o resultado (menu "Verificar atualização").
Future<void> checkUpdateNow(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  ref.invalidate(availableUpdateProvider);
  try {
    final update = await ref.read(availableUpdateProvider.future);
    if (!context.mounted) return;
    if (update == null) {
      final installed = await ref.read(installedVersionProvider.future);
      messenger.showSnackBar(
        SnackBar(content: Text('Você já está na última versão ($installed).')),
      );
    } else {
      await showUpdateDialog(context, update);
    }
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text('Não deu para verificar agora: $e')),
    );
  }
}

Future<void> showUpdateDialog(BuildContext context, AppRelease update) =>
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateDialog(update: update),
    );

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.update});

  final AppRelease update;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  OtaEvent? _event;
  var _started = false;

  bool get _failed => switch (_event?.status) {
    OtaStatus.DOWNLOAD_ERROR ||
    OtaStatus.CHECKSUM_ERROR ||
    OtaStatus.INTERNAL_ERROR ||
    OtaStatus.INSTALLATION_ERROR ||
    OtaStatus.PERMISSION_NOT_GRANTED_ERROR ||
    OtaStatus.ALREADY_RUNNING_ERROR ||
    OtaStatus.CANCELED => true,
    _ => false,
  };

  void _start() {
    setState(() {
      _started = true;
      _event = null;
    });
    try {
      OtaUpdate()
          .execute(
            widget.update.apkUrl,
            destinationFilename: 'sale-${widget.update.version}.apk',
            sha256checksum: widget.update.sha256,
          )
          .listen(
            (e) {
              if (mounted) setState(() => _event = e);
            },
            onError: (Object e) {
              if (mounted) {
                setState(
                  () => _event = OtaEvent(OtaStatus.INTERNAL_ERROR, '$e'),
                );
              }
            },
          );
    } catch (e) {
      setState(() => _event = OtaEvent(OtaStatus.INTERNAL_ERROR, '$e'));
    }
  }

  String _statusText() {
    final e = _event;
    if (e == null) return 'Preparando o download…';
    return switch (e.status) {
      OtaStatus.DOWNLOADING => 'Baixando… ${e.value ?? 0}%',
      OtaStatus.INSTALLING ||
      OtaStatus.INSTALLATION_DONE => 'Abrindo o instalador. Confirme por lá.',
      OtaStatus.PERMISSION_NOT_GRANTED_ERROR =>
        'O Android bloqueou. Permita "instalar apps desconhecidos" para o '
            'Sale? e tente de novo.',
      OtaStatus.CHECKSUM_ERROR =>
        'O arquivo baixado veio corrompido. Tente de novo.',
      OtaStatus.DOWNLOAD_ERROR => 'Falha no download. Confira a internet.',
      OtaStatus.ALREADY_RUNNING_ERROR => 'Já existe um download em andamento.',
      OtaStatus.CANCELED => 'Download cancelado.',
      _ => 'Algo deu errado: ${e.value ?? e.status.name}',
    };
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.update;
    final downloading = _event?.status == OtaStatus.DOWNLOADING;
    final progress = downloading
        ? (int.tryParse(_event?.value ?? '') ?? 0) / 100
        : null;

    return AlertDialog(
      title: Text('Sale? ${u.version}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!_started) ...[
              Text('Novidades', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(u.notes.isEmpty ? 'Melhorias e correções.' : u.notes),
            ] else ...[
              Text(_statusText()),
              if (!_failed) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(value: progress),
              ],
            ],
          ],
        ),
      ),
      actions: [
        if (!_started || _failed)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Agora não'),
          ),
        if (!_started)
          FilledButton(
            onPressed: _start,
            child: const Text('Baixar e instalar'),
          )
        else if (_failed)
          FilledButton(onPressed: _start, child: const Text('Tentar de novo'))
        else
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
      ],
    );
  }
}
