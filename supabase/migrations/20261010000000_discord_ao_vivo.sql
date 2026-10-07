-- O Discord sem webhook e com memória. O Chamado não vai mais para o canal
-- (a coluna discord_webhook fica até a 1.4.0 sair dos celulares, porque ela a
-- lê; ninguém mais a usa). No lugar, o servidor anota a call:
--
-- * call_minutos: a cada minuto, quem está numa call do servidor do grupo,
--   pelo widget público. O cron do disparo (disparar-agendados) lê o widget e
--   chama registrar_call(), que diz se a call acabou de abrir, para o aviso
--   "fulano entrou na call".
-- * profiles.discord_nome: o nome da pessoa no Discord, para ligar o minuto
--   de call a alguém do grupo (o widget só dá o nome).
-- * tempo_de_call(): quanto cada um ficou em call, para o Placar.
-- * o resumo da semana ganha as horas de call e quem mais ficou.

alter table public.profiles
  add column discord_nome text check (char_length(btrim(discord_nome)) between 1 and 40);

create table public.call_minutos (
  group_id uuid not null references public.groups (id) on delete cascade,
  minuto timestamptz not null,
  nome text not null,
  canal text,
  primary key (group_id, minuto, nome)
);

alter table public.call_minutos enable row level security;
create policy "vê a call do próprio grupo" on public.call_minutos
  for select using (is_group_member(group_id));

-- Anota quem está na call neste minuto ([p_pessoas]: [{nome, canal}]) e diz
-- se a call acabou de abrir: ninguém nos dez minutos anteriores. Rodar duas
-- vezes no mesmo minuto não anota de novo nem avisa de novo. Apaga o que tem
-- mais de seis meses.
create function public.registrar_call(
  p_grupo uuid,
  p_pessoas jsonb,
  p_minuto timestamptz default date_trunc('minute', now())
) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  abriu boolean;
begin
  delete from call_minutos
  where group_id = p_grupo and minuto < p_minuto - interval '180 days';
  if coalesce(jsonb_array_length(p_pessoas), 0) = 0 then return false; end if;
  if exists (
    select 1 from call_minutos where group_id = p_grupo and minuto = p_minuto
  ) then return false; end if;
  abriu := not exists (
    select 1 from call_minutos
    where group_id = p_grupo
      and minuto >= p_minuto - interval '10 minutes' and minuto < p_minuto
  );
  insert into call_minutos (group_id, minuto, nome, canal)
  select p_grupo, p_minuto, left(btrim(x ->> 'nome'), 40), left(x ->> 'canal', 100)
  from jsonb_array_elements(p_pessoas) x
  where coalesce(btrim(x ->> 'nome'), '') <> ''
  on conflict do nothing;
  return abriu;
end
$$;

revoke execute on function public.registrar_call(uuid, jsonb, timestamptz)
  from public, anon, authenticated;
grant execute on function public.registrar_call(uuid, jsonb, timestamptz)
  to service_role;

-- Quem do grupo [p_grupo] usa o nome [p_nome] no Discord.
create function public.quem_no_discord(p_grupo uuid, p_nome text)
returns uuid
language sql stable security definer set search_path = public as $$
  select p.id from profiles p
  join group_members gm on gm.user_id = p.id and gm.group_id = p_grupo
  where lower(btrim(p.discord_nome)) = lower(btrim(p_nome))
  order by p.id
  limit 1
$$;

-- O nome no Sale de quem usa [p_nome] no Discord, se alguém do grupo usa.
create function public.nome_do_discord(p_grupo uuid, p_nome text)
returns text
language sql stable security definer set search_path = public as $$
  select name from profiles where id = quem_no_discord(p_grupo, p_nome)
$$;

revoke execute on function public.quem_no_discord(uuid, text),
  public.nome_do_discord(uuid, text) from public, anon, authenticated;
grant execute on function public.quem_no_discord(uuid, text),
  public.nome_do_discord(uuid, text) to service_role;

-- Quanto cada um ficou em call desde [p_desde], do que mais ficou para o que
-- menos, com quem é no grupo quando o nome do Discord bate com um perfil.
create function public.tempo_de_call(p_grupo uuid, p_desde timestamptz)
returns table (nome text, minutos integer, user_id uuid)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_group_member(p_grupo) then
    raise exception 'você não está nesse grupo';
  end if;
  return query
    select m.nome, count(*)::integer, quem_no_discord(p_grupo, m.nome)
    from call_minutos m
    where m.group_id = p_grupo and m.minuto >= p_desde
    group by m.nome
    order by count(*) desc, m.nome;
end
$$;

revoke execute on function public.tempo_de_call(uuid, timestamptz) from public, anon;
grant execute on function public.tempo_de_call(uuid, timestamptz) to authenticated;

-- "45 min", "2 h", "2 h 15".
create function public.duracao_em_texto(p_minutos integer)
returns text
language sql immutable set search_path = public as $$
  select case
    when p_minutos < 60 then p_minutos || ' min'
    when p_minutos % 60 = 0 then (p_minutos / 60) || ' h'
    else (p_minutos / 60) || ' h ' || lpad((p_minutos % 60)::text, 2, '0')
  end
$$;

