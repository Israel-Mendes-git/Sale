-- Testes das regras de acesso e das ações, rodados por tool/testar_banco.sh.
-- A e B dividem um grupo; C é de fora; D entra depois pelo convite.

\set ON_ERROR_STOP on
\set A '''aaaaaaaa-0000-0000-0000-000000000001'''
\set B '''bbbbbbbb-0000-0000-0000-000000000002'''
\set C '''cccccccc-0000-0000-0000-000000000003'''
\set D '''dddddddd-0000-0000-0000-000000000004'''

-- Utilitários (rodam com a permissão de quem chama).
create schema teste;
grant usage on schema teste to authenticated, anon;

create function teste.confere(cond boolean, descricao text) returns void
language plpgsql as $$
begin
  if cond is not true then raise exception 'FALHOU: %', descricao; end if;
  raise notice 'ok: %', descricao;
end $$;

create function teste.deve_falhar(comando text, descricao text) returns void
language plpgsql as $$
declare falhou boolean := false;
begin
  begin
    execute comando;
  exception when others then
    falhou := true;
  end;
  if not falhou then raise exception 'FALHOU (devia recusar): %', descricao; end if;
  raise notice 'ok (recusou): %', descricao;
end $$;

create function teste.conta(consulta text) returns bigint
language plpgsql as $$
declare n bigint;
begin
  execute 'select count(*) from (' || consulta || ') x' into n;
  return n;
end $$;

grant execute on all functions in schema teste to authenticated, anon;

-- ---------------------------------------------------------------------------
-- Perfis nascem com o login

insert into auth.users (id, raw_user_meta_data) values
  (:A, '{"full_name": "Fulano do Discord"}'),
  (:B, '{}'),
  (:C, '{"name": "Um nome comprido demais para caber aqui"}'),
  (:D, '{}');

select teste.confere((select count(*) from profiles) = 4, 'um perfil por login');
select teste.confere(
  (select name = 'Fulano do Discord' and not named from profiles where id = :A),
  'nome do provedor vira sugestão, não confirmado');
select teste.confere((select name from profiles where id = :B) = 'Sem nome', 'sem nome do provedor');
select teste.confere((select char_length(name) from profiles where id = :C) = 24, 'nome longo é cortado');

-- ---------------------------------------------------------------------------
-- Grupo e convite

set role authenticated;
select set_config('request.jwt.claim.sub', :A, false);
select create_group('Os 3') as grupo \gset
select invite_code as codigo from groups where id = :'grupo' \gset
select id as conversa from conversations where group_id = :'grupo' and kind = 'group' \gset

select set_config('request.jwt.claim.sub', :B, false);
select join_group(lower(:'codigo'));
select teste.confere(teste.conta('select 1 from groups') = 1, 'B entra pelo convite (sem diferenciar maiúsculas)');
select join_group(:'codigo');
select teste.confere(teste.conta('select 1 from group_members') = 2, 'entrar de novo não duplica');

select set_config('request.jwt.claim.sub', :C, false);
select teste.deve_falhar($$select join_group('XXXXXXXX')$$, 'código de convite errado');
select teste.confere(teste.conta('select 1 from groups') = 0, 'C não vê o grupo dos outros');
select teste.confere(teste.conta('select 1 from profiles') = 1, 'C só vê o próprio perfil');
select teste.confere(teste.conta('select 1 from conversations') = 0, 'C não vê as conversas');

-- C tem o próprio grupo (usado mais adiante).
select create_group('Outro grupo') as grupo_c \gset

-- ---------------------------------------------------------------------------
-- Perfil

select set_config('request.jwt.claim.sub', :B, false);
select teste.confere(teste.conta('select 1 from profiles') = 2, 'B vê o próprio perfil e o de A');
with u as (update profiles set name = 'Duda', named = true where id = :B returning 1)
  select teste.confere(count(*) = 1, 'B renomeia o próprio perfil') from u;
with u as (update profiles set name = 'Hackeado' where id = :A returning 1)
  select teste.confere(count(*) = 0, 'B não renomeia o perfil de A') from u;
