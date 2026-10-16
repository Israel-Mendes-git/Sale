-- Configurações do grupo: foto, descrição, administradores, remover alguém,
-- sair e trocar o código de convite.
--
-- Nome, foto e descrição qualquer membro muda (é um grupo de amigos). Quem
-- remove gente, nomeia admin e troca o convite é admin; quem cria o grupo
-- nasce admin. O grupo nunca fica sem admin enquanto tiver alguém: se o
-- último sai, o mais antigo herda; se não sobra ninguém, o grupo some.

-- ---------------------------------------------------------------------------
-- Colunas

alter table public.groups
  add column description text
    check (description is null or char_length(description) <= 300),
  -- Caminho no bucket "anexos", dentro da pasta da conversa do grupo: as
  -- regras de quem lê e grava os anexos já valem para a foto.
  add column photo_path text;

alter table public.group_members
  add column admin boolean not null default false;

-- Quem criou cada grupo é admin; grupo cujo criador já saiu fica com o membro
-- mais antigo.
update public.group_members m set admin = true
from public.groups g
where g.id = m.group_id and g.created_by = m.user_id;

update public.group_members m set admin = true
where not exists (
    select 1 from public.group_members o where o.group_id = m.group_id and o.admin)
  and m.user_id = (
    select o.user_id from public.group_members o
    where o.group_id = m.group_id
    order by o.joined_at, o.user_id
    limit 1);

-- O nome do grupo, a foto e a descrição mudam na tela de todos na hora.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.groups;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Utilitários

create function public.is_group_admin(p_group uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from group_members
    where group_id = p_group and user_id = auth.uid() and admin
  )
$$;

-- Sem admin e com gente: o mais antigo vira admin. Sem ninguém: o grupo some
-- (e leva conversas, mensagens e jogos junto, pelo "on delete cascade").
create function public.manter_um_admin(p_group uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from group_members where group_id = p_group) then
    delete from groups where id = p_group;
    return;
  end if;
  if not exists (select 1 from group_members where group_id = p_group and admin) then
    update group_members set admin = true
    where group_id = p_group
      and user_id = (
        select user_id from group_members where group_id = p_group
        order by joined_at, user_id limit 1);
  end if;
end
$$;

