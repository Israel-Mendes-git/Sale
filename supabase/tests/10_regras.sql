-- Testes das regras de acesso e das ações, rodados por tool/testar_banco.sh.
-- A e B dividem um grupo; C é de fora; D entra depois pelo convite.

\set ON_ERROR_STOP on
\set A '''aaaaaaaa-0000-0000-0000-000000000001'''
\set B '''bbbbbbbb-0000-0000-0000-000000000002'''
\set C '''cccccccc-0000-0000-0000-000000000003'''
\set D '''dddddddd-0000-0000-0000-000000000004'''

-- Utilitários (rodam com a permissão de quem chama).
create schema teste;
grant usage on schema teste to authenticated, anon, service_role;

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

grant execute on all functions in schema teste to authenticated, anon, service_role;

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
-- Disparo automático (encontro fixo e Chamado marcado para depois)
--
-- A função recebe a hora de propósito: assim o teste viaja no tempo em vez
-- de esperar a quinta-feira chegar. 01/10/2026 é quinta, o dia do encontro.

reset role;
set role service_role;

-- A seção do calendário deixou essa quinta marcada como pulada.
select teste.confere(
  teste.conta($$select 1 from disparar_pendentes('2026-10-01 21:00-03')$$) = 0,
  'semana pulada não dispara');

delete from meeting_exceptions where meeting_id = :'encontro' and date = '2026-10-01';
select teste.confere(
  teste.conta($$select 1 from disparar_pendentes('2026-10-01 20:59-03')$$) = 0,
  'um minuto antes da hora ainda não dispara');

select chamado_id as automatico from disparar_pendentes('2026-10-01 21:00-03') \gset
select teste.confere(
  (select automatic and fired_at is not null and author_id = :A
   from chamados where id = :'automatico'),
  'o encontro fixo vira Chamado automático, em nome de quem criou o grupo');
select teste.confere(
  teste.conta(format('select 1 from chamado_targets where chamado_id = %L', :'automatico')) = 3,
  'chama todo mundo da conversa, inclusive quem criou o grupo');
select teste.confere(
  teste.conta(format('select 1 from messages where chamado_id = %L', :'automatico')) = 1,
  'o Chamado automático também vira mensagem na conversa');
select teste.confere(
  teste.conta($$select 1 from disparar_pendentes('2026-10-01 21:05-03')
                where motivo = 'encontro'$$) = 0,
  'a mesma ocorrência não dispara duas vezes');

delete from meeting_fires;
select teste.confere(
  teste.conta($$select 1 from disparar_pendentes('2026-10-01 21:20-03')$$) = 0,
  'disparo atrasado demais não acorda o grupo');

-- Exceção que só muda o horário daquela semana.
insert into meeting_exceptions (meeting_id, date, minute) values (:'encontro', '2026-10-01', 1380);
select teste.confere(
  teste.conta($$select 1 from disparar_pendentes('2026-10-01 21:00-03')$$) = 0,
  'horário trocado: 21h deixou de ser a hora');
select teste.confere(
  teste.conta($$select 1 from disparar_pendentes('2026-10-01 23:00-03')$$) = 1,
  'dispara no horário trocado da semana');

-- Chamado marcado para depois.
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :A, false);
select send_chamado(:'conversa', array[:B]::uuid[], null, false, null,
                    '2026-10-01 22:00-03') as marcado \gset
select send_chamado(:'conversa', array[:B]::uuid[], null, false, null,
                    '2026-10-01 10:00-03') as esquecido \gset

reset role;
set role service_role;
select teste.confere(
  teste.conta($$select 1 from disparar_pendentes('2026-10-01 21:50-03')$$) = 0,
  'Chamado marcado para depois ainda não venceu');
select teste.confere(
  teste.conta($$select 1 from disparar_pendentes('2026-10-01 22:00-03')$$) = 1,
  'na hora marcada, o Chamado sai para o push');
select teste.confere(
  teste.conta($$select 1 from disparar_pendentes('2026-10-01 22:01-03')$$) = 0,
  'e não sai de novo na rodada seguinte');