select teste.deve_falhar(
  format($$update profiles set name = '   ' where id = %L$$, :B), 'nome em branco');

-- ---------------------------------------------------------------------------
-- Mensagens

select set_config('request.jwt.claim.sub', :A, false);
insert into messages (conversation_id, body) values (:'conversa', 'bora hoje?');
select teste.deve_falhar(
  format($$insert into messages (conversation_id, author_id, body) values (%L, %L, 'fingindo')$$,
         :'conversa', :B),
  'A não escreve em nome de B');

select set_config('request.jwt.claim.sub', :B, false);
select teste.confere(teste.conta('select 1 from messages') = 1, 'B lê a mensagem do grupo');

select set_config('request.jwt.claim.sub', :C, false);
select teste.confere(teste.conta('select 1 from messages') = 0, 'C não lê o grupo dos outros');
select teste.deve_falhar(
  format($$insert into messages (conversation_id, body) values (%L, 'intruso')$$, :'conversa'),
  'C não escreve no grupo dos outros');

-- ---------------------------------------------------------------------------
-- Conversa individual

select set_config('request.jwt.claim.sub', :A, false);
select open_direct(:B) as direta \gset
select teste.confere(open_direct(:B) = :'direta', 'conversa individual é reaproveitada');
select teste.deve_falhar(format('select open_direct(%L)', :C), 'não abre conversa com quem é de fora');
select teste.deve_falhar(format('select open_direct(%L)', :A), 'não abre conversa consigo mesmo');

-- ---------------------------------------------------------------------------
-- Respostas rápidas

select set_config('request.jwt.claim.sub', :B, false);
insert into quick_replies (owner_id, emoji, label, kind)
  values (:B, '🍝', 'Tô jantando', 'later') returning id as jantando \gset
select teste.confere((select asks_eta from quick_replies where id = :'jantando'),
  '"vou, mas depois" sem tempo pergunta o tempo');
select teste.confere(
  not (select asks_eta from quick_replies where label = 'Chego em 10 min'),
  'resposta com tempo embutido não pergunta');
select teste.deve_falhar(
  format($$insert into quick_replies (owner_id, emoji, label, kind) values (%L, '💤', 'x', 'snooze')$$, :B),
  'não cria outro "me chama depois"');
select teste.confere(teste.conta('select 1 from quick_replies') = 7, 'B vê as 6 comuns e a própria');

select set_config('request.jwt.claim.sub', :A, false);
select teste.confere(teste.conta('select 1 from quick_replies') = 6, 'A não vê as respostas de B');
select teste.deve_falhar(
  format($$insert into quick_replies (owner_id, emoji, label, kind) values (%L, '😈', 'x', 'no')$$, :B),
  'A não cria resposta em nome de B');
with d as (delete from quick_replies where owner_id is null returning 1)
  select teste.confere(count(*) = 0, 'ninguém apaga as respostas comuns') from d;
insert into quick_replies (owner_id, emoji, label, kind)
  values (:A, '💼', 'No trabalho', 'no') returning id as trabalho \gset

-- ---------------------------------------------------------------------------
-- Jogos

insert into games (group_id, name, min_players, max_players)
  values (:'grupo', 'Valorant', 1, 5) returning id as valorant \gset
insert into games (group_id, name, min_players, max_players)
  values (:'grupo', 'Counter-Strike 2', 1, 5) returning id as cs2 \gset
insert into games (group_id, name, min_players, max_players)
  values (:'grupo', 'Among Us', 4, 15) returning id as amongus \gset
select teste.confere(teste.conta(format(
  'select 1 from game_owners where user_id = %L', :A)) = 3, 'quem cadastra já tem o jogo');
select teste.deve_falhar(
  format($$insert into games (group_id, name, min_players, max_players) values (%L, 'valorant', 1, 5)$$, :'grupo'),
  'nome repetido (sem diferenciar maiúsculas)');
select teste.deve_falhar(
  format($$insert into games (group_id, name, min_players, max_players) values (%L, 'Xadrez', 3, 2)$$, :'grupo'),
  'faixa de jogadores invertida');

