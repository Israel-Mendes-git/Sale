-- Disparo automático: o encontro fixo e o Chamado marcado para depois
-- tocando sozinhos, sem ninguém com o app aberto.
--
-- Quem acorda é um cron (ver docs/CRON.md), que chama a Edge Function
-- disparar-agendados a cada minuto; ela pede a esta função a lista do que
-- venceu e manda os pushes. A regra de quando disparar mora aqui, no banco,
-- junto das outras.

-- O horário do encontro ("quinta, 21h") é do grupo, não do servidor: sem
-- saber o fuso, o Chamado sairia três horas fora.
alter table public.groups
  add column timezone text not null default 'America/Sao_Paulo';

-- Chamado que nasceu do encontro fixo não tem uma pessoa por trás: o card
-- mostra "Encontro fixo" no lugar de "Fulano chamou".
alter table public.chamados add column automatic boolean not null default false;

-- Quando o push saiu. Só o Chamado marcado para depois usa: o de agora é
-- notificado pelo webhook, no mesmo instante em que nasce.
alter table public.chamados add column fired_at timestamptz;

-- Uma linha por ocorrência já disparada. É o que impede o cron, que roda a
-- cada minuto, de chamar o grupo sessenta vezes na mesma hora.
create table public.meeting_fires (
  meeting_id uuid not null references public.weekly_meetings (id) on delete cascade,
  date date not null,
  chamado_id uuid not null references public.chamados (id) on delete cascade,
  fired_at timestamptz not null default now(),
  primary key (meeting_id, date)
);

alter table public.meeting_fires enable row level security;
create policy "vê os disparos do encontro do grupo" on public.meeting_fires
  for select using (can_see_meeting(meeting_id));

-- Depois de quanto tempo um disparo atrasado deixa de valer. Servidor que
-- ficou fora do ar não acorda o grupo uma hora depois da janta.
create function public.janela_do_disparo() returns interval
language sql immutable as $$ select interval '15 minutes' $$;

-- O que venceu e precisa de push agora.
--
-- Faz duas coisas e devolve os Chamados a notificar: cria o Chamado do
-- encontro fixo que chegou a hora e libera os Chamados que estavam marcados
-- para depois. [p_agora] existe para os testes poderem viajar no tempo.
create function public.disparar_pendentes(p_agora timestamptz default now())
returns table (chamado_id uuid)
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
  select id from liberados
  where scheduled_for > p_agora - janela_do_disparo();
end
$$;

-- Só o servidor dispara: ninguém logado no app chama isso.
revoke execute on function public.disparar_pendentes(timestamptz) from public;
grant execute on function public.disparar_pendentes(timestamptz) to service_role;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.meeting_fires;
  end if;
end
$$;