select teste.confere(
  (select fired_at is not null from chamados where id = :'esquecido'),
  'o marcado e esquecido fica anotado, para não voltar toda rodada');

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :A, false);
select teste.deve_falhar($$select disparar_pendentes()$$,
  'quem está logado no app não dispara o cron');

-- ---------------------------------------------------------------------------
-- Soneca e insistência (o Chamado tocando de novo)
--
-- Os dois andam pelo relógio, então aqui a hora também entra de propósito:
-- `now() + 5 minutes` é o cron rodando cinco minutos depois do Chamado.

reset role;
set role authenticated;
select id as soneca from quick_replies where kind = 'snooze' \gset
select id as bora from quick_replies where owner_id is null and label = 'Bora!' \gset
select teste.confere((select asks_eta from quick_replies where id = :'soneca'),
  '"me chama daqui a pouco" pergunta daqui a quanto');

-- Insistência: A chama B e D, e só B responde.
select set_config('request.jwt.claim.sub', :A, false);
select send_chamado(:'conversa', array[:B, :D]::uuid[]) as calado \gset
select set_config('request.jwt.claim.sub', :B, false);
select respond_chamado(:'calado', :'bora');

reset role;
set role service_role;
select teste.confere(
  teste.conta(format($$select 1 from disparar_pendentes(now() + interval '4 minutes')
                       where chamado_id = %L$$, :'calado')) = 0,
  'quatro minutos de silêncio ainda não insistem');
select teste.confere(
  (select alvos = array[:D]::uuid[] and motivo = 'insistencia'
   from disparar_pendentes(now() + interval '5 minutes')
   where chamado_id = :'calado'),
  'a insistência toca de novo só para quem não respondeu');
select teste.confere(
  (select nudged_at is not null from chamados where id = :'calado'),
  'o Chamado anota que tocou de novo');
select teste.confere(
  teste.conta(format($$select 1 from disparar_pendentes(now() + interval '6 minutes')
                       where chamado_id = %L$$, :'calado')) = 0,
  'e insiste uma vez só');
select teste.confere(
  teste.conta($$select 1 from disparar_pendentes('2026-10-01 21:55-03')$$) = 0,
  'o Chamado que o cron poupou por atraso não volta pela insistência');

-- Soneca: B pede para ser chamado de novo em 20 minutos.
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :A, false);
select send_chamado(:'conversa', array[:B]::uuid[]) as sonecado \gset
select set_config('request.jwt.claim.sub', :B, false);
select respond_chamado(:'sonecado', :'soneca', 20);
select teste.confere(
  (select snoozed_until between now() + interval '19 minutes'
                            and now() + interval '21 minutes'
   from chamado_targets where chamado_id = :'sonecado' and user_id = :B),
  'a soneca marca a volta na hora pedida');
select teste.confere(
  (select status from chamados where id = :'sonecado') = 'answered',
  'quem pede soneca já respondeu: o Chamado não fica esperando');

reset role;
set role service_role;
select teste.confere(
  teste.conta(format($$select 1 from disparar_pendentes(now() + interval '19 minutes')
                       where chamado_id = %L$$, :'sonecado')) = 0,
  'antes da hora a soneca não acorda ninguém');
select teste.confere(
  (select alvos = array[:B]::uuid[] and motivo = 'soneca'
   from disparar_pendentes(now() + interval '20 minutes')
   where chamado_id = :'sonecado'),
  'na hora pedida, o Chamado volta só para quem pediu');
select teste.confere(
  (select responded_at is null and reply_label is null and snoozed_until is null
   from chamado_targets where chamado_id = :'sonecado' and user_id = :B),
  'a resposta cai e a pessoa volta para a fila de quem não respondeu');
select teste.confere(
  (select status from chamados where id = :'sonecado') = 'open',
  'e o Chamado torna a esperar resposta');
select teste.confere(
  teste.conta(format($$select 1 from disparar_pendentes(now() + interval '21 minutes')
                       where chamado_id = %L$$, :'sonecado')) = 0,
  'a mesma soneca não acorda duas vezes');

