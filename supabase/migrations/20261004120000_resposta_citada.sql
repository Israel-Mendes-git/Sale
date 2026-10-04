-- Resposta citada: em grupo de três conversando ao mesmo tempo, "não dá" não
-- diz a que pergunta.
--
-- A mensagem aponta para a que ela responde, e só para uma da mesma conversa:
-- citação atravessando conversa seria um jeito de ler o que não é seu.
--
-- Mensagem citada que for apagada não leva a resposta com ela (`set null`): o
-- que foi escrito continua, sem a citação em cima.

alter table public.messages
  add column reply_to uuid references public.messages (id) on delete set null;

create index messages_por_citada on public.messages (reply_to)
  where reply_to is not null;

drop policy "manda mensagem em nome próprio" on public.messages;
create policy "manda mensagem em nome próprio" on public.messages
  for insert with check (
    author_id = auth.uid() and chamado_id is null and
    is_conversation_member(conversation_id) and
    (
      reply_to is null or exists (
        -- As duas referências à linha nova precisam do nome da tabela: dentro
        -- da subconsulta, `reply_to` sozinho seria a coluna da citada, e a
        -- citada não responde a si mesma.
        select 1 from messages citada
        where citada.id = messages.reply_to
          and citada.conversation_id = messages.conversation_id
      )
    )
  );
