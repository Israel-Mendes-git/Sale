-- A soneca e a insistência: o Chamado tocando de novo.
--
-- Soneca: quem responde "me chama daqui a pouco" diz daqui a quanto, e na
-- hora o Chamado volta a esperar por ela — só por ela, ninguém mais é
-- incomodado.
-- Insistência: Chamado que ficou sem resposta toca uma segunda vez, só para
-- quem ficou calado.
--
-- Quem acorda os dois é o mesmo cron do encontro fixo (docs/CRON.md): é lá
-- que o relógio do grupo já bate, de minuto em minuto.

-- Quando chamar de novo quem pediu a soneca. Nulo = não pediu, ou já
-- acordou.
alter table public.chamado_targets add column snoozed_until timestamptz;

-- Quando o Chamado tocou de novo. Uma insistência por Chamado: o batsinal
-- repete uma vez, não fica apitando a noite toda.
alter table public.chamados add column nudged_at timestamptz;

-- "Me chama daqui a pouco" passa a perguntar daqui a quanto, do mesmo jeito
-- que "Tô jantando" pergunta em quanto tempo a pessoa chega.
alter table public.quick_replies drop column asks_eta;
alter table public.quick_replies add column asks_eta boolean
  generated always as (kind in ('later', 'snooze') and eta_minutes is null)
  stored;

-- Quanto tempo de silêncio antes de tocar de novo.
create function public.espera_da_insistencia() returns interval
language sql immutable as $$ select interval '5 minutes' $$;

-- Quando o Chamado tocou — é daqui que a insistência conta o silêncio.
--
-- Nulo quando ele nunca tocou: o marcado que ainda não venceu e o que
-- venceu tão atrasado que o cron deixou passar. Sem isso a insistência
-- acordaria o grupo justamente pelo Chamado que o cron poupou.
create function public.toque_do_chamado(c public.chamados) returns timestamptz
language sql immutable as $$
  select case
    -- O de agora e o do encontro fixo nascem tocando.
    when c.scheduled_for is null then coalesce(c.fired_at, c.created_at)
    -- O marcado para depois só tocou se foi liberado dentro da janela.
    when c.fired_at < c.scheduled_for + public.janela_do_disparo()
      then c.fired_at
  end
$$;

-- Responder marca a soneca de quem pediu e apaga a de quem mudou de ideia:
-- quem pede soneca e depois diz "bora" não pode ser chamado de novo.
create or replace function public.respond_chamado(
  p_chamado uuid,
  p_reply uuid,
  p_eta integer default null
) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  r quick_replies;
  st chamado_status;
begin
  if me is null then raise exception 'precisa estar logado'; end if;
  select status into st from chamados where id = p_chamado;
  if not exists (select 1 from chamado_targets where chamado_id = p_chamado and user_id = me) then
    raise exception 'você não foi chamado nesse Chamado';
  end if;
  if st <> 'open' then return; end if;
  select * into r from quick_replies
  where id = p_reply and (owner_id is null or owner_id = me);
  if r.id is null then raise exception 'resposta inválida'; end if;
  if p_eta is not null and p_eta not between 1 and 600 then
    raise exception 'tempo estimado inválido';
  end if;

  update chamado_targets
  set reply_emoji = r.emoji, reply_label = r.label, reply_kind = r.kind,
      reply_icon = r.icon,
      eta_minutes = coalesce(p_eta, r.eta_minutes), responded_at = now(),
      arrived_at = null,
      -- 15 minutos é o "daqui a pouco" de quem não escolheu.
      snoozed_until = case when r.kind = 'snooze' then
        now() + make_interval(mins => coalesce(p_eta, r.eta_minutes, 15))
      end
  where chamado_id = p_chamado and user_id = me;

  if not exists (
    select 1 from chamado_targets where chamado_id = p_chamado and responded_at is null
  ) then
    update chamados set status = 'answered' where id = p_chamado;
  end if;
end
$$;

-- O que venceu e precisa de push agora, com quem notificar em cada um.
--
-- Faz quatro coisas e devolve os Chamados a notificar: cria o Chamado do
-- encontro fixo que chegou a hora, libera os Chamados que estavam marcados
-- para depois, insiste com quem não respondeu e acorda quem pediu soneca.
--
-- [alvos] nulo = todo mundo que foi chamado; preenchido = só essas pessoas,
-- que é o caso da soneca e da insistência. [motivo] é o que o app escreve na
-- notificação. [p_agora] existe para os testes poderem viajar no tempo.
drop function public.disparar_pendentes(timestamptz);
create function public.disparar_pendentes(p_agora timestamptz default now())
returns table (chamado_id uuid, alvos uuid[], motivo text)
language plpgsql security definer set search_path = public as $$
declare
  encontro record;
  excecao public.meeting_exceptions;
  data_local date;
  minuto integer;
  hora timestamptz;
  novo uuid;