-- O resumo da semana, agora com a call.
create or replace function public.resumos_pendentes(p_agora timestamptz default now())
returns table (conversation_id uuid, texto text)
language plpgsql security definer set search_path = public as $$
#variable_conflict use_column
declare
  g record;
  local timestamp;
  hora timestamp;
  domingo date;
  conversa uuid;
  inicio timestamptz;
  total integer;
  jogo text;
  chamador text;
  vezes integer;
  pontual text;
  atrasado text;
  minutos integer;
  partes text[];
  minutos_de_call integer;
  quem_mais_call text;
  minutos_dele integer;
begin
  for g in select id, timezone from groups loop
    local := p_agora at time zone g.timezone;
    if extract(isodow from local)::integer <> 7 then continue; end if;
    hora := local::date + time '20:00';
    -- Atrasado demais não vale: servidor que ficou fora do ar não manda o
    -- resumo de domingo na segunda de manhã.
    if local < hora or local >= hora + janela_do_disparo() then continue; end if;
    domingo := local::date;
    if exists (
      select 1 from resumos_semanais r
      where r.group_id = g.id and r.semana = domingo
    ) then continue; end if;
    select c.id into conversa from conversations c
    where c.group_id = g.id and c.kind = 'group'
    limit 1;
    if conversa is null then continue; end if;

    insert into resumos_semanais (group_id, semana) values (g.id, domingo);
    inicio := p_agora - interval '7 days';

    select count(*) into total
    from chamados ch join conversations c on c.id = ch.conversation_id
    where c.group_id = g.id and ch.created_at >= inicio;

    if total = 0 then
      partes := array['Semana sem Chamado. Bora marcar alguma coisa?'];
    else
      partes := array[
        total || case when total = 1 then ' Chamado' else ' Chamados' end
      ];

      select ch.game_name into jogo
      from chamados ch join conversations c on c.id = ch.conversation_id
      where c.group_id = g.id and ch.created_at >= inicio
        and ch.game_name is not null
      group by ch.game_name
      order by count(*) desc, ch.game_name
      limit 1;
      if jogo is not null then
        partes := partes || ('jogo da semana: ' || jogo);
      end if;

      -- O encontro fixo não tem ninguém chamando: fica de fora.
      select p.name, count(*) into chamador, vezes
      from chamados ch
      join conversations c on c.id = ch.conversation_id
      join profiles p on p.id = ch.author_id
      where c.group_id = g.id and ch.created_at >= inicio and not ch.automatic
      group by p.name
      order by count(*) desc, p.name
      limit 1;
      if chamador is not null then
        partes := partes || ('quem mais chamou: ' || chamador || ' (' || vezes || ')');
      end if;

      -- O atraso de cada chegada, como no app (Chamado.promisedBy): conta da
      -- resposta, ou do horário marcado se ele vier depois, mais o tempo
      -- prometido.
      with chegadas as (
        select t.user_id,
               extract(epoch from (
                 t.arrived_at - (
                   greatest(coalesce(ch.scheduled_for, t.responded_at),
                            t.responded_at)
                   + make_interval(mins => case when t.reply_kind = 'later'
                                                then t.eta_minutes else 0 end)
                 )
               )) / 60 as atraso
        from chamado_targets t
        join chamados ch on ch.id = t.chamado_id
        join conversations c on c.id = ch.conversation_id
        where c.group_id = g.id and ch.created_at >= inicio
          and t.arrived_at is not null
          and (t.reply_kind = 'yes'
               or (t.reply_kind = 'later' and t.eta_minutes is not null))
      ),
      medias as (
        select ch.user_id, avg(ch.atraso) as media
        from chegadas ch group by ch.user_id
      )
      select
        (select p.name from medias m join profiles p on p.id = m.user_id
         where m.media <= 1 order by m.media, p.name limit 1),
        (select p.name from medias m join profiles p on p.id = m.user_id
         where m.media > 1 order by m.media desc, p.name limit 1),
        (select round(max(m.media))::integer from medias m where m.media > 1)
      into pontual, atrasado, minutos;
      if pontual is not null then
        partes := partes || ('mais pontual: ' || pontual);
      end if;
      if atrasado is not null then
        partes := partes || ('quem mais atrasou: ' || atrasado
                             || ' (+' || minutos || ' min em média)');
      end if;
    end if;

    -- A call do Discord: quanto tempo teve alguém lá, e quem mais ficou.
    select count(distinct m.minuto) into minutos_de_call
    from call_minutos m where m.group_id = g.id and m.minuto >= inicio;
    if minutos_de_call > 0 then
      select coalesce(nome_do_discord(g.id, m.nome), m.nome), count(*)
      into quem_mais_call, minutos_dele
      from call_minutos m
      where m.group_id = g.id and m.minuto >= inicio
      group by m.nome
      order by count(*) desc, m.nome
      limit 1;
      if total = 0 then
        partes := array['Semana sem Chamado, mas com call'];
      end if;
      partes := partes || (duracao_em_texto(minutos_de_call) || ' de call')
        || ('mais tempo em call: ' || quem_mais_call
            || ' (' || duracao_em_texto(minutos_dele) || ')');
    end if;

    conversation_id := conversa;
    texto := array_to_string(partes, ' · ');
    return next;
  end loop;
end
$$;

create or replace function public.versao_do_esquema() returns text
language sql immutable set search_path = public as $$ select '20261010000000' $$;
