-- Ajustar quantos jogam um jogo da biblioteca. Até aqui a faixa só era
-- escolhida ao cadastrar, e o jogo trazido da Steam entrava com 1 a 10 (a
-- Steam não diz o máximo). Qualquer um do grupo ajusta, como qualquer um
-- cadastra e remove.
--
-- Pela função, e não por uma regra de update na tabela: assim só a faixa
-- muda, e o nome, o grupo e quem cadastrou ficam como estão.

create function public.ajustar_jogadores(p_jogo uuid, p_min integer, p_max integer)
returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'precisa estar logado'; end if;
  if not exists (
    select 1 from games where id = p_jogo and is_group_member(group_id)
  ) then
    raise exception 'esse jogo não é do seu grupo';
  end if;
  -- A faixa invertida ou fora do limite esbarra nos checks da tabela.
  update games set min_players = p_min, max_players = p_max where id = p_jogo;
end
$$;

revoke execute on function public.ajustar_jogadores(uuid, integer, integer)
  from public, anon;
grant execute on function public.ajustar_jogadores(uuid, integer, integer)
  to authenticated;

create or replace function public.versao_do_esquema() returns text
language sql immutable set search_path = public as $$ select '20261009000000' $$;
