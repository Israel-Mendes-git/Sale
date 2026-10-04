-- Entregue e lido no chat: as duas marquinhas da mensagem.
--
-- Até agora a mensagem saía e ninguém sabia se chegou. Em vez de uma linha
-- por mensagem e pessoa, cada membro da conversa guarda duas datas — até onde
-- recebeu e até onde viu — e cada mensagem se compara com elas. Com isso a
-- conta de mensagens novas também é uma comparação de datas, em vez de uma
-- tabela crescendo a cada mensagem lida.
--
-- Entregue é o aparelho conectado: texto não manda push, então a mensagem
-- chega quando o app da pessoa está aberto, e é esse instante que fica
-- registrado. Lido é a conversa aberta na tela.

alter table public.conversation_members
  add column delivered_until timestamptz,
  add column read_until timestamptz;

-- Marca que tudo o que já estava no servidor chegou neste aparelho. Vale para
-- todas as conversas de uma vez: o app está aberto, o tempo real entregou.
--
-- As datas só andam para a frente — `greatest` ignora nulo, então a primeira
-- vez também vale. Marca as próprias e só as próprias: `auth.uid()` vem do
-- token do pedido, e ninguém diz que leu pela outra pessoa.
create function public.mark_delivered() returns void
language sql security definer set search_path = public as $$
  update conversation_members
  set delivered_until = greatest(delivered_until, now())
  where user_id = auth.uid()
$$;

-- Marca que a pessoa abriu a conversa e viu as mensagens até agora. Quem viu
-- também recebeu, então o lido empurra o entregue junto: senão a mensagem
-- lida ficaria com uma marquinha só.
create function public.mark_read(p_conversation uuid) returns void
language sql security definer set search_path = public as $$
  update conversation_members
  set read_until = greatest(read_until, now()),
      delivered_until = greatest(delivered_until, now())
  where conversation_id = p_conversation and user_id = auth.uid()
$$;

-- As duas só para quem está logado.
revoke execute on function
  public.mark_delivered(), public.mark_read(uuid) from public;
grant execute on function
  public.mark_delivered(), public.mark_read(uuid) to authenticated;
