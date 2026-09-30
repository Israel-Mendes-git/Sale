import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/calendar.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../pickers.dart';

/// Faixas em que a pessoa costuma estar livre, por dia da semana.
class AvailabilityScreen extends ConsumerWidget {
  const AvailabilityScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final calendar = ref.watch(calendarProvider(userId));
    return Scaffold(
      appBar: AppBar(title: const Text('Minha disponibilidade')),
      body: calendar.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Erro: $e')),
        data: (data) {
          final mine = [
            for (final a in data.availability)
              if (a.userId == userId) a,
          ];
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Marque quando você costuma estar livre pra jogar. O '
                  'calendário cruza os horários de todo mundo.',
                ),
              ),
              for (var weekday = 1; weekday <= 7; weekday++)
                _WeekdayRow(
                  weekday: weekday,
                  userId: userId,
                  slots: [
                    for (final a in mine)
                      if (a.weekday == weekday) a,
                  ]..sort((a, b) => a.range.start.compareTo(b.range.start)),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _WeekdayRow extends ConsumerWidget {
  const _WeekdayRow({
    required this.weekday,
    required this.userId,
    required this.slots,
  });

  final int weekday;
  final String userId;
  final List<Availability> slots;

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = weekdayLong[weekday - 1];
    final start = await pickMinute(
      context,
      initial: 20 * 60,
      help: 'Livre a partir de ($name)',
    );
    if (start == null || !context.mounted) return;
    var end = await pickMinute(
      context,
      initial: (start + 3 * 60).clamp(0, minutesPerDay - 1),
      help: 'Até ($name) — 00:00 = meia-noite',
    );
    if (end == null) return;
    // O seletor não tem 24:00; 00:00 como fim quer dizer meia-noite.
    if (end == 0) end = minutesPerDay;
    if (end <= start) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'O fim precisa ser depois do início. Para passar da meia-noite, '
            'crie uma faixa em cada dia.',
          ),
        ),
      );
      return;
    }
    await ref
        .read(repositoryProvider)
        .addAvailability(
          userId: userId,
          weekday: weekday,
          range: TimeRange(start, end),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(weekdayLong[weekday - 1]),
      subtitle: slots.isEmpty
          ? const Text('sem horário marcado')
          : Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final a in slots)
                  InputChip(
                    label: Text(
                      '${minutesLabel(a.range.start)}–${minutesLabel(a.range.end)}',
                    ),
                    onDeleted: () =>
                        ref.read(repositoryProvider).removeAvailability(a.id),
                    deleteButtonTooltipMessage: 'Remover',
                  ),
              ],
            ),
      trailing: IconButton(
        tooltip: 'Adicionar horário em ${weekdayLong[weekday - 1]}',
        icon: const Icon(Icons.add),
        onPressed: () => _add(context, ref),
      ),
    );
  }
}
