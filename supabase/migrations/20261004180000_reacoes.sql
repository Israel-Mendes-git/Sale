-- Reação na mensagem: responder sem escrever.
--
-- Uma por pessoa por mensagem, como a chave primária diz. Trocar de emoji é
-- trocar a que já existe, e tocar no mesmo de novo tira a sua — nada de
-- empilhar quinze reações de uma pessoa só na mesma mensagem.

create table public.message_reactions (
  message_id uuid not null references public.messages (id) on delete cascade,
  user_id uuid not null default auth.uid()
    references public.profiles (id) on delete cascade,
  -- Um emoji cabe em poucos caracteres, mas os compostos (bandeiras, pessoas
  -- com tom de pele) gastam mais de um.
  emoji text not null check (char_length(emoji) between 1 and 16),
  created_at timestamptz not null default now(),
  primary key (message_id, user_id)
);

-- Quem vê a mensagem vê as reações dela. Mora numa função porque a regra é a
-- da conversa da mensagem, não a da linha da reação.
create function public.can_see_message(m uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from messages msg
    where msg.id = m and is_conversation_member(msg.conversation_id)
  )
$$;

alter table public.message_reactions enable row level security;

create policy "vê as reações das mensagens que vê" on public.message_reactions
  for select using (can_see_message(message_id));
create policy "reage em nome próprio" on public.message_reactions
  for insert with check (
    user_id = auth.uid() and can_see_message(message_id)
  );
create policy "troca a própria reação" on public.message_reactions
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "tira a própria reação" on public.message_reactions
  for delete using (user_id = auth.uid());

-- Tempo real: a reação aparece no celular de quem está com a conversa aberta.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.message_reactions;
  end if;
end
$$;
