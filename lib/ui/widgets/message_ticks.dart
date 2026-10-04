import 'package:flutter/material.dart';

import '../../domain/models.dart';

/// As marquinhas da mensagem que eu mandei: um tique quando ela está no
/// servidor, dois quando chegou no aparelho de quem vai ler e dois na cor da
/// confirmação quando essa pessoa abriu a conversa.
class MessageTicks extends StatelessWidget {
  const MessageTicks(this.status, {super.key, this.size = 14});

  final MessageStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Icon(
      status == MessageStatus.sent ? Icons.check : Icons.done_all,
      size: size,
      color: status == MessageStatus.read
          ? scheme.tertiary
          : scheme.onSurfaceVariant,
      semanticLabel: switch (status) {
        MessageStatus.sent => 'enviada',
        MessageStatus.delivered => 'entregue',
        MessageStatus.read => 'lida',
      },
    );
  }
}
