import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/calendar.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../pickers.dart';
import '../widgets/avatar.dart';
import '../widgets/brand.dart';
import '../widgets/rsvp_choice.dart';
import 'availability_screen.dart';
import 'meeting_sheet.dart';

/// Semana do grupo, em texto e em ordem de importância: o encontro fixo,
/// quando todo mundo está livre, os meus horários e o dia a dia.
class WeekScreen extends ConsumerStatefulWidget {
  const WeekScreen({super.key, required this.userId});

  final String userId;

  @override
  ConsumerState<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends ConsumerState<WeekScreen> {
  var _weekOffset = 0;

  @override
  Widget build(BuildContext context) {
    final now = ref.read(clockProvider)();
    final conversations =
        ref.watch(conversationsProvider(widget.userId)).value ?? [];
    final group = conversations
        .where((c) => c.kind == ConversationKind.group)
        .firstOrNull;
    final calendar = ref.watch(calendarProvider(widget.userId));

    final thisMonday = weekStart(now);
    final monday = DateTime(
      thisMonday.year,
      thisMonday.month,
      thisMonday.day + 7 * _weekOffset,
    );
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);

    return Scaffold(
      appBar: AppBar(title: const Text('Semana')),
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
                final ctx = _WeekContext(
                  group: group,
                  userId: widget.userId,
                  now: now,
                  data: data,
                );
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
                    _MeetingSection(ctx: ctx, days: days),
                    _FreeTimesSection(ctx: ctx, days: days),
                    _MyTimesSection(ctx: ctx),
                    _DaysSection(ctx: ctx, days: days),
                  ],
                );
              },
            ),
    );
  }
}

/// O que todas as seções precisam saber.
class _WeekContext {
  const _WeekContext({
    required this.group,
    required this.userId,
    required this.now,
    required this.data,
  });

  final Conversation group;
  final String userId;
  final DateTime now;
  final CalendarData data;

  bool isPast(DateTime date) => date.isBefore(dateOnly(now));
  bool isToday(DateTime date) => sameDate(date, now);

  WeeklyMeeting? get meeting =>
      data.meetings.where((m) => m.conversationId == group.id).firstOrNull;
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.subtitle,
    this.highlight = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: highlight
            ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

String _capitalized(String s) => s[0].toUpperCase() + s.substring(1);

/// "Quinta, 01/10".
String _longDay(DateTime d) =>
    '${_capitalized(weekdayLong[d.weekday - 1])}, ${ddmm(d)}';

String _rangeText(TimeRange r) =>
    '${minutesLabel(r.start)} às ${minutesLabel(r.end)}';

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

// ---------------------------------------------------------------------------
// Encontro fixo

class _MeetingSection extends ConsumerWidget {
  const _MeetingSection({required this.ctx, required this.days});

  final _WeekContext ctx;
  final List<DayPlan> days;