-- Soneca que venceu tarde demais: cai sem tocar, como o encontro atrasado.
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :B, false);
select respond_chamado(:'sonecado', :'soneca', 20);
reset role;
set role service_role;
select teste.confere(
  teste.conta(format($$select 1 from disparar_pendentes(now() + interval '40 minutes')
                       where chamado_id = %L$$, :'sonecado')) = 0,
  'soneca atrasada demais não acorda ninguém de madrugada');
select teste.confere(
  (select snoozed_until is null and reply_kind = 'snooze'
   from chamado_targets where chamado_id = :'sonecado' and user_id = :B),
  'a soneca cai, e a resposta continua no card');

-- Mudar de ideia depois da soneca, e o Chamado encerrado no meio dela.
reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :A, false);
select send_chamado(:'conversa', array[:B, :D]::uuid[]) as desistiu \gset
select set_config('request.jwt.claim.sub', :B, false);
select respond_chamado(:'desistiu', :'soneca', 10);
select respond_chamado(:'desistiu', :'bora');
select teste.confere(
  (select snoozed_until is null and reply_kind = 'yes'
   from chamado_targets where chamado_id = :'desistiu' and user_id = :B),
  'quem desiste da soneca não é chamado de novo');

select set_config('request.jwt.claim.sub', :A, false);
select send_chamado(:'conversa', array[:B, :D]::uuid[]) as encerrado \gset
select set_config('request.jwt.claim.sub', :D, false);
select respond_chamado(:'encerrado', :'soneca', 10);
select set_config('request.jwt.claim.sub', :A, false);
select close_chamado(:'encerrado');
reset role;
set role service_role;
select teste.confere(
  teste.conta(format($$select 1 from disparar_pendentes(now() + interval '10 minutes')
                       where chamado_id = %L$$, :'encerrado')) = 0,
  'Chamado encerrado não acorda quem pediu soneca');
select teste.confere(
  (select snoozed_until is null from chamado_targets
   where chamado_id = :'encerrado' and user_id = :D),
  'e a soneca do Chamado encerrado cai');

-- ---------------------------------------------------------------------------
-- Lembrete do encontro fixo
--
-- A seção do disparo deixou esta quinta com o horário trocado para 23h, então
-- o lembrete dela vence às 21h.

reset role;
set role service_role;
select teste.confere(
  teste.conta($$select 1 from lembretes_pendentes('2026-10-01 20:59-03')$$) = 0,
  'um minuto antes do lembrete, ninguém é avisado');
select teste.confere(
  (select hora = '2026-10-01 23:00-03'::timestamptz
   from lembretes_pendentes('2026-10-01 21:00-03')),
  'o lembrete sai duas horas antes, no horário trocado da semana');
select teste.confere(
  teste.conta($$select 1 from lembretes_pendentes('2026-10-01 21:05-03')$$) = 0,
  'o mesmo lembrete não sai duas vezes');
select teste.confere(
  (select date = '2026-10-01' from meeting_reminders
   where meeting_id = :'encontro'),
  'a ocorrência avisada fica anotada');

-- De volta ao horário de sempre: encontro às 21h, lembrete às 19h. Só B
-- confirmou presença, na seção do calendário.
delete from meeting_exceptions where meeting_id = :'encontro' and date = '2026-10-01';
delete from meeting_reminders;
select teste.confere(
  (select alvos @> array[:A, :D]::uuid[] and array_length(alvos, 1) = 2
   from lembretes_pendentes('2026-10-01 19:00-03')),
  'lembra só quem ainda não confirmou presença');

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :A, false);
select teste.confere(teste.conta('select 1 from meeting_reminders') = 1,
  'o grupo vê o lembrete do próprio encontro');
select teste.deve_falhar($$select lembretes_pendentes()$$,
  'quem está logado no app não manda lembrete');
select set_config('request.jwt.claim.sub', :C, false);
select teste.confere(teste.conta('select 1 from meeting_reminders') = 0,
  'C não vê os lembretes do encontro dos outros');

reset role;
set role service_role;
delete from meeting_reminders;
select teste.confere(
  teste.conta($$select 1 from lembretes_pendentes('2026-10-01 19:20-03')$$) = 0,
  'lembrete atrasado demais não vale: avisar tarde só confunde');

