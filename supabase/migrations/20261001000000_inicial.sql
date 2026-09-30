-- Esquema inicial do Sale?
--
-- Leitura e escrita simples passam pelas regras de acesso (RLS). Mudanças de
-- estado com regra de negócio (disparar Chamado, responder, vetar, entrar em
-- grupo) passam por funções "security definer", para ninguém responder por
-- outra pessoa nem escolher o resultado do sorteio.

-- ---------------------------------------------------------------------------
-- Tipos

create type public.conversation_kind as enum ('direct', 'group');
create type public.reply_kind as enum ('yes', 'later', 'no', 'snooze');
create type public.chamado_status as enum ('open', 'answered', 'closed');
create type public.rsvp_status as enum ('going', 'maybe', 'not_going');

-- ---------------------------------------------------------------------------
-- Pessoas e grupos

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 24),
  -- A pessoa confirmou o nome (o que vem do Discord/Google é só sugestão).
  named boolean not null default false,
  emoji text not null default '🎮',
  color integer not null default -16121,
  created_at timestamptz not null default now()
);

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(btrim(name)) between 1 and 40),
  invite_code text not null unique
    default upper(substr(md5(gen_random_uuid()::text), 1, 8)),
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now()
);

create table public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Conversas

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  kind public.conversation_kind not null,
  name text,
  created_at timestamptz not null default now()
);