-- Tira alguém do grupo: sai da lista de membros e da conversa do grupo. As
-- conversas individuais ficam, como ficam no WhatsApp.
create function public.tirar_do_grupo(p_group uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from conversation_members cm
  using conversations c
  where c.id = cm.conversation_id and c.group_id = p_group
    and c.kind = 'group' and cm.user_id = p_user;
  delete from group_members where group_id = p_group and user_id = p_user;
  perform manter_um_admin(p_group);
end
$$;

-- Só o servidor usa estes dois: a porta para o app são as ações abaixo.
revoke execute on function public.manter_um_admin(uuid) from public, anon, authenticated;
revoke execute on function public.tirar_do_grupo(uuid, uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Ações

-- Nome e descrição. O nome também é o da conversa do grupo.
create function public.editar_grupo(p_group uuid, p_name text, p_description text)
returns void
language plpgsql security definer set search_path = public as $$
declare
  nome text := btrim(coalesce(p_name, ''));
  descricao text := nullif(btrim(coalesce(p_description, '')), '');
begin
  if not is_group_member(p_group) then raise exception 'você não é deste grupo'; end if;
  if char_length(nome) not between 1 and 40 then
    raise exception 'o nome do grupo precisa ter de 1 a 40 letras';
  end if;
  if char_length(coalesce(descricao, '')) > 300 then
    raise exception 'a descrição passa de 300 letras';
  end if;
  update groups set name = nome, description = descricao where id = p_group;
  update conversations set name = nome where group_id = p_group and kind = 'group';
end
$$;

-- A foto: o caminho de um arquivo já enviado para a pasta da conversa do
-- grupo, ou nulo para tirar.
create function public.trocar_foto_do_grupo(p_group uuid, p_path text) returns void
language plpgsql security definer set search_path = public as $$
declare
  pasta text;
begin
  if not is_group_member(p_group) then raise exception 'você não é deste grupo'; end if;
  if p_path is not null then
    select id::text into pasta from conversations
    where group_id = p_group and kind = 'group' limit 1;
    if pasta is null or split_part(p_path, '/', 1) <> pasta then
      raise exception 'a foto precisa estar na pasta da conversa do grupo';
    end if;
  end if;
  update groups set photo_path = p_path where id = p_group;
end
$$;

create function public.remover_do_grupo(p_group uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_group_admin(p_group) then raise exception 'só admin remove alguém'; end if;
  if p_user = auth.uid() then raise exception 'para sair, use "Sair do grupo"'; end if;
  if not exists (select 1 from group_members where group_id = p_group and user_id = p_user) then
    raise exception 'essa pessoa não está no grupo';
  end if;
  perform tirar_do_grupo(p_group, p_user);
end
$$;

-- Dá ou tira o admin de alguém. O último admin não perde o posto: para isso,
-- ele nomeia outro antes.
create function public.definir_admin(p_group uuid, p_user uuid, p_admin boolean)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_group_admin(p_group) then raise exception 'só admin nomeia admin'; end if;
  if not exists (select 1 from group_members where group_id = p_group and user_id = p_user) then
    raise exception 'essa pessoa não está no grupo';
  end if;
  if not p_admin and not exists (
    select 1 from group_members
    where group_id = p_group and admin and user_id <> p_user
  ) then
    raise exception 'o grupo precisa de pelo menos um admin';
  end if;
  update group_members set admin = p_admin
  where group_id = p_group and user_id = p_user;
end
$$;

create function public.sair_do_grupo(p_group uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_group_member(p_group) then raise exception 'você não é deste grupo'; end if;
  perform tirar_do_grupo(p_group, auth.uid());
end
$$;

-- Código novo: o antigo para de funcionar (para quando ele vazou).
create function public.novo_codigo_de_convite(p_group uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  codigo text;
begin
  if not is_group_admin(p_group) then raise exception 'só admin troca o convite'; end if;
  loop
    codigo := upper(substr(md5(gen_random_uuid()::text), 1, 8));
    exit when not exists (select 1 from groups where invite_code = codigo);
  end loop;
  update groups set invite_code = codigo where id = p_group;
  return codigo;
end
$$;

-- Quem cria nasce admin.
create or replace function public.create_group(p_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  g uuid;
  c uuid;
begin
  if me is null then raise exception 'precisa estar logado'; end if;
  insert into groups (name, created_by) values (btrim(p_name), me) returning id into g;
  insert into group_members (group_id, user_id, admin) values (g, me, true);
  insert into conversations (group_id, kind, name) values (g, 'group', btrim(p_name))
    returning id into c;
  insert into conversation_members (conversation_id, user_id) values (c, me);
  return g;
end
$$;

-- O "update" direto do app (a regra "membro renomeia o grupo") fica só para o
-- Discord. Nome, foto e descrição passam pelas ações acima, que conferem o
-- tamanho e levam o nome para a conversa; o convite e o dono, só admin ou
-- ninguém. As ações rodam como o dono das funções, não como "authenticated",
-- e passam.
create function public.grupo_so_muda_pelas_acoes() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user in ('authenticated', 'anon') and (
    new.name is distinct from old.name
    or new.description is distinct from old.description
    or new.photo_path is distinct from old.photo_path
    or new.invite_code is distinct from old.invite_code
    or new.created_by is distinct from old.created_by
    or new.timezone is distinct from old.timezone
  ) then
    raise exception 'isso muda pelas configurações do grupo';
  end if;
  return new;
end
$$;

create trigger grupo_so_muda_pelas_acoes before update on public.groups
  for each row execute function public.grupo_so_muda_pelas_acoes();

-- Sair só pela ação, que também tira da conversa e cuida do admin.
drop policy "sai do grupo" on public.group_members;

create or replace function public.versao_do_esquema() returns text
language sql immutable set search_path = public as $$ select '20261016000000' $$;
