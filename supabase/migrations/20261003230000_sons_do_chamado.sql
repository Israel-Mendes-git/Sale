-- O som do Chamado, que era a última pergunta em aberto do PRD.
--
-- Até agora o Chamado tocava o som padrão de notificação do aparelho: o mesmo
-- de qualquer aviso, que é o contrário de um batsinal. Agora o app traz cinco
-- sons, cada grupo pode subir os seus, e quem dispara escolhe qual toca.
--
-- Os sons que vêm no app e os do grupo moram na mesma tabela, com group_id
-- nulo = vem no app — igual às respostas rápidas comuns a todos. Em `file`, o
-- som do app guarda o nome do arquivo (`res/raw` e `assets/sons`) e o do grupo
-- o caminho dele no Storage (bucket "sons").

create table public.sounds (
  id uuid primary key default gen_random_uuid(),
  -- Nulo = som que vem no app, igual para todos os grupos.
  group_id uuid references public.groups (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 24),
  file text not null check (char_length(btrim(file)) between 1 and 200),
  created_by uuid default auth.uid() references public.profiles (id),
  created_at timestamptz not null default now()
);

-- Um nome por grupo, e também entre os que vêm no app (daí o
-- `nulls not distinct`: para este índice, group_id nulo é um valor como outro).
create unique index sounds_nome_unico
  on public.sounds (group_id, lower(btrim(name))) nulls not distinct;

insert into public.sounds (name, file) values
  ('Batsinal', 'batsinal'),
  ('Sirene', 'sirene'),
  ('Telefone', 'telefone'),
  ('Alarme', 'alarme'),
  ('Radar', 'radar');

alter table public.sounds enable row level security;

create policy "vê os sons do app e os do grupo" on public.sounds
  for select using (group_id is null or is_group_member(group_id));
-- Som do app ninguém cadastra nem apaga: ele vem dentro do APK.
create policy "membro cadastra som no grupo" on public.sounds
  for insert with check (
    group_id is not null and is_group_member(group_id)
    and created_by = auth.uid()
  );
create policy "membro remove som do grupo" on public.sounds
  for delete using (group_id is not null and is_group_member(group_id));

-- O som daquele Chamado, do jeito que o app precisa para tocá-lo: o nome do
-- arquivo, quando o som vem no app, ou o id do som, quando é do grupo. É o
-- mesmo nome do canal de notificação no aparelho.
--
-- Guardado em vez de consultado de propósito, como o nome do jogo: som que o
-- grupo apagar depois não muda o que já tocou, e o push não precisa de mais
-- uma consulta. Nulo = o som da marca, que é o padrão de quem não escolhe.
alter table public.chamados
  add column sound_key text
    check (char_length(btrim(sound_key)) between 1 and 64);

-- O som que a pessoa usa quando chama, escolhido em "Meu perfil → Som do
-- Chamado" e já marcado na tela do Chamado. Som do grupo apagado volta a ser
-- nulo, e nulo é o som da marca.
alter table public.profiles
  add column sound_id uuid references public.sounds (id) on delete set null;

-- O grupo a que um arquivo do bucket "sons" pertence: a primeira pasta do
-- caminho (`<grupo>/<arquivo>`). Nulo quando o caminho não começa com um id,
-- para a regra de acesso recusar em vez de estourar.
create function public.grupo_do_arquivo(caminho text) returns uuid
language plpgsql immutable as $$
begin
  return split_part(caminho, '/', 1)::uuid;
exception when others then
  return null;
end
$$;

-- ---------------------------------------------------------------------------
-- Disparar escolhendo o som

drop function public.send_chamado(uuid, uuid[], uuid, boolean, text, timestamptz);
create function public.send_chamado(
  p_conversation uuid,
  p_targets uuid[],
  p_game uuid default null,
  p_draw boolean default false,
  p_note text default null,
  p_scheduled_for timestamptz default null,
  p_sound uuid default null
) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  grp uuid;
  targets uuid[];
  chosen uuid;
  chosen_name text;
  key text;
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

  -- O som sai da lista que esta conversa enxerga: os do app e os do grupo
  -- dela. Som de outro grupo não toca aqui.
  if p_sound is not null then
    select case when s.group_id is null then s.file else s.id::text end
      into key
    from sounds s
    where s.id = p_sound and (s.group_id is null or s.group_id = grp);
    if key is null then raise exception 'som fora da lista do grupo'; end if;
  end if;

  insert into chamados (conversation_id, author_id, game_id, game_name, drawn,
                        note, scheduled_for, sound_key)
  values (p_conversation, me, chosen, chosen_name, p_draw,
          nullif(btrim(p_note), ''), p_scheduled_for, key)
  returning id into ch;
  insert into chamado_targets (chamado_id, user_id) select ch, unnest(targets);
  insert into messages (conversation_id, author_id, chamado_id)
  values (p_conversation, me, ch);
  return ch;
end
$$;

revoke execute on function
  public.send_chamado(uuid, uuid[], uuid, boolean, text, timestamptz, uuid)
from public;
grant execute on function
  public.send_chamado(uuid, uuid[], uuid, boolean, text, timestamptz, uuid)
to authenticated;

-- ---------------------------------------------------------------------------
-- Os arquivos dos sons do grupo (Storage)
--
-- Um bucket fechado, com os arquivos em `<grupo>/<arquivo>`: quem está no
-- grupo sobe, lê e apaga; de fora, ninguém. No Postgres dos testes não existe
-- o schema storage, e aí esta parte não roda.

do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit)
    values ('sons', 'sons', false, 2097152)
    on conflict (id) do nothing;

    execute $pol$
      create policy "membro lê os sons do grupo" on storage.objects
        for select using (
          bucket_id = 'sons'
          and public.is_group_member(public.grupo_do_arquivo(name))
        )
    $pol$;
    execute $pol$
      create policy "membro sobe som no grupo" on storage.objects
        for insert with check (
          bucket_id = 'sons'
          and public.is_group_member(public.grupo_do_arquivo(name))
        )
    $pol$;
    execute $pol$
      create policy "membro apaga som do grupo" on storage.objects
        for delete using (
          bucket_id = 'sons'
          and public.is_group_member(public.grupo_do_arquivo(name))
        )
    $pol$;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Tempo real: som novo aparece na lista de quem está com o app aberto

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.sounds;
  end if;
end
$$;