-- Com todo mundo confirmado não há o que lembrar.
delete from meeting_reminders;
insert into meeting_rsvps (meeting_id, date, user_id, status) values
  (:'encontro', '2026-10-01', :A, 'maybe'),
  (:'encontro', '2026-10-01', :D, 'not_going');
select teste.confere(
  teste.conta($$select 1 from lembretes_pendentes('2026-10-01 19:00-03')$$) = 0,
  'com todo mundo confirmado, não sai lembrete');
delete from meeting_rsvps
  where meeting_id = :'encontro' and user_id in (:A, :D);

-- Semana pulada.
delete from meeting_reminders;
insert into meeting_exceptions (meeting_id, date, skipped)
  values (:'encontro', '2026-10-01', true);
select teste.confere(
  teste.conta($$select 1 from lembretes_pendentes('2026-10-01 19:00-03')$$) = 0,
  'semana pulada não lembra ninguém');
delete from meeting_exceptions where meeting_id = :'encontro' and date = '2026-10-01';

-- ---------------------------------------------------------------------------
-- Expiração do Chamado

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :A, false);
select send_chamado(:'conversa', array[:B]::uuid[]) as largado \gset
select send_chamado(:'conversa', array[:B]::uuid[]) as respondido \gset
select set_config('request.jwt.claim.sub', :B, false);
select respond_chamado(:'respondido', :'bora');

reset role;
set role service_role;
select expirar_chamados(now() + interval '1 hour 59 minutes');
select teste.confere(
  (select status = 'open' from chamados where id = :'largado'),
  'antes das duas horas, o Chamado continua aberto');
select teste.confere(
  expirar_chamados(now() + interval '2 hours') >= 1,
  'duas horas depois do toque, o Chamado expira');
select teste.confere(
  (select status = 'closed' and expired_at is not null
   from chamados where id = :'largado'),
  'o Chamado expirado fica fechado, e anotado como expirado');
select teste.confere(
  (select status = 'answered' and expired_at is null
   from chamados where id = :'respondido'),
  'Chamado respondido não expira: fica de registro');
select teste.confere(
  (select expired_at is null from chamados where id = :'encerrado'),
  'quem chamou encerrou não é a mesma coisa que expirar');
select teste.confere(
  expirar_chamados(now() + interval '3 hours') = 0,
  'e não expira duas vezes');

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :B, false);
select respond_chamado(:'largado', :'bora');
select teste.confere(
  (select responded_at is null from chamado_targets
   where chamado_id = :'largado' and user_id = :B),
  'Chamado expirado não aceita mais resposta');
select teste.deve_falhar($$select expirar_chamados()$$,
  'quem está logado no app não fecha Chamado pelo relógio');

-- O marcado que o cron poupou por atraso conta do horário marcado: sem isso
-- ficaria aberto para sempre, esperando resposta de quem nunca foi avisado.
reset role;
set role service_role;
select teste.confere(
  (select status = 'closed' and expired_at is not null
   from chamados where id = :'esquecido'),
  'o marcado e esquecido também sai do caminho');

-- ---------------------------------------------------------------------------
-- Som do Chamado

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :A, false);
select teste.confere(
  teste.conta($$select 1 from sounds where group_id is null$$) = 5,
  'os cinco sons que vêm no app aparecem para quem está logado');
select id as sirene from sounds where group_id is null and file = 'sirene' \gset

-- Som do grupo: quem está nele sobe, e todo mundo do grupo enxerga.
insert into sounds (group_id, name, file)
values (:'grupo', 'Buzina', :'grupo' || '/buzina.ogg') returning id as buzina \gset
select teste.confere(teste.conta($$select 1 from sounds$$) = 6,
  'A vê os sons do app mais o do grupo');

select set_config('request.jwt.claim.sub', :B, false);
select teste.confere(teste.conta($$select 1 from sounds$$) = 6,
  'B, do mesmo grupo, vê o som que A subiu');

