-- Lembrete do encontro fixo: um aviso duas horas antes, para quem ainda não
-- confirmou presença.
--
-- Sem ele, confirmar presença só acontece se alguém abrir o app e olhar a
-- aba Semana — e o encontro chega com meio grupo sem responder. Quem avisa é
-- o mesmo cron do disparo (docs/CRON.md), que já acorda de minuto em minuto.
--
-- O lembrete não é um Chamado: não toca em tela cheia nem espera resposta
-- rápida. É um aviso comum, que leva a pessoa a dizer se vai.

-- Uma linha por ocorrência já avisada, como meeting_fires para o disparo: é
-- o que impede o cron, que roda a cada minuto, de lembrar quinze vezes.
create table public.meeting_reminders (
  meeting_id uuid not null references public.weekly_meetings (id) on delete cascade,
  date date not null,
  sent_at timestamptz not null default now(),
  primary key (meeting_id, date)
);

alter table public.meeting_reminders enable row level security;
create policy "vê os lembretes do encontro do grupo" on public.meeting_reminders
  for select using (can_see_meeting(meeting_id));

-- Com quanta antecedência o lembrete sai. A mesma do aviso dentro do app
-- (`meetingReminderAhead`, em lib/domain/calendar.dart).
create function public.antecedencia_do_lembrete() returns interval
language sql immutable as $$ select interval '2 hours' $$;

-- Os lembretes que venceram: a ocorrência do encontro e quem ainda não
-- confirmou presença nela.
--
-- A janela é a do disparo: lembrete atrasado não vale, porque avisar "duas
-- horas antes" vinte minutos tarde é só confundir. [p_agora] existe para os
-- testes poderem viajar no tempo.
create function public.lembretes_pendentes(p_agora timestamptz default now())
returns table (
  meeting_id uuid,
  conversation_id uuid,
  hora timestamptz,
  jogo text,
  alvos uuid[]
)
language plpgsql security definer set search_path = public as $$
declare
  encontro record;
  excecao public.meeting_exceptions;
  data_local date;
  minuto integer;
  comeco timestamptz;
  aviso timestamptz;
  faltam uuid[];
begin
  for encontro in
    select m.id, m.conversation_id, m.weekday, m.minute, m.game, g.timezone
    from weekly_meetings m
    join conversations c on c.id = m.conversation_id
    join groups g on g.id = c.group_id
  loop
    -- O dia a olhar é o do encontro que vem, não o de hoje: às 23h de quarta,
    -- o lembrete que vence é o do encontro de quinta à 0h30.
    data_local := (
      (p_agora + antecedencia_do_lembrete()) at time zone encontro.timezone
    )::date;
    if extract(isodow from data_local)::integer <> encontro.weekday then
      continue;
    end if;

    select * into excecao from meeting_exceptions e
    where e.meeting_id = encontro.id and e.date = data_local;
    if excecao.skipped then continue; end if;

    minuto := coalesce(excecao.minute, encontro.minute);
    comeco := (data_local + make_interval(mins => minuto))
      at time zone encontro.timezone;
    aviso := comeco - antecedencia_do_lembrete();
    if p_agora < aviso or p_agora >= aviso + janela_do_disparo() then
      continue;
    end if;
    if exists (
      select 1 from meeting_reminders r
      where r.meeting_id = encontro.id and r.date = data_local
    ) then continue; end if;

    select array_agg(cm.user_id) into faltam
    from conversation_members cm
    where cm.conversation_id = encontro.conversation_id
      and not exists (
        select 1 from meeting_rsvps r
        where r.meeting_id = encontro.id
          and r.date = data_local
          and r.user_id = cm.user_id
      );

    -- A ocorrência fica anotada mesmo quando não há ninguém a lembrar: ela
    -- foi resolvida, e o cron não precisa olhar de novo.
    insert into meeting_reminders (meeting_id, date)
    values (encontro.id, data_local);
    if faltam is null then continue; end if;

    meeting_id := encontro.id;
    conversation_id := encontro.conversation_id;
    hora := comeco;
    jogo := encontro.game;
    alvos := faltam;
    return next;
  end loop;
end
$$;

-- Só o servidor lembra: ninguém logado no app chama isso.
revoke execute on function public.lembretes_pendentes(timestamptz) from public;
grant execute on function public.lembretes_pendentes(timestamptz) to service_role;
