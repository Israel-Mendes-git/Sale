import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/calendar.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../pickers.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/range_bar.dart';
import 'availability_screen.dart';
import 'meeting_sheet.dart';

/// Calendário semanal do grupo: encontro fixo, Chamados agendados e os
/// horários em que todo mundo está livre.
class WeekScreen extends ConsumerStatefulWidget {
  const WeekScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends ConsumerState<WeekScreen> {
  var _weekOffset = 0;

  DateTime get _now => ref.read(clockProvider)();

  @override
  Widget build(BuildContext context) {
    final conversations =
        ref.watch(conversationsProvider(widget.userId)).value ?? [];
    final group = conversations
        .where((c) => c.kind == ConversationKind.group)
        .firstOrNull;
    final calendar = ref.watch(calendarProvider(widget.userId));

    final thisMonday = weekStart(_now);
    final monday = DateTime(
      thisMonday.year,
      thisMonday.month,
      thisMonday.day + 7 * _weekOffset,
    );
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Semana'),
        actions: [
          if (group != null)
            IconButton(
              tooltip: 'Encontro fixo',
              icon: const Icon(Icons.event_repeat),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                showDragHandle: true,
                builder: (_) => MeetingSheet(
                  conversation: group,
                  existing: calendar.value?.meetings
                      .where((m) => m.conversationId == group.id)
                      .firstOrNull,
                ),
              ),
            ),
          IconButton(
            tooltip: 'Minha disponibilidade',
            icon: const Icon(Icons.schedule),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AvailabilityScreen(userId: widget.userId),
              ),
            ),
          ),
        ],
      ),
      body: group == null
          ? const Center(child: Text('Entre num grupo para ver a semana.'))
          : calendar.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Erro: $e')),
              data: (data) {
                final days = planWeek(
                  data,
                  monday: monday,
                  memberIds: group.memberIds,
                );
                final window = _windowFor(days);
                return ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _WeekHeader(
                      label: '${ddmm(monday)} – ${ddmm(sunday)}',
                      onPrevious: () => setState(() => _weekOffset--),
                      onNext: () => setState(() => _weekOffset++),
                      onToday: _weekOffset == 0
                          ? null
                          : () => setState(() => _weekOffset = 0),
                    ),
                    _Legend(memberIds: group.memberIds, userId: widget.userId),
                    for (final day in days)
                      _DayCard(
                        day: day,
                        group: group,
                        userId: widget.userId,
                        window: window,
                        now: _now,
                      ),
                  ],
                );
              },
            ),
    );
  }

  /// Janela de horário comum a todos os dias da semana, arredondada em horas.
  TimeRange _windowFor(List<DayPlan> days) {
    var start = minutesPerDay;
    var end = 0;
    void include(int s, int e) {
      start = math.min(start, s);
      end = math.max(end, e);
    }

    for (final d in days) {
      for (final ranges in d.availability.values) {
        for (final r in ranges) {
          include(r.start, r.end);
        }
      }
      for (final m in d.meetings) {
        include(m.minute, math.min(m.minute + 60, minutesPerDay));
      }
      for (final c in d.chamados) {
        final m = c.scheduledFor!.hour * 60 + c.scheduledFor!.minute;
        include(m, math.min(m + 60, minutesPerDay));
      }
    }
    if (start >= end) return const TimeRange(18 * 60, 24 * 60);

    start = start ~/ 60 * 60;
    end = math.min(minutesPerDay, (end + 59) ~/ 60 * 60);
    // Pelo menos 4 h, para a barra não virar um borrão.
    if (end - start < 4 * 60) {
      start = math.max(0, end - 4 * 60);
      end = math.max(end, start + 4 * 60);
    }
    return TimeRange(start, end);
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({
    required this.label,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });

  final String label;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback? onToday;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Semana anterior',
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
          ),
          Text(label, style: Theme.of(context).textTheme.titleMedium),
          IconButton(
            tooltip: 'Próxima semana',
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
          ),
          const Spacer(),
          if (onToday != null)
            TextButton(onPressed: onToday, child: const Text('Esta semana')),
        ],
      ),
    );
  }
}

class _Legend extends ConsumerWidget {
  const _Legend({required this.memberIds, required this.userId});

  final List<String> memberIds;
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    Widget dot(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        children: [
          for (final id in memberIds)
            dot(
              Color(repo.profile(id).color),
              id == userId ? 'Você' : repo.profile(id).name,
            ),
          dot(signalYellow, 'todos livres (toque para chamar)'),
        ],
      ),
    );
  }
}