select set_config('request.jwt.claim.sub', :B, false);
insert into game_owners (game_id, user_id) values (:'valorant', :B);
select teste.deve_falhar(
  format($$insert into game_owners (game_id, user_id) values (%L, %L)$$, :'cs2', :A),
  'B não marca jogo em nome de A');

select set_config('request.jwt.claim.sub', :C, false);
select teste.confere(teste.conta('select 1 from games') = 0, 'C não vê a biblioteca dos outros');
select teste.deve_falhar(
  format($$insert into games (group_id, name, min_players, max_players) values (%L, 'Intruso', 1, 2)$$, :'grupo'),
  'C não cadastra jogo no grupo dos outros');
insert into games (group_id, name, min_players, max_players)
  values (:'grupo_c', 'Jogo do C', 1, 4) returning id as jogo_c \gset

-- ---------------------------------------------------------------------------
-- Chamado

select set_config('request.jwt.claim.sub', :A, false);

-- A e B: só o Valorant serve (Among Us pede 4; B não tem CS2).
do $$
declare ch uuid; nome text;
begin
  for i in 1..10 loop
    ch := send_chamado(
      (select id from conversations where kind = 'direct' limit 1),
      array['bbbbbbbb-0000-0000-0000-000000000002'::uuid], null, true);
    select game_name into nome from chamados where id = ch;
    perform teste.confere(nome = 'Valorant', 'sorteio só tira jogo que os dois têm (' || i || ')');
  end loop;
end $$;

select send_chamado(:'conversa', array[:B]::uuid[], :'cs2') as chamado \gset
select teste.confere(
  (select game_name = 'Counter-Strike 2' and not drawn from chamados where id = :'chamado'),
  'Chamado com jogo escolhido');
select teste.confere(teste.conta(format(
  'select 1 from messages where chamado_id = %L', :'chamado')) = 1, 'Chamado vira mensagem na conversa');
select teste.deve_falhar(
  format('select send_chamado(%L, array[%L]::uuid[], %L, true)', :'conversa', :B, :'cs2'),
  'jogo escolhido e sorteio ao mesmo tempo');
select teste.deve_falhar(
  format('select send_chamado(%L, array[%L]::uuid[], %L)', :'conversa', :B, :'jogo_c'),
  'jogo de outro grupo');
select teste.deve_falhar(
  format('select send_chamado(%L, array[%L]::uuid[])', :'conversa', :C),
  'chamar quem não está na conversa');
select teste.deve_falhar(
  format('select send_chamado(%L, array[%L]::uuid[])', :'conversa', :A),
  'Chamado só para si mesmo');
select teste.deve_falhar(
  format($$insert into messages (conversation_id, chamado_id) values (%L, %L)$$, :'conversa', :'chamado'),
  'mensagem de Chamado só pela ação');

select set_config('request.jwt.claim.sub', :C, false);
select teste.deve_falhar(
  format('select send_chamado(%L, array[%L]::uuid[])', :'conversa', :A),
  'C não dispara no grupo dos outros');
select teste.confere(teste.conta('select 1 from chamados') = 0, 'C não vê os Chamados dos outros');

-- Responder
select set_config('request.jwt.claim.sub', :B, false);
select teste.deve_falhar(
  format('select respond_chamado(%L, %L)', :'chamado', :'trabalho'),
  'B não usa a resposta pessoal de A');
select teste.deve_falhar(
  format('select respond_chamado(%L, %L, 9999)', :'chamado', :'jantando'),
  'tempo estimado absurdo');
select respond_chamado(:'chamado', :'jantando', 30);
select teste.confere(
  (select reply_label = 'Tô jantando' and eta_minutes = 30 from chamado_targets
   where chamado_id = :'chamado' and user_id = :B),
  'B responde com a própria resposta e o tempo');
select teste.confere((select status from chamados where id = :'chamado') = 'answered',
  'todos responderam: respondido');

select set_config('request.jwt.claim.sub', :A, false);
select teste.deve_falhar(
  format('select respond_chamado(%L, %L)', :'chamado', :'trabalho'),
  'quem chamou não responde o próprio Chamado');
