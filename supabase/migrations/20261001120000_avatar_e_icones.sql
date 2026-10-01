-- Fotos de verdade no lugar do emoji sorteado, e respostas rápidas com
-- ícone em vez de emoji.
--
-- O emoji continua na tabela como reserva: quem entrou por um provedor sem
-- foto, ou apagou a foto depois, continua com um rosto no lugar do vazio.

-- ---------------------------------------------------------------------------
-- Foto do perfil

alter table public.profiles add column avatar_url text;

-- O Discord manda em avatar_url; o Google, em picture.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  suggested text := btrim(coalesce(
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'name',
    new.raw_user_meta_data ->> 'user_name',
    ''
  ));
begin
  insert into profiles (id, name, emoji, color, avatar_url)
  values (
    new.id,
    coalesce(nullif(left(suggested, 24), ''), 'Sem nome'),
    (array['🎮', '👾', '🕹️', '🎲', '🚀', '🐉'])[1 + floor(random() * 6)::int],
    (array[-16121, -11549705, -8271996, -1086464, -6543440, -4056997])
      [1 + floor(random() * 6)::int],
    nullif(btrim(coalesce(
      new.raw_user_meta_data ->> 'avatar_url',
      new.raw_user_meta_data ->> 'picture',
      ''
    )), '')
  );
  return new;
end
$$;

-- Quem já entrou antes desta migração também ganha a foto.
update public.profiles p
set avatar_url = nullif(btrim(coalesce(
      u.raw_user_meta_data ->> 'avatar_url',
      u.raw_user_meta_data ->> 'picture',
      ''
    )), '')
from auth.users u
where u.id = p.id and p.avatar_url is null;

-- ---------------------------------------------------------------------------
-- Ícone das respostas rápidas
--
-- Guarda o nome do ícone, não o desenho: o app escolhe como desenhar, e a
-- mesma resposta fica igual em qualquer celular (emoji muda de cara conforme
-- o aparelho).

alter table public.quick_replies
  add column icon text not null default 'balao'
  check (char_length(btrim(icon)) between 1 and 24);

update public.quick_replies set icon = case kind
  when 'yes' then 'check'
  when 'later' then 'relogio'
  when 'no' then 'xis'
  when 'snooze' then 'soneca'
end
where owner_id is null;

-- O emoji vira opcional: o app novo não manda mais, mas as respostas
-- antigas continuam válidas.
alter table public.quick_replies alter column emoji set default '💬';

-- O Chamado guarda uma cópia da resposta escolhida; a cópia também precisa
-- do ícone, senão o card perde o desenho quando a pessoa apaga a resposta.
alter table public.chamado_targets add column reply_icon text;

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
      eta_minutes = coalesce(p_eta, r.eta_minutes), responded_at = now()
  where chamado_id = p_chamado and user_id = me;

  if not exists (
    select 1 from chamado_targets where chamado_id = p_chamado and responded_at is null
  ) then
    update chamados set status = 'answered' where id = p_chamado;
  end if;
end
$$;
