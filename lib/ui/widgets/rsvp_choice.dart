import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/calendar.dart';
import '../../state/providers.dart';

/// "Vou · Talvez · Não vou" de uma ocorrência do encontro fixo. Aparece na
/// aba Semana e no aviso do encontro que está chegando, na lista de
/// conversas.
class RsvpChoice extends ConsumerWidget {
  const RsvpChoice({
    super.key,
    required this.occurrence,
    required this.userId,
    this.enabled = true,
  });

  final MeetingOccurrence occurrence;
  final String userId;

  /// Dia que já passou não deixa confirmar.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = occurrence.rsvps[userId]?.status;

    Future<void> answer(RsvpStatus status) async {
      String? reason;
      if (status == RsvpStatus.notGoing) {
        final typed = await showDialog<String>(
          context: context,
          builder: (_) => const _ReasonDialog(),
        );
        // Fechou o diálogo sem escolher: não responde nada.
        if (typed == null || !context.mounted) return;
        reason = typed.isEmpty ? null : typed;
      }
      await ref
          .read(repositoryProvider)
          .setRsvp(
            Rsvp(
              meetingId: occurrence.meeting.id,
              date: occurrence.date,
              userId: userId,
              status: status,
              reason: reason,
            ),
          );
    }

    return Wrap(
      spacing: 8,
      children: [
        for (final (status, label) in const [
          (RsvpStatus.going, 'Vou'),
          (RsvpStatus.maybe, 'Talvez'),
          (RsvpStatus.notGoing, 'Não vou'),
        ])
          ChoiceChip(
            label: Text(label),
            selected: mine == status,
            onSelected: enabled ? (_) => answer(status) : null,
          ),
      ],
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog();

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Não vai? Conta o motivo'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Opcional'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ''),
          child: const Text('Sem motivo'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('Enviar'),
        ),
      ],
    );
  }
}
