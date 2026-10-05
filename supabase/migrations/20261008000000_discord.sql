-- O Discord do grupo, sem bot: o webhook de um canal, onde o Chamado do grupo
-- é postado, e o ID do servidor, de onde o app lê quem está na call pelo
-- widget público.
--
-- Qualquer um do grupo configura, pela regra que já deixa renomear o grupo. O
-- formato é conferido aqui, para o servidor não postar em endereço qualquer.

alter table public.groups
  add column discord_webhook text check (
    discord_webhook ~ '^https://(discord|discordapp)\.com/api/webhooks/[0-9]+/[A-Za-z0-9_-]+$'
  ),
  add column discord_servidor text check (discord_servidor ~ '^[0-9]{5,25}$');

create or replace function public.versao_do_esquema() returns text
language sql immutable set search_path = public as $$ select '20261008000000' $$;