  void _edit(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          MeetingSheet(conversation: ctx.group, existing: ctx.meeting),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meeting = ctx.meeting;
    if (meeting == null) {
      return _Section(
        title: 'Encontro fixo',
        subtitle: 'Um dia da semana para o grupo jogar junto.',
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.event_repeat),
            label: const Text('Marcar encontro fixo'),
            onPressed: () => _edit(context),
          ),
        ),
      );
    }

    final o = days
        .expand((d) => d.meetings)
        .where((m) => m.meeting.id == meeting.id)
        .first;
    final theme = Theme.of(context);
    final repo = ref.watch(repositoryProvider);
    final past = ctx.isPast(o.date);
    final editable = !past;

    Future<void> setException(MeetingException e) =>
        repo.setMeetingException(e);

    return _Section(
      title: 'Encontro fixo',
      subtitle:
          'Toda ${weekdayLong[meeting.weekday - 1]} às '
          '${minutesLabel(meeting.minute)}'
          '${meeting.game == null ? '' : ' · ${meeting.game}'}',
      highlight: editable && !o.skipped,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_longDay(o.date)} · ${minutesLabel(o.minute)}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: o.skipped ? theme.hintColor : null,
                    decoration: o.skipped ? TextDecoration.lineThrough : null,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _edit(context),
                child: const Text('Editar'),
              ),
            ],
          ),
          if (past)
            const Text('Já passou.')
          else if (o.skipped)
            _Notice(
              text: 'Pulado nesta semana.',
              action: 'Desfazer',
              onAction: () => repo.clearMeetingException(meeting.id, o.date),
            )
          else if (o.moved)
            _Notice(
              text:
                  'Só nesta semana: ${minutesLabel(o.minute)} '
                  '(o normal é ${minutesLabel(meeting.minute)}).',
              action: 'Voltar ao normal',
              onAction: () => repo.clearMeetingException(meeting.id, o.date),
            ),
          if (!o.skipped) ...[
            const SizedBox(height: 12),
            Text('Você vai?', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            RsvpChoice(occurrence: o, userId: ctx.userId, enabled: editable),
            const SizedBox(height: 12),
            for (final id in ctx.group.memberIds)
              if (id != ctx.userId)
                _RsvpLine(profile: repo.profile(id), rsvp: o.rsvps[id]),
          ],
          if (editable && !o.skipped) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_busy),
                  label: const Text('Pular esta semana'),
                  onPressed: () => setException(
                    MeetingException(
                      meetingId: meeting.id,
                      date: o.date,
                      skipped: true,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.schedule),
                  label: const Text('Mudar só esta semana'),
                  onPressed: () async {
                    final minute = await pickMinute(
                      context,
                      initial: o.minute,
                      help: 'Horário só de ${dayLabel(o.date)}',
                    );
                    if (minute == null) return;
                    await setException(
                      MeetingException(
                        meetingId: meeting.id,
                        date: o.date,
                        minute: minute,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Na hora do encontro o app vai chamar o grupo sozinho quando o '
            'servidor estiver ligado.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.text,
    required this.action,
    required this.onAction,
  });

  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.info_outline, size: 18, color: Theme.of(context).hintColor),
        const SizedBox(width: 6),
        Expanded(child: Text(text)),
        TextButton(onPressed: onAction, child: Text(action)),
      ],
    );
  }
}

class _RsvpLine extends StatelessWidget {
  const _RsvpLine({required this.profile, required this.rsvp});

  final Profile profile;
  final Rsvp? rsvp;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = switch (rsvp?.status) {
      RsvpStatus.going => ('✅', 'vai'),
      RsvpStatus.maybe => ('🤔', 'talvez'),
      RsvpStatus.notGoing => ('❌', 'não vai'),
      null => ('⏳', 'ainda não respondeu'),
    };
    final reason = rsvp?.reason;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Avatar(profile, radius: 12),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${profile.name}: $icon $label'
              '${reason == null ? '' : ' ($reason)'}',
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quando todo mundo está livre

class _FreeTimesSection extends ConsumerWidget {
  const _FreeTimesSection({required this.ctx, required this.days});

  final _WeekContext ctx;
  final List<DayPlan> days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final slots = [
      for (final d in days)
        if (!ctx.isPast(d.date))
          for (final r in d.everyoneFree)
            if (!_isOver(d.date, r)) (d.date, r),
    ];

