-- Placar do atraso: guardar a chegada de verdade, para comparar com o
-- "chego em X min".
--
-- Quem prometeu vir toca em "Cheguei" e o servidor anota a hora. O resto das
-- estatísticas (quem mais chama, quem mais recusa, jogo mais jogado) sai dos
-- Chamados que já existem, contado no app.

alter table public.chamado_targets add column arrived_at timestamptz;

-- Marca a chegada de quem está pedindo. A hora é a do servidor, não a do
-- celular: relógio adiantado não compra pontualidade.
create function public.arrive_chamado(p_chamado uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  st chamado_status;
begin
  if me is null then raise exception 'precisa estar logado'; end if;
  select status into st from chamados where id = p_chamado;
  if st is null then raise exception 'Chamado não encontrado'; end if;
  -- Encerrado por quem chamou não espera mais ninguém.
  if st = 'closed' then raise exception 'esse Chamado já foi encerrado'; end if;

  update chamado_targets
  set arrived_at = now()
  where chamado_id = p_chamado
    and user_id = me
    and arrived_at is null
    and reply_kind in ('yes', 'later');
  if not found then
    raise exception 'só quem disse que vinha marca que chegou';
  end if;
end
$$;

-- Responder de novo recomeça a promessa, então a chegada antiga cai: senão a
-- conta do atraso compararia a chegada de antes com o prazo de agora.
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
      eta_minutes = coalesce(p_eta, r.eta_minutes), responded_at = now(),
      arrived_at = null
  where chamado_id = p_chamado and user_id = me;

  if not exists (
    select 1 from chamado_targets where chamado_id = p_chamado and responded_at is null
  ) then
    update chamados set status = 'answered' where id = p_chamado;
  end if;
end
$$;

revoke execute on function public.arrive_chamado(uuid) from public;
grant execute on function public.arrive_chamado(uuid) to authenticated;