begin
  for encontro in
    select m.id, m.conversation_id, m.weekday, m.minute, m.game,
           g.timezone, g.created_by
    from weekly_meetings m
    join conversations c on c.id = m.conversation_id
    join groups g on g.id = c.group_id
  loop
    -- O dia e a hora são os do grupo; o servidor pode estar em qualquer fuso.
    data_local := (p_agora at time zone encontro.timezone)::date;
    if extract(isodow from data_local)::integer <> encontro.weekday then
      continue;
    end if;

    select * into excecao from meeting_exceptions e
    where e.meeting_id = encontro.id and e.date = data_local;
    if excecao.skipped then continue; end if;

    minuto := coalesce(excecao.minute, encontro.minute);
    hora := (data_local + make_interval(mins => minuto)) at time zone encontro.timezone;
    if p_agora < hora or p_agora >= hora + janela_do_disparo() then continue; end if;
    if exists (
      select 1 from meeting_fires f
      where f.meeting_id = encontro.id and f.date = data_local
    ) then continue; end if;

    insert into chamados (conversation_id, author_id, game_name, automatic, fired_at)
    values (encontro.conversation_id, encontro.created_by, encontro.game, true, p_agora)
    returning id into novo;

    -- No automático todo mundo é chamado, inclusive quem criou o grupo:
    -- não há uma pessoa chamando as outras.
    insert into chamado_targets (chamado_id, user_id)
    select novo, cm.user_id
    from conversation_members cm
    where cm.conversation_id = encontro.conversation_id;

    insert into messages (conversation_id, author_id, chamado_id)
    values (encontro.conversation_id, encontro.created_by, novo);

    insert into meeting_fires (meeting_id, date, chamado_id)
    values (encontro.id, data_local, novo);

    chamado_id := novo;
    alvos := null;
    motivo := 'encontro';
    return next;
  end loop;

  -- Marca todos os que já venceram, mas só manda push nos recentes: o que
  -- passou da janela fica marcado para não voltar na próxima rodada.
  return query
  with liberados as (
    update chamados set fired_at = p_agora
    where scheduled_for is not null
      and fired_at is null
      and status = 'open'
      and scheduled_for <= p_agora
    returning id, scheduled_for
  )
  select id, null::uuid[], 'marcado'::text
  from liberados
  where scheduled_for > p_agora - janela_do_disparo();

  -- A insistência vem antes da soneca de propósito: quem pediu soneca já
  -- respondeu, e assim não leva os dois pushes no mesmo minuto.
  return query
  with insistidos as (
    update chamados c set nudged_at = p_agora
    where c.status = 'open'
      and c.nudged_at is null
      -- Venceu a espera e ainda está dentro da janela. O limite de baixo é
      -- aberto, igual ao do app (`fireWindow`, em lib/domain/models.dart).
      and toque_do_chamado(c) <= p_agora - espera_da_insistencia()
      and toque_do_chamado(c) >
          p_agora - espera_da_insistencia() - janela_do_disparo()
      and exists (
        select 1 from chamado_targets t
        where t.chamado_id = c.id and t.responded_at is null
      )
    returning c.id
  )
  select i.id,
         (select array_agg(t.user_id) from chamado_targets t
          where t.chamado_id = i.id and t.responded_at is null),
         'insistencia'::text
  from insistidos i;

  -- Soneca que não vai mais acordar ninguém: o Chamado foi encerrado, ou ela
  -- venceu tão atrasada que a hora de jogar já passou. Cai sem tocar, e a
  -- resposta 💤 fica no card do mesmo jeito.
  update chamado_targets t set snoozed_until = null
  where t.snoozed_until is not null
    and (t.snoozed_until <= p_agora - janela_do_disparo()
         or exists (
           select 1 from chamados c
           where c.id = t.chamado_id and c.status = 'closed'
         ));

  -- A soneca na hora: a resposta cai e a pessoa volta para a fila de quem
  -- não respondeu, que é o que faz o Chamado tocar de novo só para ela.
  return query
  with acordadas as (
    update chamado_targets t
    set snoozed_until = null, responded_at = null, eta_minutes = null,
        reply_emoji = null, reply_label = null, reply_kind = null,
        reply_icon = null
    where t.snoozed_until <= p_agora
    returning t.chamado_id, t.user_id
  ),
  reabertos as (
    -- O Chamado tinha todas as respostas; agora espera de novo por uma.
    update chamados set status = 'open'
    where status = 'answered'
      and id in (select a.chamado_id from acordadas a)
  )
  select a.chamado_id, array_agg(a.user_id), 'soneca'::text
  from acordadas a
  group by a.chamado_id;
end
$$;

-- Só o servidor dispara: ninguém logado no app chama isso.
revoke execute on function public.disparar_pendentes(timestamptz) from public;
grant execute on function public.disparar_pendentes(timestamptz) to service_role;