select set_config('request.jwt.claim.sub', :C, false);
select teste.confere(teste.conta($$select 1 from sounds$$) = 5,
  'C vê só os sons do app');
select teste.deve_falhar(
  format($$insert into sounds (group_id, name, file)
           values (%L, 'Intruso', 'x.ogg')$$, :'grupo'),
  'C não cadastra som no grupo dos outros');

-- Som do app ninguém cadastra nem apaga: ele vem dentro do APK.
select set_config('request.jwt.claim.sub', :A, false);
select teste.deve_falhar(
  $$insert into sounds (name, file) values ('Falso', 'falso')$$,
  'ninguém cadastra som do app');
with d as (delete from sounds where group_id is null returning 1)
  select teste.confere(count(*) = 0, 'nem apaga os que vêm nele') from d;
select teste.deve_falhar(
  format($$insert into sounds (group_id, name, file)
           values (%L, 'buzina', 'outro.ogg')$$, :'grupo'),
  'nome de som repetido no grupo (nem trocando a caixa)');

-- Disparar escolhendo o som: o Chamado guarda a chave com que o app toca —
-- o nome do arquivo, no som do app, e o id, no som do grupo.
select send_chamado(:'conversa', array[:B]::uuid[], null, false, null, null,
                    :'sirene') as com_sirene \gset
select teste.confere(
  (select sound_key = 'sirene' from chamados where id = :'com_sirene'),
  'som do app vai pelo nome do arquivo');
select send_chamado(:'conversa', array[:B]::uuid[], null, false, null, null,
                    :'buzina') as com_buzina \gset
select teste.confere(
  (select sound_key = :'buzina' from chamados where id = :'com_buzina'),
  'som do grupo vai pelo id');
select teste.confere(
  (select sound_key is null from chamados where id = :'chamado'),
  'quem não escolheu som fica com o da marca');

-- Som de outro grupo não toca aqui.
select set_config('request.jwt.claim.sub', :C, false);
insert into sounds (group_id, name, file)
values (:'grupo_c', 'Som do C', :'grupo_c' || '/c.ogg') returning id as som_c \gset
select set_config('request.jwt.claim.sub', :A, false);
select teste.deve_falhar(
  format('select send_chamado(%L, array[%L]::uuid[], null, false, null, null, %L)',
         :'conversa', :B, :'som_c'),
  'som de outro grupo');

-- Som apagado sai do perfil de quem o usava, mas não muda o que já tocou.
update profiles set sound_id = :'buzina' where id = :A;
delete from sounds where id = :'buzina';
select teste.confere(
  (select sound_id is null from profiles where id = :A),
  'som apagado sai do perfil de quem o tinha');
select teste.confere(
  (select sound_key = :'buzina' from chamados where id = :'com_buzina'),
  'e o Chamado guarda a chave do som que tocou nele');

-- A primeira pasta do arquivo é o grupo: é dela que sai a regra de acesso aos
-- arquivos no Storage.
select teste.confere(
  uuid_da_pasta(:'grupo' || '/buzina.ogg') = :'grupo'::uuid,
  'o caminho do arquivo diz de que grupo ele é');
select teste.confere(
  uuid_da_pasta('buzina.ogg') is null,
  'caminho sem pasta não dá acesso a nada');

-- ---------------------------------------------------------------------------
-- Entregue e lido (as marquinhas da mensagem)

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :A, false);
select mark_read(:'conversa');
select teste.confere(
  (select read_until is not null and delivered_until is not null
   from conversation_members
   where conversation_id = :'conversa' and user_id = :A),
  'quem abre a conversa marca lido, e o lido traz o entregue junto');
select teste.confere(
  (select read_until is null from conversation_members
   where conversation_id = :'conversa' and user_id = :B),
  'e marca só a própria linha');
select teste.confere(
  (select read_until is null from conversation_members
   where conversation_id = :'direta' and user_id = :A),
  'uma conversa não marca a outra');

