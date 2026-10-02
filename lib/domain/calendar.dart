import 'package:flutter/foundation.dart';

import 'models.dart';

const minutesPerDay = 24 * 60;

/// Faixa de horário dentro de um dia, em minutos desde a meia-noite:
/// [start] incluso, [end] excluso. Não atravessa a meia-noite.
@immutable
class TimeRange {
  const TimeRange(this.start, this.end)
    : assert(start >= 0 && end <= minutesPerDay && start < end);

  final int start;
  final int end;

  int get length => end - start;

  TimeRange? intersect(TimeRange other) {
    final s = start > other.start ? start : other.start;
    final e = end < other.end ? end : other.end;
    return s < e ? TimeRange(s, e) : null;
  }

  @override
  bool operator ==(Object other) =>
      other is TimeRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TimeRange($start, $end)';
}

/// Faixa em que a pessoa costuma estar livre, repetida toda semana.
@immutable
class Availability {
  const Availability({
    required this.id,
    required this.userId,
    required this.weekday,
    required this.range,
  });

  final String id;
  final String userId;

  /// 1 = segunda … 7 = domingo, como em [DateTime.weekday].
  final int weekday;
  final TimeRange range;
}

/// Encontro fixo semanal de um grupo.
@immutable
class WeeklyMeeting {
  const WeeklyMeeting({
    required this.id,
    required this.conversationId,
    required this.weekday,
    required this.minute,
    this.game,
  });

  final String id;
  final String conversationId;
  final int weekday;

  /// Horário em minutos desde a meia-noite.
  final int minute;
  final String? game;
}

/// Mudança de um encontro só numa data: pular ou trocar o horário.
@immutable
class MeetingException {
  const MeetingException({
    required this.meetingId,
    required this.date,
    this.skipped = false,
    this.minute,
  });

  final String meetingId;
  final DateTime date;
  final bool skipped;

  /// Horário só desta data; nulo = o de sempre.
  final int? minute;
}

enum RsvpStatus { going, maybe, notGoing }

@immutable
class Rsvp {
  const Rsvp({
    required this.meetingId,
    required this.date,
    required this.userId,
    required this.status,
    this.reason,
  });

  final String meetingId;
  final DateTime date;
  final String userId;
  final RsvpStatus status;
  final String? reason;
}

/// Tudo o que o calendário precisa, lido de uma vez do repositório.
@immutable
class CalendarData {
  const CalendarData({
    required this.meetings,
    required this.exceptions,
    required this.rsvps,
    required this.availability,
    required this.scheduledChamados,
  });

  final List<WeeklyMeeting> meetings;
  final List<MeetingException> exceptions;
  final List<Rsvp> rsvps;
  final List<Availability> availability;
  final List<Chamado> scheduledChamados;
}

/// Uma ocorrência do encontro fixo numa data.
@immutable
class MeetingOccurrence {
  const MeetingOccurrence({
    required this.meeting,
    required this.date,
    required this.minute,
    required this.skipped,
    required this.moved,
    required this.rsvps,
  });

  final WeeklyMeeting meeting;
  final DateTime date;
  final int minute;
  final bool skipped;

  /// Horário diferente do de sempre só nesta data.
  final bool moved;
  final Map<String, Rsvp> rsvps;

  DateTime get startsAt => date.add(Duration(minutes: minute));
}

@immutable
class DayPlan {
  const DayPlan({
    required this.date,
    required this.meetings,
    required this.chamados,
    required this.availability,
    required this.everyoneFree,
  });

  final DateTime date;
  final List<MeetingOccurrence> meetings;
  final List<Chamado> chamados;

  /// Faixas livres de cada membro neste dia, já ordenadas e unidas.
  final Map<String, List<TimeRange>> availability;

  /// Faixas em que todos os membros estão livres.
  final List<TimeRange> everyoneFree;

  bool get isEmpty =>
      meetings.isEmpty && chamados.isEmpty && everyoneFree.isEmpty;
}

/// Quanto tempo depois da hora um encontro fixo ainda vira Chamado. A mesma
/// janela vale no servidor (`janela_do_disparo`, no banco): encontro muito
/// atrasado não acorda mais ninguém.
const meetingFireWindow = Duration(minutes: 15);

DateTime dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);

/// Segunda-feira da semana de [t].
DateTime weekStart(DateTime t) =>
    DateTime(t.year, t.month, t.day - (t.weekday - 1));

bool sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Ordena e une faixas que se tocam ou se sobrepõem.
List<TimeRange> mergeRanges(Iterable<TimeRange> ranges) {
  final sorted = ranges.toList()..sort((a, b) => a.start.compareTo(b.start));
  final merged = <TimeRange>[];
  for (final r in sorted) {
    if (merged.isNotEmpty && r.start <= merged.last.end) {
      final last = merged.removeLast();
      merged.add(TimeRange(last.start, r.end > last.end ? r.end : last.end));
    } else {
      merged.add(r);
    }
  }
  return merged;
}

/// Interseção de listas de faixas (cada lista já unida por [mergeRanges]).
List<TimeRange> intersectAll(List<List<TimeRange>> lists) {
  if (lists.isEmpty) return const [];
  var acc = lists.first;
  for (final next in lists.skip(1)) {
    final out = <TimeRange>[];
    for (final a in acc) {
      for (final b in next) {
        final i = a.intersect(b);
        if (i != null) out.add(i);
      }
    }
    acc = mergeRanges(out);
  }
  return acc;
}

/// Monta os 7 dias da semana que começa em [monday] para as pessoas em
/// [memberIds] (normalmente os membros do grupo do encontro fixo).
List<DayPlan> planWeek(
  CalendarData data, {
  required DateTime monday,
  required List<String> memberIds,
}) {
  return [
    for (var i = 0; i < 7; i++)
      _planDay(
        data,
        DateTime(monday.year, monday.month, monday.day + i),
        memberIds,
      ),
  ];
}

DayPlan _planDay(CalendarData data, DateTime date, List<String> memberIds) {
  final meetings = <MeetingOccurrence>[];
  for (final m in data.meetings.where((m) => m.weekday == date.weekday)) {
    final ex = data.exceptions
        .where((e) => e.meetingId == m.id && sameDate(e.date, date))
        .firstOrNull;
    final minute = ex?.minute ?? m.minute;
    meetings.add(
      MeetingOccurrence(
        meeting: m,
        date: date,
        minute: minute,
        skipped: ex?.skipped ?? false,
        moved: minute != m.minute,
        rsvps: {
          for (final r in data.rsvps)
            if (r.meetingId == m.id && sameDate(r.date, date)) r.userId: r,
        },
      ),
    );
  }
  meetings.sort((a, b) => a.minute.compareTo(b.minute));

  final chamados = [
    for (final c in data.scheduledChamados)
      if (c.scheduledFor != null && sameDate(c.scheduledFor!, date)) c,
  ]..sort((a, b) => a.scheduledFor!.compareTo(b.scheduledFor!));

  final availability = {
    for (final id in memberIds)
      id: mergeRanges([
        for (final a in data.availability)
          if (a.userId == id && a.weekday == date.weekday) a.range,
      ]),
  };

  return DayPlan(
    date: date,
    meetings: meetings,
    chamados: chamados,
    availability: availability,
    everyoneFree: intersectAll(availability.values.toList()),
  );
}
