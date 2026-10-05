-- Apagar e editar mensagem.
--
-- Editar troca o corpo e marca "(editado)". Apagar deixa uma lápide: a linha
-- fica (para não abrir buraco na conversa nem na contagem de novas), mas sem
-- texto, anexo nem reações, e some da citação de quem a respondeu.
--
-- As duas são ações SECURITY DEFINER que conferem o autor, como respond_chamado
-- e as outras — nada de UPDATE/DELETE direto na tabela pelo app.

alter table public.messages
  add column edited_at timestamptz,
  add column deleted_at timestamptz;

-- A regra de conteúdo passa a aceitar a mensagem apagada (sem texto nem anexo).
alter table public.messages drop constraint messages_conteudo;
alter table public.messages add constraint messages_conteudo check (
  case
    when deleted_at is not null then true
    when chamado_id is not null then body is null and attachment_path is null
    else body is not null or attachment_path is not null
  end
);

-- Editar: troca o corpo da própria mensagem de texto e a marca como editada.
create function public.edit_message(p_message uuid, p_body text) returns void
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  corpo text := btrim(p_body);
begin
  if me is null then raise exception 'precisa estar logado'; end if;
  if char_length(corpo) not between 1 and 4000 then
    raise exception 'mensagem vazia ou longa demais';
  end if;
  update messages
  set body = corpo, edited_at = now()
  where id = p_message and author_id = me
    and chamado_id is null and deleted_at is null;
  if not found then raise exception 'só dá para editar a própria mensagem'; end if;
end
$$;

-- Apagar: a própria mensagem vira lápide, e quem a citava perde a citação.
create function public.delete_message(p_message uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'precisa estar logado'; end if;
  update messages
  set deleted_at = now(), body = null, reply_to = null,
      attachment_path = null, attachment_kind = null,
      attachment_width = null, attachment_height = null
  where id = p_message and author_id = me
    and chamado_id is null and deleted_at is null;
  if not found then raise exception 'só dá para apagar a própria mensagem'; end if;
  delete from message_reactions where message_id = p_message;
  update messages set reply_to = null where reply_to = p_message;
end
$$;

-- As duas só para quem está logado.
revoke execute on function
  public.edit_message(uuid, text), public.delete_message(uuid) from public;
grant execute on function
  public.edit_message(uuid, text), public.delete_message(uuid) to authenticated;