update chamado_targets set reply_label = 'forjado' where chamado_id = :'chamado';
select teste.confere(
  (select reply_label from chamado_targets where chamado_id = :'chamado') = 'Tô jantando',
  'ninguém altera resposta direto na tabela');

-- Vetar: B passa a ter o CS2, então A e B têm Valorant e CS2.
select set_config('request.jwt.claim.sub', :B, false);
insert into game_owners (game_id, user_id) values (:'cs2', :B);

select set_config('request.jwt.claim.sub', :A, false);
select send_chamado(:'conversa', array[:B]::uuid[], null, true) as sorteado \gset
select game_id as primeiro from chamados where id = :'sorteado' \gset
select veto_game(:'sorteado');
select teste.confere(
  (select game_id is not null and game_id <> :'primeiro' from chamados where id = :'sorteado'),
  'o veto sorteia outro jogo');
select teste.deve_falhar(format('select veto_game(%L)', :'sorteado'), 'cada um veta uma vez');

select set_config('request.jwt.claim.sub', :C, false);
select teste.deve_falhar(format('select veto_game(%L)', :'sorteado'), 'quem é de fora não veta');

select set_config('request.jwt.claim.sub', :B, false);
select veto_game(:'sorteado');
select teste.confere(
  (select game_id is null and game_name is null from chamados where id = :'sorteado'),
  'vetaram tudo: fica "qualquer coisa"');
select teste.deve_falhar(format('select veto_game(%L)', :'chamado'), 'Chamado sem sorteio não tem veto');

-- Encerrar
select teste.deve_falhar(format('select close_chamado(%L)', :'sorteado'), 'só quem chamou encerra');
select set_config('request.jwt.claim.sub', :A, false);
select close_chamado(:'sorteado');
select teste.confere((select status from chamados where id = :'sorteado') = 'closed', 'quem chamou encerra');
select set_config('request.jwt.claim.sub', :B, false);
select respond_chamado(:'sorteado', :'jantando', 10);
select teste.confere(
  (select responded_at is null from chamado_targets where chamado_id = :'sorteado'),
  'Chamado encerrado não aceita resposta');

-- ---------------------------------------------------------------------------
-- Calendário

select set_config('request.jwt.claim.sub', :A, false);
insert into weekly_meetings (conversation_id, weekday, minute)
  values (:'conversa', 4, 1260) returning id as encontro \gset
select teste.deve_falhar(
  format('insert into weekly_meetings (conversation_id, weekday, minute) values (%L, 5, 1260)', :'conversa'),
  'um encontro fixo por grupo');
select teste.deve_falhar(
  format('insert into weekly_meetings (conversation_id, weekday, minute) values (%L, 5, 1260)', :'direta'),
  'encontro fixo só em grupo');
insert into meeting_exceptions (meeting_id, date, skipped) values (:'encontro', '2026-10-01', true);

select set_config('request.jwt.claim.sub', :B, false);
insert into meeting_rsvps (meeting_id, date, status) values (:'encontro', '2026-10-01', 'going');
select teste.deve_falhar(
  format($$insert into meeting_rsvps (meeting_id, date, user_id, status) values (%L, '2026-10-01', %L, 'going')$$,
         :'encontro', :A),
  'B não confirma em nome de A');
insert into availability (weekday, start_minute, end_minute) values (4, 1260, 1440);
select teste.deve_falhar(
  format('insert into availability (user_id, weekday, start_minute, end_minute) values (%L, 4, 0, 60)', :A),
  'B não marca horário em nome de A');
select teste.deve_falhar(
  'insert into availability (weekday, start_minute, end_minute) values (4, 600, 600)',
  'faixa vazia');
insert into device_tokens (token) values ('token-do-b');

select set_config('request.jwt.claim.sub', :A, false);
select teste.confere(teste.conta('select 1 from meeting_rsvps') = 1, 'A vê a confirmação de B');
select teste.confere(teste.conta('select 1 from availability') = 1, 'A vê os horários de B');
select teste.confere(teste.conta('select 1 from device_tokens') = 0, 'A não vê os aparelhos de B');