-- O ponteiro só anda para a frente: relógio do servidor atrasado, pedido
-- repetido fora de ordem ou tela reaberta não desmarcam o que já foi visto.
reset role;
update conversation_members set read_until = now() + interval '1 hour'
where conversation_id = :'conversa' and user_id = :A;
set role authenticated;
select set_config('request.jwt.claim.sub', :A, false);
select mark_read(:'conversa');
select teste.confere(
  (select read_until > now() from conversation_members
   where conversation_id = :'conversa' and user_id = :A),
  'marcar de novo não volta o lido no tempo');

-- Entregue vale para todas as conversas de uma vez: o app abriu, o tempo
-- real entregou o que estava lá.
select set_config('request.jwt.claim.sub', :B, false);
select mark_delivered();
select teste.confere(
  teste.conta(format($$select 1 from conversation_members
    where user_id = %L and delivered_until is not null$$, :B)) = 2,
  'B recebe nas duas conversas de que participa');
select teste.confere(
  (select read_until is null from conversation_members
   where conversation_id = :'conversa' and user_id = :B),
  'receber não é ler');
select teste.confere(
  (select delivered_until is null from conversation_members
   where conversation_id = :'conversa' and user_id = :D),
  'e não entrega pelos outros');

-- Quem é de fora chama as mesmas funções e não acontece nada: elas mexem só
-- na linha de quem chamou. (A conferência é fora do papel de C, que não vê a
-- conversa dos outros nem para checar.)
select set_config('request.jwt.claim.sub', :C, false);
select mark_read(:'conversa');
select mark_delivered();
reset role;
select teste.confere(
  teste.conta(format($$select 1 from conversation_members
    where conversation_id = %L and user_id = %L$$, :'conversa', :C)) = 0,
  'marcar leitura não põe quem é de fora na conversa');
select teste.confere(
  teste.conta(format($$select 1 from conversation_members
    where user_id = %L and delivered_until is not null$$, :C)) = 1,
  'o entregue de C vale só para a conversa do grupo dele');

-- Quem está na conversa vê a marca dos outros: é dela que sai o segundo
-- tique de quem escreveu.
set role authenticated;
select set_config('request.jwt.claim.sub', :B, false);
select teste.confere(
  (select read_until is not null from conversation_members
   where conversation_id = :'conversa' and user_id = :A),
  'B vê até onde A leu');

-- ---------------------------------------------------------------------------
-- Imagem na conversa

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :A, false);

insert into messages (conversation_id, attachment_path, attachment_kind,
                      attachment_width, attachment_height)
values (:'conversa', :'conversa' || '/print.jpg', 'image', 1080, 1920);
select teste.confere(
  teste.conta(format($$select 1 from messages
    where conversation_id = %L and attachment_kind = 'image'$$,
    :'conversa')) = 1,
  'imagem sem legenda é mensagem válida');

insert into messages (conversation_id, body, attachment_path, attachment_kind)
values (:'conversa', 'olha essa jogada', :'conversa' || '/jogada.jpg', 'image');
select teste.confere(
  teste.conta(format($$select 1 from messages
    where conversation_id = %L and body = 'olha essa jogada'
      and attachment_path is not null$$, :'conversa')) = 1,
  'imagem com legenda também');

select teste.deve_falhar(
  format($$insert into messages (conversation_id) values (%L)$$, :'conversa'),
  'mensagem sem texto e sem anexo');
select teste.deve_falhar(
  format($$insert into messages (conversation_id, attachment_path)
           values (%L, 'x.jpg')$$, :'conversa'),
  'anexo sem tipo');
select teste.deve_falhar(
  format($$insert into messages (conversation_id, attachment_kind)
           values (%L, 'image')$$, :'conversa'),
  'tipo sem anexo');
select teste.deve_falhar(
  format($$insert into messages (conversation_id, attachment_path,
                                 attachment_kind, attachment_width)
           values (%L, 'x.jpg', 'image', 0)$$, :'conversa'),
  'imagem de largura zero');

select set_config('request.jwt.claim.sub', :C, false);
select teste.deve_falhar(
  format($$insert into messages (conversation_id, attachment_path,
                                 attachment_kind)
           values (%L, 'intruso.jpg', 'image')$$, :'conversa'),
  'C não manda imagem na conversa dos outros');