    return _Section(
      title: 'Quando todo mundo está livre',
      subtitle: 'Cruzando os horários que cada um marcou.',
      child: slots.isEmpty
          ? const Text(
              'Nesta semana não há horário em que todos estejam livres. '
              'Marque os seus em "Seus horários" logo abaixo.',
            )
          : Column(
              children: [
                for (final (date, r) in slots)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.groups),
                    title: Text(
                      '${_longDay(date)}${ctx.isToday(date) ? ' (hoje)' : ''}',
                    ),
                    subtitle: Text(_rangeText(r)),
                    trailing: Tooltip(
                      message:
                          'Agendar Chamado ${dayLabel(date)} '
                          '${minutesLabel(r.start)}–${minutesLabel(r.end)}',
                      child: FilledButton.tonal(
                        onPressed: () => _schedule(context, ref, date, r),
                        child: const Text('Chamar'),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  /// A janela de hoje que já acabou não aparece.
  bool _isOver(DateTime date, TimeRange r) =>
      !date.add(Duration(minutes: r.end)).isAfter(ctx.now);

  /// Cria um Chamado agendado para o grupo dentro da janela escolhida.
  Future<void> _schedule(
    BuildContext context,
    WidgetRef ref,
    DateTime date,
    TimeRange range,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    var initial = range.start;
    if (ctx.isToday(date)) {
      // Hoje, sugere o próximo quarto de hora a partir de agora.
      final nowMinute = ctx.now.hour * 60 + ctx.now.minute;
      initial = math.max(initial, (nowMinute ~/ 15 + 1) * 15);
    }
    final minute = await pickMinute(
      context,
      initial: math.min(initial, range.end - 1),
      help: 'Chamar o grupo em ${dayLabel(date)} às…',
    );
    if (minute == null) return;
    final at = date.add(Duration(minutes: minute));
    if (!at.isAfter(ctx.now)) {
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
          conversationId: ctx.group.id,
          authorId: ctx.userId,
          targetIds: [
            for (final id in ctx.group.memberIds)
              if (id != ctx.userId) id,
          ],
          scheduledFor: at,
        );
    messenger.showSnackBar(
      SnackBar(
        content: Text('Chamado agendado: ${dayLabel(date)} às ${hhmm(at)}'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Seus horários

class _MyTimesSection extends StatelessWidget {
  const _MyTimesSection({required this.ctx});

  final _WeekContext ctx;

  @override
  Widget build(BuildContext context) {
    final byDay = <int, List<TimeRange>>{};
    for (final a in ctx.data.availability) {
      if (a.userId == ctx.userId) (byDay[a.weekday] ??= []).add(a.range);
    }
    final lines = [
      for (var d = 1; d <= 7; d++)
        if (byDay[d] case final ranges?)
          '${weekdayShort[d - 1]}: '
              '${mergeRanges(ranges).map(_rangeText).join(', ')}',
    ];

    return _Section(
      title: 'Seus horários',
      subtitle: 'Quando você costuma estar livre, toda semana.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (lines.isEmpty)
            const Text('Você ainda não marcou nenhum horário.')
          else
            for (final l in lines) Text(l),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_calendar),
            label: const Text('Editar meus horários'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AvailabilityScreen(userId: ctx.userId),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dia a dia

class _DaysSection extends ConsumerWidget {
  const _DaysSection({required this.ctx, required this.days});

  final _WeekContext ctx;
  final List<DayPlan> days;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(repositoryProvider);
    final theme = Theme.of(context);

    String summary(DayPlan d) {
      final parts = <String>[
        for (final m in d.meetings)
          m.skipped ? 'encontro pulado' : 'encontro ${minutesLabel(m.minute)}',
        for (final c in d.chamados) 'Chamado ${hhmm(c.scheduledFor!)}',
        if (d.everyoneFree.isNotEmpty)
          'todos livres ${d.everyoneFree.map(_rangeText).join(', ')}',
      ];
      return parts.isEmpty ? 'nada marcado' : parts.join(' · ');
    }

    return _Section(
      title: 'Dia a dia',
      subtitle: 'Toque num dia para ver o horário de cada um.',
      child: Column(
        children: [
          for (final d in days)
            Opacity(
              opacity: ctx.isPast(d.date) ? 0.5 : 1,
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                title: Text(
                  '${_longDay(d.date)}${ctx.isToday(d.date) ? ' · hoje' : ''}',
                  style: ctx.isToday(d.date)
                      ? TextStyle(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        )
                      : null,
                ),
                subtitle: Text(summary(d)),
                children: [
                  for (final c in d.chamados)
                    Row(
                      children: [
                        const Marca(size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Chamado às ${hhmm(c.scheduledFor!)} · '
                            '${chamadoGame(c)} (${c.authorId == ctx.userId ? 'você' : repo.profile(c.authorId).name} chamou)',
                          ),
                        ),
                      ],
                    ),
                  for (final entry in d.availability.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Avatar(repo.profile(entry.key), radius: 10),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${entry.key == ctx.userId ? 'Você' : repo.profile(entry.key).name}: '
                              '${entry.value.isEmpty ? 'não marcou horário livre' : 'livre ${entry.value.map(_rangeText).join(', ')}'}',
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
