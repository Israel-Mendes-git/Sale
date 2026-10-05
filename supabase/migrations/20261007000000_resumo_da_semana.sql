-- O resumo da semana: domingo às 20h, no fuso do grupo, um aviso com o que
-- a semana foi — quantos Chamados, o jogo da semana, quem mais chamou, quem
-- foi o mais pontual e quem mais atrasou.
--
-- Quem manda é o mesmo cron do disparo (docs/CRON.md). Uma linha por semana
-- enviada impede o cron, que roda a cada minuto, de mandar quinze vezes.

create table public.resumos_semanais (
  group_id uuid not null references public.groups (id) on delete cascade,
  semana date not null,
  enviado_em timestamptz not null default now(),
  primary key (group_id, semana)
);

-- Só o servidor mexe nela.
alter table public.resumos_semanais enable row level security;

-- Os resumos que venceram agora: um por grupo, com o texto do aviso.
-- [p_agora] existe para os testes poderem viajar no tempo.
create function public.resumos_pendentes(p_agora timestamptz default now())
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

    conversation_id := conversa;
    texto := array_to_string(partes, ' · ');
    return next;
  end loop;
end
$$;

-- No Supabase toda função nova vem com execute para anon e authenticated.
revoke execute on function public.resumos_pendentes(timestamptz)
  from public, anon, authenticated;
grant execute on function public.resumos_pendentes(timestamptz) to service_role;