-- A pasta do anexo é a conversa, como a do som é o grupo.
select set_config('request.jwt.claim.sub', :A, false);
select teste.confere(
  uuid_da_pasta(:'conversa' || '/print.jpg') = :'conversa'::uuid,
  'o caminho do anexo diz de que conversa ele é');

-- ---------------------------------------------------------------------------
-- Resposta citada

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :A, false);
insert into messages (conversation_id, body) values (:'conversa', 'quem vem?')
returning id as pergunta \gset

select set_config('request.jwt.claim.sub', :B, false);
insert into messages (conversation_id, body, reply_to)
values (:'conversa', 'eu', :'pergunta');
select teste.confere(
  teste.conta(format($$select 1 from messages
    where reply_to = %L and body = 'eu'$$, :'pergunta')) = 1,
  'a resposta aponta para a mensagem citada');

-- A citada tem de ser da mesma conversa: citar de fora seria um jeito de ler
-- o que não é seu.
select set_config('request.jwt.claim.sub', :A, false);
insert into messages (conversation_id, body) values (:'direta', 'só nós dois')
returning id as reservada \gset
select teste.deve_falhar(
  format($$insert into messages (conversation_id, body, reply_to)
           values (%L, 'citando de fora', %L)$$, :'conversa', :'reservada'),
  'citação de outra conversa');
select teste.deve_falhar(
  format($$insert into messages (conversation_id, body, reply_to)
           values (%L, 'citando o nada', %L)$$, :'conversa',
         '00000000-0000-0000-0000-000000000000'),
  'citação de mensagem que não existe');

-- Apagar a citada não leva a resposta com ela.
reset role;
delete from messages where id = :'pergunta';
set role authenticated;
select set_config('request.jwt.claim.sub', :B, false);
select teste.confere(
  (select reply_to is null from messages
   where conversation_id = :'conversa' and body = 'eu'),
  'resposta sem a citada fica, só sem a citação');

-- ---------------------------------------------------------------------------
-- Reação na mensagem

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :A, false);
insert into messages (conversation_id, body) values (:'conversa', 'ganhei')
returning id as vitoria \gset

select set_config('request.jwt.claim.sub', :B, false);
insert into message_reactions (message_id, emoji) values (:'vitoria', '🔥');
select teste.confere(
  teste.conta(format($$select 1 from message_reactions
    where message_id = %L and emoji = '🔥'$$, :'vitoria')) = 1,
  'B reage à mensagem de A');

-- Uma por pessoa: a segunda troca a primeira, não empilha.
select teste.deve_falhar(
  format($$insert into message_reactions (message_id, emoji)
           values (%L, '👍')$$, :'vitoria'),
  'duas reações da mesma pessoa na mesma mensagem');
update message_reactions set emoji = '👍'
where message_id = :'vitoria' and user_id = :B;
select teste.confere(
  (select emoji from message_reactions
   where message_id = :'vitoria' and user_id = :B) = '👍',
  'trocar de emoji troca a reação que já existia');

select teste.deve_falhar(
  format($$insert into message_reactions (message_id, user_id, emoji)
           values (%L, %L, '😂')$$, :'vitoria', :A),
  'B não reage em nome de A');

select set_config('request.jwt.claim.sub', :A, false);
select teste.confere(
  teste.conta(format($$select 1 from message_reactions
    where message_id = %L$$, :'vitoria')) = 1,
  'A vê a reação na mensagem dela');

-- De fora não se vê nem se reage.
select set_config('request.jwt.claim.sub', :C, false);
select teste.confere(
  teste.conta('select 1 from message_reactions') = 0,
  'C não vê as reações da conversa dos outros');
select teste.deve_falhar(
  format($$insert into message_reactions (message_id, emoji)
           values (%L, '😂')$$, :'vitoria'),
  'C não reage na conversa dos outros');

-- Tirar a própria reação, e mensagem apagada leva as reações com ela.
select set_config('request.jwt.claim.sub', :B, false);
delete from message_reactions where message_id = :'vitoria' and user_id = :B;
select teste.confere(
  teste.conta('select 1 from message_reactions') = 0,
  'tocar de novo tira a própria reação');