create table public.conversation_members (
  conversation_id uuid not null
    references public.conversations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  primary key (conversation_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Respostas rápidas

create table public.quick_replies (
  id uuid primary key default gen_random_uuid(),
  -- Nulo = comum a todos.
  owner_id uuid references public.profiles (id) on delete cascade,
  emoji text not null check (char_length(emoji) between 1 and 16),
  label text not null check (char_length(btrim(label)) between 1 and 40),
  kind public.reply_kind not null,
  -- Tempo embutido ("Chego em 10 min").
  eta_minutes integer check (eta_minutes between 1 and 600),
  -- "Vou, mas depois" sem tempo embutido pergunta quanto tempo.
  asks_eta boolean generated always as (kind = 'later' and eta_minutes is null)
    stored,
  created_at timestamptz not null default now()
);

insert into public.quick_replies (emoji, label, kind, eta_minutes) values
  ('✅', 'Bora!', 'yes', null),
  ('⏱️', 'Chego em 10 min', 'later', 10),
  ('⏱️', 'Chego em 20 min', 'later', 20),
  ('⏱️', 'Chego em 30 min', 'later', 30),
  ('❌', 'Hoje não', 'no', null),
  ('💤', 'Me chama daqui a pouco', 'snooze', null);

-- ---------------------------------------------------------------------------
-- Jogos

create table public.games (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 40),
  min_players integer not null check (min_players >= 1),
  max_players integer not null check (max_players <= 32),
  created_by uuid not null default auth.uid() references public.profiles (id),
  created_at timestamptz not null default now(),
  check (min_players <= max_players)
);

create unique index games_nome_unico on public.games (group_id, lower(btrim(name)));

create table public.game_owners (
  game_id uuid not null references public.games (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  primary key (game_id, user_id)
);

-- ---------------------------------------------------------------------------
-- Chamados

create table public.chamados (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null
    references public.conversations (id) on delete cascade,
  author_id uuid not null references public.profiles (id),
  game_id uuid references public.games (id) on delete set null,
  -- Nome guardado: o card continua legível se o jogo sair da biblioteca.
  game_name text,
  drawn boolean not null default false,
  note text check (char_length(note) <= 200),
  scheduled_for timestamptz,
  status public.chamado_status not null default 'open',
  created_at timestamptz not null default now()
);

create table public.chamado_targets (
  chamado_id uuid not null references public.chamados (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  -- Cópia da resposta: sobrevive se a pessoa apagar a resposta depois.
  reply_emoji text,
  reply_label text,
  reply_kind public.reply_kind,
  eta_minutes integer,
  responded_at timestamptz,
  primary key (chamado_id, user_id)
);

create table public.chamado_vetoes (
  chamado_id uuid not null references public.chamados (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  game_id uuid references public.games (id) on delete set null,
  primary key (chamado_id, user_id)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null
    references public.conversations (id) on delete cascade,
  author_id uuid not null default auth.uid() references public.profiles (id),
  body text check (char_length(body) between 1 and 4000),
  chamado_id uuid references public.chamados (id) on delete cascade,
  created_at timestamptz not null default now(),
  check ((body is null) <> (chamado_id is null))
);

create index messages_por_conversa on public.messages (conversation_id, created_at);

-- ---------------------------------------------------------------------------
-- Calendário

create table public.weekly_meetings (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null unique
    references public.conversations (id) on delete cascade,
  weekday integer not null check (weekday between 1 and 7),
  minute integer not null check (minute between 0 and 1439),
  game text check (char_length(game) <= 40)
);

create table public.meeting_exceptions (
  meeting_id uuid not null references public.weekly_meetings (id) on delete cascade,
  date date not null,
  skipped boolean not null default false,
  minute integer check (minute between 0 and 1439),
  primary key (meeting_id, date)
);

create table public.meeting_rsvps (
  meeting_id uuid not null references public.weekly_meetings (id) on delete cascade,
  date date not null,
  user_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  status public.rsvp_status not null,
  reason text check (char_length(reason) <= 120),
  primary key (meeting_id, date, user_id)
);

create table public.availability (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  weekday integer not null check (weekday between 1 and 7),
  start_minute integer not null check (start_minute between 0 and 1439),
  end_minute integer not null check (end_minute between 1 and 1440),
  check (start_minute < end_minute)
);

-- Aparelhos para o push (FCM).
create table public.device_tokens (
  token text primary key,
  user_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Funções de apoio às regras (security definer evita recursão nas políticas)

create function public.is_group_member(g uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from group_members where group_id = g and user_id = auth.uid()
  )
$$;

create function public.is_conversation_member(c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from conversation_members
    where conversation_id = c and user_id = auth.uid()
  )
$$;

create function public.shares_group(other uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1
    from group_members a join group_members b using (group_id)
    where a.user_id = auth.uid() and b.user_id = other
  )
$$;

create function public.can_see_chamado(ch uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from chamados c
    where c.id = ch and is_conversation_member(c.conversation_id)
  )
$$;

create function public.can_see_meeting(m uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from weekly_meetings w
    where w.id = m and is_conversation_member(w.conversation_id)
  )
$$;

-- ---------------------------------------------------------------------------
-- Perfil nasce com o login (nome do provedor é só sugestão)

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  suggested text := btrim(coalesce(
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'name',
    new.raw_user_meta_data ->> 'user_name',
    ''
  ));
begin
  insert into profiles (id, name, emoji, color)
  values (
    new.id,
    coalesce(nullif(left(suggested, 24), ''), 'Sem nome'),
    (array['🎮', '👾', '🕹️', '🎲', '🚀', '🐉'])[1 + floor(random() * 6)::int],
    (array[-16121, -11549705, -8271996, -1086464, -6543440, -4056997])
      [1 + floor(random() * 6)::int]
  );
  return new;
end
$$;

create trigger ao_criar_usuario
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Quem cadastra o jogo já é dono dele.
create function public.game_owner_on_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into game_owners (game_id, user_id) values (new.id, new.created_by)
  on conflict do nothing;
  return new;
end
$$;

create trigger dono_do_jogo_novo
  after insert on public.games
  for each row execute function public.game_owner_on_insert();

-- ---------------------------------------------------------------------------
-- Regras de acesso

alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.conversations enable row level security;
alter table public.conversation_members enable row level security;
alter table public.quick_replies enable row level security;
alter table public.games enable row level security;
alter table public.game_owners enable row level security;
alter table public.chamados enable row level security;
alter table public.chamado_targets enable row level security;
alter table public.chamado_vetoes enable row level security;
alter table public.messages enable row level security;
alter table public.weekly_meetings enable row level security;
alter table public.meeting_exceptions enable row level security;
alter table public.meeting_rsvps enable row level security;
alter table public.availability enable row level security;
alter table public.device_tokens enable row level security;

create policy "vê o próprio perfil e o de quem divide grupo" on public.profiles
  for select using (id = auth.uid() or shares_group(id));
create policy "edita só o próprio perfil" on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

create policy "vê os próprios grupos" on public.groups
  for select using (is_group_member(id));
create policy "membro renomeia o grupo" on public.groups
  for update using (is_group_member(id)) with check (is_group_member(id));

create policy "vê quem está nos seus grupos" on public.group_members
  for select using (is_group_member(group_id));
create policy "sai do grupo" on public.group_members
  for delete using (user_id = auth.uid());

create policy "vê as próprias conversas" on public.conversations
  for select using (is_conversation_member(id));
create policy "vê quem está nas suas conversas" on public.conversation_members
  for select using (is_conversation_member(conversation_id));

create policy "vê as comuns e as próprias" on public.quick_replies
  for select using (owner_id is null or owner_id = auth.uid());
create policy "cria só as próprias" on public.quick_replies
  for insert with check (owner_id = auth.uid() and kind <> 'snooze');
create policy "apaga só as próprias" on public.quick_replies
  for delete using (owner_id = auth.uid());

create policy "vê os jogos do grupo" on public.games
  for select using (is_group_member(group_id));
create policy "membro cadastra jogo" on public.games
  for insert with check (is_group_member(group_id) and created_by = auth.uid());
create policy "membro remove jogo" on public.games
  for delete using (is_group_member(group_id));

create policy "vê quem tem os jogos do grupo" on public.game_owners
  for select using (
    exists (select 1 from games g where g.id = game_id and is_group_member(g.group_id))
  );
create policy "marca que tem" on public.game_owners
  for insert with check (
    user_id = auth.uid() and
    exists (select 1 from games g where g.id = game_id and is_group_member(g.group_id))
  );
create policy "desmarca" on public.game_owners
  for delete using (user_id = auth.uid());

create policy "vê Chamados das suas conversas" on public.chamados
  for select using (is_conversation_member(conversation_id));
create policy "vê respostas dos Chamados visíveis" on public.chamado_targets
  for select using (can_see_chamado(chamado_id));
create policy "vê vetos dos Chamados visíveis" on public.chamado_vetoes
  for select using (can_see_chamado(chamado_id));

create policy "lê mensagens das suas conversas" on public.messages
  for select using (is_conversation_member(conversation_id));
create policy "manda texto em nome próprio" on public.messages
  for insert with check (
    author_id = auth.uid() and chamado_id is null and
    is_conversation_member(conversation_id)
  );

create policy "vê encontro das suas conversas" on public.weekly_meetings
  for select using (is_conversation_member(conversation_id));
create policy "membro marca encontro no grupo" on public.weekly_meetings
  for all using (is_conversation_member(conversation_id))
  with check (
    is_conversation_member(conversation_id) and
    exists (select 1 from conversations c where c.id = conversation_id and c.kind = 'group')
  );

create policy "membro mexe nas exceções" on public.meeting_exceptions
  for all using (can_see_meeting(meeting_id)) with check (can_see_meeting(meeting_id));

create policy "vê confirmações" on public.meeting_rsvps
  for select using (can_see_meeting(meeting_id));
create policy "confirma em nome próprio" on public.meeting_rsvps
  for insert with check (user_id = auth.uid() and can_see_meeting(meeting_id));
create policy "muda a própria confirmação" on public.meeting_rsvps
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid() and can_see_meeting(meeting_id));
create policy "apaga a própria confirmação" on public.meeting_rsvps
  for delete using (user_id = auth.uid());

create policy "vê horários de quem divide grupo" on public.availability
  for select using (user_id = auth.uid() or shares_group(user_id));
create policy "marca os próprios horários" on public.availability
  for insert with check (user_id = auth.uid());
create policy "apaga os próprios horários" on public.availability
  for delete using (user_id = auth.uid());

create policy "cuida só dos próprios aparelhos" on public.device_tokens
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Ações (regras de negócio no servidor)

create function public.create_group(p_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  g uuid;
  c uuid;
begin
  if me is null then raise exception 'precisa estar logado'; end if;
  insert into groups (name, created_by) values (btrim(p_name), me) returning id into g;
  insert into group_members (group_id, user_id) values (g, me);
  insert into conversations (group_id, kind, name) values (g, 'group', btrim(p_name))
    returning id into c;
  insert into conversation_members (conversation_id, user_id) values (c, me);
  return g;
end
$$;

create function public.join_group(p_code text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  g uuid;
begin
  if me is null then raise exception 'precisa estar logado'; end if;
  select id into g from groups where invite_code = upper(btrim(p_code));
  if g is null then raise exception 'código de convite inválido'; end if;
  insert into group_members (group_id, user_id) values (g, me) on conflict do nothing;
  insert into conversation_members (conversation_id, user_id)
    select id, me from conversations where group_id = g and kind = 'group'
  on conflict do nothing;
  return g;
end
$$;

-- Conversa individual com alguém do mesmo grupo (reaproveita se já existe).
create function public.open_direct(p_other uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  c uuid;
  g uuid;
begin
  if me is null then raise exception 'precisa estar logado'; end if;
  if p_other = me or not shares_group(p_other) then
    raise exception 'só dá para conversar com alguém do seu grupo';
  end if;
  select cv.id into c
  from conversations cv
  join conversation_members a on a.conversation_id = cv.id and a.user_id = me
  join conversation_members b on b.conversation_id = cv.id and b.user_id = p_other
  where cv.kind = 'direct'
  limit 1;
  if c is not null then return c; end if;

  select a.group_id into g
  from group_members a join group_members b using (group_id)
  where a.user_id = me and b.user_id = p_other
  limit 1;
  insert into conversations (group_id, kind) values (g, 'direct') returning id into c;
  insert into conversation_members (conversation_id, user_id) values (c, me), (c, p_other);
  return c;
end
$$;

-- Sorteia um jogo do grupo que todos em p_players têm, que cabe nesse número
-- de pessoas e que não está em p_excluded.
create function public.draw_game(p_group uuid, p_players uuid[], p_excluded uuid[])
returns uuid
language sql volatile security definer set search_path = public as $$
  select g.id
  from games g
  where g.group_id = p_group
    and cardinality(p_players) between g.min_players and g.max_players
    and not (g.id = any (coalesce(p_excluded, '{}')))
    and (select count(*) from game_owners o
         where o.game_id = g.id and o.user_id = any (p_players))
        = cardinality(p_players)
  order by random()
  limit 1
$$;

create function public.send_chamado(
  p_conversation uuid,
  p_targets uuid[],
  p_game uuid default null,
  p_draw boolean default false,
  p_note text default null,
  p_scheduled_for timestamptz default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  grp uuid;
  targets uuid[];
  chosen uuid;
  chosen_name text;
  ch uuid;
begin
  if me is null then raise exception 'precisa estar logado'; end if;
  if not is_conversation_member(p_conversation) then
    raise exception 'você não está nessa conversa';
  end if;
  select array_agg(distinct t) into targets from unnest(p_targets) t where t <> me;
  if targets is null then raise exception 'Chamado sem ninguém para chamar'; end if;
  if exists (
    select 1 from unnest(targets) t
    where not exists (
      select 1 from conversation_members m
      where m.conversation_id = p_conversation and m.user_id = t
    )
  ) then
    raise exception 'só dá para chamar quem está na conversa';
  end if;
  if p_game is not null and p_draw then
    raise exception 'escolha um jogo ou o sorteio, não os dois';
  end if;

  select group_id into grp from conversations where id = p_conversation;
  if p_game is not null then
    select id, name into chosen, chosen_name from games
    where id = p_game and group_id = grp;
    if chosen is null then raise exception 'jogo fora da biblioteca do grupo'; end if;
  elsif p_draw then
    chosen := draw_game(grp, targets || me, '{}');
    if chosen is null then raise exception 'nenhum jogo em comum para sortear'; end if;
    select name into chosen_name from games where id = chosen;
  end if;

  insert into chamados (conversation_id, author_id, game_id, game_name, drawn, note, scheduled_for)
  values (p_conversation, me, chosen, chosen_name, p_draw, nullif(btrim(p_note), ''), p_scheduled_for)
  returning id into ch;
  insert into chamado_targets (chamado_id, user_id) select ch, unnest(targets);
  insert into messages (conversation_id, author_id, chamado_id) values (p_conversation, me, ch);
  return ch;
end
$$;

create function public.respond_chamado(
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
      eta_minutes = coalesce(p_eta, r.eta_minutes), responded_at = now()
  where chamado_id = p_chamado and user_id = me;

  if not exists (
    select 1 from chamado_targets where chamado_id = p_chamado and responded_at is null
  ) then
    update chamados set status = 'answered' where id = p_chamado;
  end if;
end
$$;

create function public.veto_game(p_chamado uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  c chamados;
  players uuid[];
  next_game uuid;
begin
  if me is null then raise exception 'precisa estar logado'; end if;
  select * into c from chamados where id = p_chamado for update;
  select array_agg(user_id) || c.author_id into players
  from chamado_targets where chamado_id = p_chamado;
  if c.id is null or c.status <> 'open' or not c.drawn or c.game_id is null
     or not (me = any (players))
     or exists (select 1 from chamado_vetoes where chamado_id = p_chamado and user_id = me)
  then
    raise exception 'não dá para vetar esse Chamado';
  end if;

  insert into chamado_vetoes (chamado_id, user_id, game_id) values (p_chamado, me, c.game_id);
  next_game := draw_game(
    (select group_id from conversations where id = c.conversation_id),
    players,
    (select array_agg(game_id) from chamado_vetoes where chamado_id = p_chamado)
  );
  update chamados
  set game_id = next_game,
      game_name = (select name from games where id = next_game)
  where id = p_chamado;
end
$$;

create function public.close_chamado(p_chamado uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update chamados set status = 'closed'
  where id = p_chamado and author_id = auth.uid() and status = 'open';
  if not found and not exists (
    select 1 from chamados where id = p_chamado and author_id = auth.uid()
  ) then
    raise exception 'só quem chamou encerra o Chamado';
  end if;
end
$$;

-- As ações só para quem está logado.
revoke execute on function
  public.create_group(text), public.join_group(text), public.open_direct(uuid),
  public.draw_game(uuid, uuid[], uuid[]),
  public.send_chamado(uuid, uuid[], uuid, boolean, text, timestamptz),
  public.respond_chamado(uuid, uuid, integer), public.veto_game(uuid),
  public.close_chamado(uuid)
from public;
grant execute on function
  public.create_group(text), public.join_group(text), public.open_direct(uuid),
  public.send_chamado(uuid, uuid[], uuid, boolean, text, timestamptz),
  public.respond_chamado(uuid, uuid, integer), public.veto_game(uuid),
  public.close_chamado(uuid)
to authenticated;

-- ---------------------------------------------------------------------------
-- Tempo real (a publicação existe no Supabase; localmente, não)

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table
      public.messages, public.chamados, public.chamado_targets,
      public.chamado_vetoes, public.profiles, public.games, public.game_owners,
      public.weekly_meetings, public.meeting_exceptions, public.meeting_rsvps,
      public.availability;
  end if;
end
$$;