class _DayCard extends ConsumerWidget {
  const _DayCard({
    required this.day,
    required this.group,
    required this.userId,
    required this.window,
    required this.now,
  });

  final DayPlan day;
  final Conversation group;
  final String userId;
  final TimeRange window;
  final DateTime now;

  bool get _isToday => sameDate(day.date, now);
  bool get _isPast => day.date.isBefore(dateOnly(now));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final repo = ref.watch(repositoryProvider);

    return Opacity(
      opacity: _isPast ? 0.5 : 1,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: _isToday
              ? BorderSide(color: scheme.primary, width: 1.5)
              : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    weekdayLong[day.date.weekday - 1],
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(ddmm(day.date), style: theme.textTheme.bodyMedium),
                  if (_isToday) ...[
                    const SizedBox(width: 8),
                    Text(
                      'hoje',
                      style: TextStyle(
                        color: scheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
              for (final m in day.meetings)
                _MeetingTile(
                  occurrence: m,
                  group: group,
                  userId: userId,
                  editable: !_isPast,
                ),
              for (final c in day.chamados)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Text('🦇', style: TextStyle(fontSize: 22)),
                  title: Text(
                    'Chamado · ${hhmm(c.scheduledFor!)} · ${chamadoGame(c)}',
                  ),
                  subtitle: Text(
                    c.authorId == userId
                        ? 'você chamou'
                        : '${repo.profile(c.authorId).name} chamou',
                  ),
                ),
              const SizedBox(height: 8),
              _Timeline(
                day: day,
                window: window,
                userId: userId,
                onTapFree: _isPast
                    ? null
                    : (r) => _scheduleChamado(context, ref, r),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Cria um Chamado agendado para o grupo dentro da faixa livre tocada.
  Future<void> _scheduleChamado(
    BuildContext context,
    WidgetRef ref,
    TimeRange range,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    var initial = range.start;
    if (_isToday) {
      // Hoje, sugere o próximo quarto de hora a partir de agora.
      final nowMinute = now.hour * 60 + now.minute;
      initial = math.max(initial, (nowMinute ~/ 15 + 1) * 15);
    }
    if (initial >= range.end) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Essa janela já passou.')),
      );
      return;
    }
    final minute = await pickMinute(
      context,
      initial: initial,
      help: 'Chamar o grupo em ${dayLabel(day.date)} às…',
    );
    if (minute == null) return;
    final at = day.date.add(Duration(minutes: minute));
    if (!at.isAfter(now)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Escolha um horário que ainda não passou.'),
        ),
      );
      return;
    }
    await ref
        .read(repositoryProvider)
        .sendChamado(
          conversationId: group.id,
          authorId: userId,
          targetIds: [
            for (final id in group.memberIds)
              if (id != userId) id,
          ],
          scheduledFor: at,
        );
    messenger.showSnackBar(
      SnackBar(
        content: Text('Chamado agendado: ${dayLabel(day.date)} às ${hhmm(at)}'),
      ),
    );
  }
}

class _Timeline extends ConsumerWidget {
  const _Timeline({
    required this.day,
    required this.window,
    required this.userId,
    required this.onTapFree,
  });

  final DayPlan day;
  final TimeRange window;
  final String userId;
  final void Function(TimeRange range)? onTapFree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    String rangeLabel(TimeRange r) =>
        '${minutesLabel(r.start)}–${minutesLabel(r.end)}';

    Widget row(Widget leading, Widget bar) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 56, child: leading),
          Expanded(child: bar),
        ],
      ),
    );

    return Column(
      children: [
        row(
          const SizedBox.shrink(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(minutesLabel(window.start), style: labelStyle),
              Text(
                minutesLabel((window.start + window.end) ~/ 2 ~/ 60 * 60),
                style: labelStyle,
              ),
              Text(minutesLabel(window.end), style: labelStyle),
            ],
          ),
        ),
        for (final entry in day.availability.entries)
          row(
            Row(
              children: [
                Avatar(repo.profile(entry.key), radius: 9),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    entry.key == userId ? 'Você' : repo.profile(entry.key).name,
                    style: labelStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            RangeBar(
              ranges: entry.value,
              window: window,
              color: Color(repo.profile(entry.key).color)
                  .withValues(alpha: 0.7),
              height: 10,
            ),
          ),
        row(
          Text(
            'Todos',
            style: labelStyle?.copyWith(
              color: signalYellow,
              fontWeight: FontWeight.bold,
            ),
          ),
          day.everyoneFree.isEmpty
              ? Align(
                  alignment: Alignment.centerLeft,
                  child: Text('ninguém livre junto', style: labelStyle),
                )
              : RangeBar(
                  ranges: day.everyoneFree,
                  window: window,
                  color: signalYellow,
                  height: 18,
                  onTap: onTapFree,
                  tooltipBuilder: (r) => 'Todos livres ${rangeLabel(r)}',
                ),
        ),
      ],
    );
  }
}