insert into message_reactions (message_id, emoji) values (:'vitoria', '🔥');
reset role;
delete from messages where id = :'vitoria';
select teste.confere(
  (select count(*) from message_reactions where message_id = :'vitoria') = 0,
  'mensagem apagada leva as reações dela');
set role authenticated;

-- ---------------------------------------------------------------------------
-- A do dia

reset role;
set role authenticated;
select set_config('request.jwt.claim.sub', :A, false);
insert into messages (conversation_id, body) values (:'conversa', 'frase boa')
returning id as frase \gset
insert into messages (conversation_id, body) values (:'conversa', 'outra')
returning id as outra \gset

select indicar_destaque(:'frase');
select indicar_destaque(:'frase');
select teste.confere(
  teste.conta('select 1 from destaque_indicacoes') = 1,
  'A indica uma mensagem de hoje, e indicar de novo não duplica');

insert into messages (conversation_id, body) values (:'direta', 'só nós')
returning id as so_nos \gset
select teste.deve_falhar(
  format('select indicar_destaque(%L)', :'so_nos'),
  'a do dia é só da conversa do grupo');

reset role;
update messages set created_at = now() - interval '2 days' where id = :'outra';
set role authenticated;
select teste.deve_falhar(
  format('select indicar_destaque(%L)', :'outra'),
  'só dá para indicar o que foi de hoje');

select set_config('request.jwt.claim.sub', :B, false);
select votar_destaque(:'frase');
select votar_destaque(:'frase');
select teste.confere(
  teste.conta('select 1 from destaque_votos') = 1,
  'um voto por pessoa por dia');
select teste.confere(
  teste.conta('select 1 from destaque_indicacoes') = 1,
  'B vê a indicação de A');

select set_config('request.jwt.claim.sub', :C, false);
select teste.confere(
  teste.conta('select 1 from destaque_indicacoes') = 0,
  'C não vê as indicações do grupo dos outros');
select teste.deve_falhar(
  format('select votar_destaque(%L)', :'frase'),
  'C não vota no grupo dos outros');

reset role;
select teste.confere(
  (select count(*) from fechar_destaques(now() + interval '1 day 7 hours')) = 1,
  'o dia que virou fecha com uma vencedora');
select teste.confere(
  (select message_id from destaques where conversation_id = :'conversa')
    = :'frase'::uuid,
  'a mais votada vira a do dia');
select teste.confere(
  (select count(*) from fechar_destaques(now() + interval '1 day 7 hours')) = 0,
  'o mesmo dia não fecha duas vezes');

update destaque_indicacoes set dia = dia - 1 where message_id = :'frase';
set role authenticated;
select set_config('request.jwt.claim.sub', :A, false);
select teste.deve_falhar(
  format('select votar_destaque(%L)', :'frase'),
  'a votação do dia que já virou fechou');

-- ---------------------------------------------------------------------------
-- Resumo da semana

reset role;
select texto as resumo from resumos_pendentes(((date_trunc('week', now() at time zone 'America/Sao_Paulo') + interval '6 days 20 hours 5 minutes') at time zone 'America/Sao_Paulo'))
where conversation_id = :'conversa' \gset
select teste.confere(
  :'resumo' ~ '^[0-9]+ Chamados?',
  'domingo às 20h sai o resumo, contando os Chamados da semana');
select teste.confere(
  (select count(*) from resumos_pendentes(((date_trunc('week', now() at time zone 'America/Sao_Paulo') + interval '6 days 20 hours 5 minutes') at time zone 'America/Sao_Paulo'))) = 0,
  'o mesmo domingo não manda o resumo duas vezes');
select teste.confere(
  (select count(*) from resumos_pendentes(((date_trunc('week', now() at time zone 'America/Sao_Paulo') + interval '7 days 20 hours 5 minutes') at time zone 'America/Sao_Paulo'))) = 0,
  'na segunda não tem resumo');
set role authenticated;
select set_config('request.jwt.claim.sub', :A, false);
select teste.deve_falhar(
  'select * from resumos_pendentes()',
  'só o servidor monta o resumo');

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
