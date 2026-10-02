import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/calendar.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../pickers.dart';
import '../widgets/sheet.dart';

/// Configura o encontro fixo semanal de um grupo.
class MeetingSheet extends ConsumerStatefulWidget {
  const MeetingSheet({super.key, required this.conversation, this.existing});

  final Conversation conversation;

  /// Encontro atual do grupo; nulo = criar um novo.
  final WeeklyMeeting? existing;

  @override
  ConsumerState<MeetingSheet> createState() => _MeetingSheetState();
}

class _MeetingSheetState extends ConsumerState<MeetingSheet> {
  var _weekday = 4;
  var _minute = 21 * 60;
  final _game = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.existing case final m?) {
      _weekday = m.weekday;
      _minute = m.minute;
      _game.text = m.game ?? '';
    }
  }

  @override
  void dispose() {
    _game.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final game = _game.text.trim();
    await ref
        .read(repositoryProvider)
        .saveMeeting(
          conversationId: widget.conversation.id,
          weekday: _weekday,
          minute: _minute,
          game: game.isEmpty ? null : game,
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await ref.read(repositoryProvider).deleteMeeting(widget.existing!.id);
    if (mounted) Navigator.pop(context);
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
            Text('Encontro fixo', style: theme.textTheme.titleLarge),
            Text(
              '${widget.conversation.name ?? 'Grupo'} · toda semana',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text('Dia', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var d = 1; d <= 7; d++)
                  ChoiceChip(
                    label: Text(weekdayShort[d - 1]),
                    selected: _weekday == d,
                    onSelected: (_) => setState(() => _weekday = d),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Horário', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule),
              label: Text(minutesLabel(_minute)),
              onPressed: () async {
                final m = await pickMinute(context, initial: _minute);
                if (m != null) setState(() => _minute = m);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _game,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Jogo (opcional)',
                hintText: 'Vazio = decide na hora',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Na hora do encontro o app vai disparar o Chamado para o grupo. '
              'Isso depende do servidor, que ainda não está ligado.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (widget.existing != null)
                  TextButton(
                    onPressed: _delete,
                    child: const Text('Remover encontro'),
                  ),
                const Spacer(),
                FilledButton(onPressed: _save, child: const Text('Salvar')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