select set_config('request.jwt.claim.sub', :C, false);
select teste.confere(teste.conta('select 1 from weekly_meetings') = 0, 'C não vê o encontro dos outros');
select teste.confere(teste.conta('select 1 from meeting_rsvps') = 0, 'C não vê as confirmações');
select teste.confere(teste.conta('select 1 from availability') = 0, 'C não vê os horários dos outros');
select teste.deve_falhar(
  format($$insert into meeting_exceptions (meeting_id, date, skipped) values (%L, '2026-10-08', true)$$, :'encontro'),
  'C não mexe no encontro dos outros');

-- ---------------------------------------------------------------------------
-- Quem entra depois

select set_config('request.jwt.claim.sub', :D, false);
select join_group(:'codigo');
select teste.confere(teste.conta('select 1 from conversations') = 1, 'D entra na conversa do grupo');
select teste.confere(teste.conta('select 1 from games') = 3, 'D vê a biblioteca do grupo');
select teste.confere(teste.conta(format(
  'select 1 from conversations where id = %L', :'direta')) = 0, 'D não vê a conversa individual de A e B');

-- ---------------------------------------------------------------------------
-- Chegada (placar do atraso)
--
-- Com D no grupo, o Chamado para B e D continua aberto depois de só B
-- responder — é isso que deixa testar a resposta trocada.

select id as chego10 from quick_replies where owner_id is null and label = 'Chego em 10 min' \gset
select id as hojenao from quick_replies where owner_id is null and label = 'Hoje não' \gset

select set_config('request.jwt.claim.sub', :A, false);
select send_chamado(:'conversa', array[:B, :D]::uuid[]) as atraso \gset

select set_config('request.jwt.claim.sub', :B, false);
select teste.deve_falhar(format('select arrive_chamado(%L)', :'atraso'),
  'quem não respondeu não marca chegada');
select respond_chamado(:'atraso', :'chego10');
select arrive_chamado(:'atraso');
select teste.confere(
  (select arrived_at is not null from chamado_targets
   where chamado_id = :'atraso' and user_id = :B),
  'quem prometeu marca que chegou');
select teste.deve_falhar(format('select arrive_chamado(%L)', :'atraso'),
  'a chegada é marcada uma vez só');

-- Responder de novo recomeça a promessa, então a chegada antiga cai.
select respond_chamado(:'atraso', :'chego10');
select teste.confere(
  (select arrived_at is null from chamado_targets
   where chamado_id = :'atraso' and user_id = :B),
  'resposta nova apaga a chegada antiga');
select arrive_chamado(:'atraso');

select set_config('request.jwt.claim.sub', :D, false);
select respond_chamado(:'atraso', :'hojenao');
select teste.deve_falhar(format('select arrive_chamado(%L)', :'atraso'),
  'quem disse que não vinha não marca chegada');

select set_config('request.jwt.claim.sub', :A, false);
select teste.deve_falhar(format('select arrive_chamado(%L)', :'atraso'),
  'quem chamou não marca chegada');
select teste.deve_falhar(format('select arrive_chamado(%L)', :'sorteado'),
  'Chamado encerrado não aceita chegada');
update chamado_targets set arrived_at = now()
  where chamado_id = :'atraso' and user_id = :D;
select teste.confere(
  (select arrived_at is null from chamado_targets
   where chamado_id = :'atraso' and user_id = :D),
  'ninguém marca chegada direto na tabela');

select set_config('request.jwt.claim.sub', :C, false);
select teste.deve_falhar(format('select arrive_chamado(%L)', :'atraso'),
  'quem é de fora não marca chegada');

-- ---------------------------------------------------------------------------
-- Sem login

reset role;
set role anon;
select teste.deve_falhar('select * from messages', 'sem login não lê mensagens');
select teste.deve_falhar(
  format('select send_chamado(%L, array[%L]::uuid[])', :'conversa', :B),
  'sem login não dispara Chamado');
reset role;

\echo 'TODOS OS TESTES DO BANCO PASSARAM'
