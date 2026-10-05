-- A do dia: o grupo elege a frase, o momento ou o áudio do dia.
--
-- Qualquer um do grupo indica uma mensagem do dia (texto, imagem ou recado de
-- voz) e cada um tem um voto por dia, que pode trocar até a votação fechar.
-- Quem fecha é o cron (docs/CRON.md): a mais votada vira a do dia — empate vai
-- para a de mais reações, e depois para a indicada primeiro — e todas ficam
-- no Hall das do dia.
--
-- O "dia" vira às 6h da manhã no fuso do grupo, não à meia-noite: o momento
-- das 23h50 ainda é de hoje para quem está jogando de madrugada.
--
-- Vale só para a conversa do grupo. Indicar e votar passam pelas ações do
-- banco; as tabelas só se leem.

-- O dia da disputa de um instante, no relógio do grupo da conversa.
create function public.dia_do_destaque(p_conversa uuid, p_quando timestamptz)
returns date
language sql stable security definer set search_path = public as $$
  select ((p_quando at time zone g.timezone) - interval '6 hours')::date
  from conversations c join groups g on g.id = c.group_id
  where c.id = p_conversa
$$;

create table public.destaque_indicacoes (
  message_id uuid primary key references public.messages (id) on delete cascade,
  conversation_id uuid not null
    references public.conversations (id) on delete cascade,
  dia date not null,
  indicada_por uuid not null references public.profiles (id),
  indicada_em timestamptz not null default now()
);

create index destaque_indicacoes_por_dia
  on public.destaque_indicacoes (conversation_id, dia);

-- Um voto por pessoa por dia; votar de novo troca o voto.
create table public.destaque_votos (
  conversation_id uuid not null
    references public.conversations (id) on delete cascade,
  dia date not null,
  user_id uuid not null references public.profiles (id) on delete cascade,
  message_id uuid not null
    references public.destaque_indicacoes (message_id) on delete cascade,
  votado_em timestamptz not null default now(),
  primary key (conversation_id, dia, user_id)
);

-- A vencedora de cada dia. A mensagem pode ser apagada depois; o dia fica.
create table public.destaques (
  conversation_id uuid not null
    references public.conversations (id) on delete cascade,
  dia date not null,
  message_id uuid references public.messages (id) on delete set null,
  votos integer not null default 0,
  escolhido_em timestamptz not null default now(),
  primary key (conversation_id, dia)
);

alter table public.destaque_indicacoes enable row level security;
alter table public.destaque_votos enable row level security;
alter table public.destaques enable row level security;

create policy "vê as indicações da conversa" on public.destaque_indicacoes
  for select using (is_conversation_member(conversation_id));
create policy "vê os votos da conversa" on public.destaque_votos
  for select using (is_conversation_member(conversation_id));
create policy "vê as do dia da conversa" on public.destaques
  for select using (is_conversation_member(conversation_id));

-- Indica uma mensagem de hoje para a do dia.
create function public.indicar_destaque(p_message uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  m messages;
  hoje date;
begin
  if me is null then raise exception 'precisa estar logado'; end if;
  select * into m from messages where id = p_message;
  if m.id is null or m.deleted_at is not null or m.chamado_id is not null then
    raise exception 'essa mensagem não pode ser a do dia';
  end if;
  if not is_conversation_member(m.conversation_id) then
    raise exception 'você não está nessa conversa';
  end if;
  if not exists (
    select 1 from conversations
    where id = m.conversation_id and kind = 'group'
  ) then
    raise exception 'a do dia é da conversa do grupo';
  end if;
  hoje := dia_do_destaque(m.conversation_id, now());
  if dia_do_destaque(m.conversation_id, m.created_at) <> hoje then
    raise exception 'só dá para indicar o que foi de hoje';
  end if;
  insert into destaque_indicacoes (message_id, conversation_id, dia, indicada_por)
  values (p_message, m.conversation_id, hoje, me)
  on conflict (message_id) do nothing;
end
$$;

-- Vota numa indicada de hoje; votar de novo troca o voto.
create function public.votar_destaque(p_message uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  i destaque_indicacoes;
begin
  if me is null then raise exception 'precisa estar logado'; end if;
  select * into i from destaque_indicacoes where message_id = p_message;
  if i.message_id is null then
    raise exception 'essa mensagem não foi indicada';
  end if;
  if not is_conversation_member(i.conversation_id) then
    raise exception 'você não está nessa conversa';
  end if;
  if i.dia <> dia_do_destaque(i.conversation_id, now()) then
    raise exception 'a votação desse dia já fechou';
  end if;
  insert into destaque_votos (conversation_id, dia, user_id, message_id)
  values (i.conversation_id, i.dia, me, p_message)
  on conflict (conversation_id, dia, user_id)
  do update set message_id = excluded.message_id, votado_em = now();
end
$$;

-- Fecha os dias que já viraram e devolve as vencedoras, para o push.
-- [p_agora] existe para os testes poderem viajar no tempo.
create function public.fechar_destaques(p_agora timestamptz default now())
returns table (conversation_id uuid, dia date, message_id uuid, votos integer)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
begin
  return query
  with abertos as (
    select distinct i.conversation_id as conversa, i.dia as dia_aberto
    from destaque_indicacoes i
    where i.dia < dia_do_destaque(i.conversation_id, p_agora)
      and not exists (
        select 1 from destaques d
        where d.conversation_id = i.conversation_id and d.dia = i.dia
      )
  ),
  placar as (
    select i.conversation_id as conversa, i.dia as dia_disputa,
           i.message_id as mensagem, i.indicada_em,
           (select count(*) from destaque_votos v
            where v.message_id = i.message_id)::integer as total_votos,
           (select count(*) from message_reactions r
            where r.message_id = i.message_id)::integer as total_reacoes
    from destaque_indicacoes i
    join abertos a on a.conversa = i.conversation_id and a.dia_aberto = i.dia
    join messages m on m.id = i.message_id and m.deleted_at is null
  ),
  vencedoras as (
    select distinct on (p.conversa, p.dia_disputa) p.*
    from placar p
    order by p.conversa, p.dia_disputa, p.total_votos desc,
             p.total_reacoes desc, p.indicada_em asc
  ),
  gravadas as (
    insert into destaques (conversation_id, dia, message_id, votos)
    select v.conversa, v.dia_disputa, v.mensagem, v.total_votos
    from vencedoras v
    on conflict do nothing
    returning destaques.conversation_id, destaques.dia,
              destaques.message_id, destaques.votos
  )
  select g.conversation_id, g.dia, g.message_id, g.votos from gravadas g;
end
$$;

revoke execute on function
  public.indicar_destaque(uuid), public.votar_destaque(uuid) from public;
grant execute on function
  public.indicar_destaque(uuid), public.votar_destaque(uuid) to authenticated;
-- No Supabase toda função nova vem com execute para anon e authenticated;
-- tirar só do public não basta.
revoke execute on function public.fechar_destaques(timestamptz)
  from public, anon, authenticated;
grant execute on function public.fechar_destaques(timestamptz) to service_role;

-- Tempo real: indicar e votar aparecem na hora para quem está na conversa.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.destaque_indicacoes;
    alter publication supabase_realtime add table public.destaque_votos;
    alter publication supabase_realtime add table public.destaques;
  end if;
end
$$;