class _MeetingTile extends ConsumerWidget {
  const _MeetingTile({
    required this.occurrence,
    required this.group,
    required this.userId,
    required this.editable,
  });

  final MeetingOccurrence occurrence;
  final Conversation group;
  final String userId;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final repo = ref.watch(repositoryProvider);
    final o = occurrence;
    final mine = o.rsvps[userId]?.status;
    final canAnswer = editable && !o.skipped;

    Future<void> answer(RsvpStatus status) async {
      String? reason;
      if (status == RsvpStatus.notGoing) {
        final typed = await _askReason(context);
        // Fechou o diálogo sem escolher: não responde nada.
        if (typed == null || !context.mounted) return;
        reason = typed.isEmpty ? null : typed;
      }
      await repo.setRsvp(
        Rsvp(
          meetingId: o.meeting.id,
          date: o.date,
          userId: userId,
          status: status,
          reason: reason,
        ),
      );
    }

    final title = StringBuffer('Encontro fixo · ${minutesLabel(o.minute)}');
    if (o.meeting.game != null) title.write(' · ${o.meeting.game}');

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_repeat, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.toString(),
                      style: theme.textTheme.titleSmall?.copyWith(
                        decoration: o.skipped
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    if (o.skipped)
                      Text(
                        'pulado esta semana',
                        style: theme.textTheme.bodySmall,
                      )
                    else if (o.moved)
                      Text(
                        'horário só desta semana (normal: '
                        '${minutesLabel(o.meeting.minute)})',
                        style: theme.textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              if (editable)
                PopupMenuButton<_MeetingAction>(
                  tooltip: 'Opções do encontro',
                  onSelected: (a) => _act(context, ref, a),
                  itemBuilder: (_) => [
                    if (!o.skipped)
                      const PopupMenuItem(
                        value: _MeetingAction.skip,
                        child: Text('Pular esta semana'),
                      ),
                    const PopupMenuItem(
                      value: _MeetingAction.move,
                      child: Text('Mudar horário só desta semana'),
                    ),
                    if (o.skipped || o.moved)
                      const PopupMenuItem(
                        value: _MeetingAction.reset,
                        child: Text('Voltar ao normal'),
                      ),
                  ],
                ),
            ],
          ),
          if (!o.skipped) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final (status, label) in const [
                  (RsvpStatus.going, 'Vou'),
                  (RsvpStatus.maybe, 'Talvez'),
                  (RsvpStatus.notGoing, 'Não vou'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: mine == status,
                    onSelected: canAnswer ? (_) => answer(status) : null,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                for (final id in group.memberIds)
                  if (id != userId)
                    _RsvpBadge(profile: repo.profile(id), rsvp: o.rsvps[id]),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    _MeetingAction a,
  ) async {
    final repo = ref.read(repositoryProvider);
    final o = occurrence;
    switch (a) {
      case _MeetingAction.skip:
        await repo.setMeetingException(
          MeetingException(
            meetingId: o.meeting.id,
            date: o.date,
            skipped: true,
          ),
        );
      case _MeetingAction.move:
        final minute = await pickMinute(
          context,
          initial: o.minute,
          help: 'Horário só de ${dayLabel(o.date)}',
        );
        if (minute == null) return;
        await repo.setMeetingException(
          MeetingException(
            meetingId: o.meeting.id,
            date: o.date,
            minute: minute,
          ),
        );
      case _MeetingAction.reset:
        await repo.clearMeetingException(o.meeting.id, o.date);
    }
  }

  /// Nulo = desistiu; vazio = sem motivo.
  Future<String?> _askReason(BuildContext context) => showDialog<String>(
    context: context,
    builder: (_) => const _ReasonDialog(),
  );
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

enum _MeetingAction { skip, move, reset }

class _RsvpBadge extends StatelessWidget {
  const _RsvpBadge({required this.profile, required this.rsvp});

  final Profile profile;
  final Rsvp? rsvp;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (rsvp?.status) {
      RsvpStatus.going => ('✅', 'vai'),
      RsvpStatus.maybe => ('🤔', 'talvez'),
      RsvpStatus.notGoing => ('❌', 'não vai'),
      null => ('…', 'sem resposta'),
    };
    final reason = rsvp?.reason;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Avatar(profile, radius: 10),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '${profile.name} $icon $label${reason == null ? '' : ' ($reason)'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
