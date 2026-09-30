import 'package:flutter_test/flutter_test.dart';
import 'package:sale/data/memory_repository.dart';
import 'package:sale/domain/calendar.dart';
import 'package:sale/domain/models.dart';

TimeRange h(num start, num end) =>
    TimeRange((start * 60).round(), (end * 60).round());

Availability av(String user, int weekday, TimeRange r) => Availability(
  id: '$user-$weekday-${r.start}',
  userId: user,
  weekday: weekday,
  range: r,
);

CalendarData data({
  List<WeeklyMeeting> meetings = const [],
  List<MeetingException> exceptions = const [],
  List<Rsvp> rsvps = const [],
  List<Availability> availability = const [],
  List<Chamado> chamados = const [],
}) => CalendarData(
  meetings: meetings,
  exceptions: exceptions,
  rsvps: rsvps,
  availability: availability,
  scheduledChamados: chamados,
);

void main() {
  // Segunda, 28/09/2026: a semana atravessa a virada de mês.
  final monday = DateTime(2026, 9, 28);
  final thursday = DateTime(2026, 10, 1);
  const members = ['israel', 'beto', 'caio'];

  group('datas', () {
    test('a semana começa na segunda, inclusive a partir do domingo', () {
      expect(weekStart(DateTime(2026, 10, 4, 23, 59)), monday);
      expect(weekStart(DateTime(2026, 9, 28, 0, 1)), monday);
      expect(weekStart(DateTime(2026, 10, 1, 12)), monday);
    });
  });

  group('faixas', () {
    test('une faixas sobrepostas e encostadas, fora de ordem', () {
      expect(mergeRanges([h(21, 23), h(19, 20), h(20, 21), h(22, 24)]), [
        h(19, 24),
      ]);
      expect(mergeRanges([h(14, 15), h(16, 17)]), [h(14, 15), h(16, 17)]);
    });

    test('todos livres = interseção de todo mundo', () {
      // Quinta dos dados de exemplo.
      expect(
        intersectAll([
          [h(19, 24)],
          [h(21, 24)],
          [h(20, 23)],
        ]),
        [h(21, 23)],
      );
      // Sábado: o Beto tem um buraco das 20h às 21h.
      expect(
        intersectAll([
          [h(14, 24)],
          [h(16, 20), h(21, 24)],
          [h(15, 22)],
        ]),
        [h(16, 20), h(21, 22)],
      );
    });

    test('quem não marcou nada zera o "todos livres"', () {
      expect(
        intersectAll([
          [h(19, 24)],
          [],
        ]),
        isEmpty,
      );
      expect(intersectAll([]), isEmpty);
    });

    test('faixa inválida é recusada', () {
      expect(() => TimeRange(600, 600), throwsA(isA<AssertionError>()));
      expect(
        () => TimeRange(0, minutesPerDay + 1),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('planWeek', () {
    const meeting = WeeklyMeeting(
      id: 'm',
      conversationId: 'grupo',
      weekday: 4,
      minute: 21 * 60,
    );

    test('monta os 7 dias e põe o encontro na quinta', () {
      final days = planWeek(
        data(meetings: [meeting]),
        monday: monday,
        memberIds: members,
      );
      expect(days.map((d) => d.date.day), [28, 29, 30, 1, 2, 3, 4]);
      expect(days[3].meetings.single.startsAt, DateTime(2026, 10, 1, 21));
      expect(days.where((d) => d.meetings.isNotEmpty), hasLength(1));
    });

    test('exceção pula ou muda o horário só daquela data', () {
      final skipped = planWeek(
        data(
          meetings: [meeting],
          exceptions: [
            MeetingException(meetingId: 'm', date: thursday, skipped: true),
          ],
        ),
        monday: monday,
        memberIds: members,
      )[3].meetings.single;
      expect(skipped.skipped, isTrue);

      final moved = planWeek(
        data(
          meetings: [meeting],
          exceptions: [
            MeetingException(meetingId: 'm', date: thursday, minute: 22 * 60),
          ],
        ),
        monday: monday,
        memberIds: members,
      )[3].meetings.single;
      expect(moved.minute, 22 * 60);
      expect(moved.moved, isTrue);

      // A exceção de uma semana não vaza para a seguinte.
      final nextWeek = planWeek(
        data(
          meetings: [meeting],
          exceptions: [
            MeetingException(meetingId: 'm', date: thursday, skipped: true),
          ],
        ),
        monday: DateTime(2026, 10, 5),
        memberIds: members,
      )[3].meetings.single;
      expect(nextWeek.skipped, isFalse);
    });

    test('confirmações contam só na data delas', () {
      final day = planWeek(
        data(
          meetings: [meeting],
          rsvps: [
            Rsvp(
              meetingId: 'm',
              date: thursday,
              userId: 'beto',
              status: RsvpStatus.maybe,
            ),
            Rsvp(
              meetingId: 'm',
              date: DateTime(2026, 9, 24),
              userId: 'caio',
              status: RsvpStatus.notGoing,
            ),
          ],
        ),
        monday: monday,
        memberIds: members,
      )[3];
      expect(day.meetings.single.rsvps.keys, ['beto']);
    });

    test('Chamado agendado cai no dia dele, em ordem de horário', () {
      Chamado at(String id, DateTime t) => Chamado(
        id: id,
        conversationId: 'grupo',
        authorId: 'israel',
        createdAt: monday,
        scheduledFor: t,
        responses: const {'beto': null},
      );
      final days = planWeek(
        data(
          chamados: [
            at('b', DateTime(2026, 10, 3, 22)),
            at('a', DateTime(2026, 10, 3, 15)),
          ],
        ),
        monday: monday,
        memberIds: members,
      );
      expect(days[5].chamados.map((c) => c.id), ['a', 'b']);
      expect(days.where((d) => d.chamados.isNotEmpty), hasLength(1));
    });

    test('disponibilidade é por membro e "todos livres" usa só os membros', () {
      final day = planWeek(
        data(
          availability: [
            av('israel', 4, h(19, 24)),
            av('beto', 4, h(21, 24)),
            av('caio', 4, h(20, 23)),
            av('estranho', 4, h(0, 1)),
          ],
        ),
        monday: monday,
        memberIds: members,
      )[3];
      expect(day.availability.keys, members);
      expect(day.everyoneFree, [h(21, 23)]);
    });
  });

  group('repositório', () {
    late MemoryRepository repo;
    setUp(
      () => repo = MemoryRepository(clock: () => DateTime(2026, 9, 28, 10)),
    );

    test('encontro fixo é um por grupo: salvar de novo substitui', () async {
      final before = (await repo.watchCalendar('israel').first).meetings.single;
      await repo.saveMeeting(
        conversationId: 'grupo',
        weekday: 4,
        minute: 22 * 60,
      );
      final after = (await repo.watchCalendar('israel').first).meetings.single;
      expect(after.id, before.id);
      expect(after.minute, 22 * 60);
    });

    test(
      'mudar o dia do encontro descarta exceções e confirmações antigas',
      () async {
        await repo.setRsvp(
          Rsvp(
            meetingId: 'encontro-grupo',
            date: thursday,
            userId: 'beto',
            status: RsvpStatus.going,
          ),
        );
        await repo.setMeetingException(
          MeetingException(
            meetingId: 'encontro-grupo',
            date: thursday,
            skipped: true,
          ),
        );

        // Mesmo dia, outro horário: mantém.
        await repo.saveMeeting(
          conversationId: 'grupo',
          weekday: 4,
          minute: 20 * 60,
        );
        var cal = await repo.watchCalendar('israel').first;
        expect(cal.rsvps, hasLength(1));
        expect(cal.exceptions, hasLength(1));

        // Outro dia: descarta.
        await repo.saveMeeting(
          conversationId: 'grupo',
          weekday: 5,
          minute: 20 * 60,
        );
        cal = await repo.watchCalendar('israel').first;
        expect(cal.rsvps, isEmpty);
        expect(cal.exceptions, isEmpty);
      },
    );

    test('confirmar de novo substitui a resposta anterior', () async {
      for (final s in [RsvpStatus.going, RsvpStatus.notGoing]) {
        await repo.setRsvp(
          Rsvp(
            meetingId: 'encontro-grupo',
            date: thursday,
            userId: 'beto',
            status: s,
          ),
        );
      }
      final cal = await repo.watchCalendar('israel').first;
      expect(cal.rsvps.single.status, RsvpStatus.notGoing);
    });

    test('disponibilidade: adiciona, remove e recusa dia inválido', () async {
      await repo.addAvailability(userId: 'caio', weekday: 1, range: h(20, 22));
      var mine = (await repo.watchCalendar('caio').first).availability.where(
        (a) => a.userId == 'caio' && a.weekday == 1,
      );
      expect(mine.single.range, h(20, 22));

      await repo.removeAvailability(mine.single.id);
      mine = (await repo.watchCalendar('caio').first).availability.where(
        (a) => a.userId == 'caio' && a.weekday == 1,
      );
      expect(mine, isEmpty);

      expect(
        () => repo.addAvailability(userId: 'caio', weekday: 8, range: h(1, 2)),
        throwsArgumentError,
      );
    });

    test(
      'calendário só mostra Chamados agendados abertos de quem participa',
      () async {
        final agendado = await repo.sendChamado(
          conversationId: 'israel-beto',
          authorId: 'israel',
          targetIds: ['beto'],
          scheduledFor: DateTime(2026, 10, 1, 21),
        );
        await repo.sendChamado(
          conversationId: 'israel-beto',
          authorId: 'israel',
          targetIds: ['beto'],
        );

        expect(
          (await repo.watchCalendar('beto').first).scheduledChamados.single.id,
          agendado.id,
        );
        expect(
          (await repo.watchCalendar('caio').first).scheduledChamados,
          isEmpty,
        );

        await repo.closeChamado(agendado.id);
        expect(
          (await repo.watchCalendar('beto').first).scheduledChamados,
          isEmpty,
        );
      },
    );
  });
}
