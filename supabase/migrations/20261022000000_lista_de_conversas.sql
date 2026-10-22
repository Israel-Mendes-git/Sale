-- A lista de conversas do jeito de cada um, e a mensagem encaminhada.
--
-- Fixar, silenciar e marcar como não lida são escolhas de quem usa, não da
-- conversa: o grupo fixado no topo do meu celular não sobe no seu. Ficam numa
-- tabela à parte, e não em conversation_members, porque lá todo mundo da
-- conversa lê a linha de todo mundo — e ninguém precisa saber que você
-- silenciou o grupo.
--
-- Silenciada cala o aviso de mensagem comum até `muted_until` ('infinity' =
-- até reativar). Menção a você e Chamado continuam tocando: o Chamado é a
-- razão de ser do app, e quem te chamou pelo nome quer mesmo você.
--
-- Marcada como não lida é o "depois eu vejo": a conversa fica com a bolinha
-- até ser aberta de novo, quando mark_read a desmarca.

create table public.conversation_prefs (
  conversation_id uuid not null
    references public.conversations (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  pinned_at timestamptz,
  muted_until timestamptz,
  marked_unread boolean not null default false,
  primary key (conversation_id, user_id)
);

alter table public.conversation_prefs enable row level security;

-- Só as próprias, e só de conversa em que se está.
create policy "vê as próprias escolhas" on public.conversation_prefs
  for select using (user_id = auth.uid());
create policy "escolhe nas próprias conversas" on public.conversation_prefs
  for insert with check (
    user_id = auth.uid() and is_conversation_member(conversation_id)
  );
create policy "muda as próprias escolhas" on public.conversation_prefs
  for update using (user_id = auth.uid())
  with check (
    user_id = auth.uid() and is_conversation_member(conversation_id)
  );

-- Abrir a conversa também tira o "não lida".
create or replace function public.mark_read(p_conversation uuid) returns void
language sql security definer set search_path = public as $$
  update conversation_members
  set read_until = greatest(read_until, now()),
      delivered_until = greatest(delivered_until, now())
  where conversation_id = p_conversation and user_id = auth.uid();

  update conversation_prefs set marked_unread = false
  where conversation_id = p_conversation and user_id = auth.uid()
    and marked_unread;
$$;

-- Encaminhada: a mensagem veio de outra conversa. A bolha avisa, como no
-- WhatsApp; de onde veio não se guarda — a outra conversa pode ser a dois.
alter table public.messages
  add column forwarded boolean not null default false;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.conversation_prefs;
  end if;
end
$$;

create or replace function public.versao_do_esquema() returns text
language sql immutable set search_path = public as $$ select '20261022000000' $$;
