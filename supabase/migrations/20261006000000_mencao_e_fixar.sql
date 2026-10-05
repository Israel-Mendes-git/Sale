-- Menção e mensagem fixada.
--
-- Menção: "@Nome" no texto chama a atenção de alguém, e "@todos" de todo
-- mundo. O texto guarda a menção como foi escrita; quem foi mencionado vai
-- também nesta lista, que é por onde o push sabe quem avisar com mais força.
-- Quem escreve monta a lista; o push só avisa quem está mesmo na conversa.
--
-- Fixada: uma mensagem por conversa no topo dela — o IP do servidor, o
-- horário combinado. Qualquer um da conversa fixa e desafixa, pela ação
-- pin_message; apagar a mensagem fixada a tira do topo.

alter table public.messages
  add column mentions uuid[] not null default '{}';

alter table public.conversations
  add column pinned_message_id uuid
    references public.messages (id) on delete set null;

create function public.pin_message(p_conversation uuid, p_message uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'precisa estar logado'; end if;
  if not is_conversation_member(p_conversation) then
    raise exception 'você não está nessa conversa';
  end if;
  if p_message is not null and not exists (
    select 1 from messages
    where id = p_message and conversation_id = p_conversation
      and deleted_at is null
  ) then
    raise exception 'essa mensagem não é desta conversa';
  end if;
  update conversations set pinned_message_id = p_message
  where id = p_conversation;
end
$$;

-- Apagar a mensagem fixada tira ela do topo da conversa.
create or replace function public.delete_message(p_message uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'precisa estar logado'; end if;
  update messages
  set deleted_at = now(), body = null, reply_to = null,
      attachment_path = null, attachment_kind = null,
      attachment_width = null, attachment_height = null,
      mentions = '{}'
  where id = p_message and author_id = me
    and chamado_id is null and deleted_at is null;
  if not found then raise exception 'só dá para apagar a própria mensagem'; end if;
  delete from message_reactions where message_id = p_message;
  update messages set reply_to = null where reply_to = p_message;
  update conversations set pinned_message_id = null
  where pinned_message_id = p_message;
end
$$;

revoke execute on function public.pin_message(uuid, uuid) from public;
grant execute on function public.pin_message(uuid, uuid) to authenticated;
