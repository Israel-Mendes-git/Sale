-- O push no servidor: os avisos do banco para as Edge Functions, e o relógio.
--
-- Até aqui isto era feito à mão no painel (docs/PUSH.md e docs/CRON.md): dois
-- webhooks e um cron. Agora mora numa migração, e o que é segredo fica no
-- Vault do Supabase, não no código:
--
--   select vault.create_secret('https://<projeto>.supabase.co', 'url_do_projeto');
--   select vault.create_secret('<o mesmo SEGREDO_DO_WEBHOOK da função>',
--                              'segredo_do_webhook');
--
-- Sem esses dois no Vault (ou sem pg_net, como no Postgres dos testes), os
-- avisos simplesmente não saem: mandar mensagem nunca falha por causa do push.

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    create extension if not exists pg_net;
  end if;
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
  end if;
end
$$;

-- Chama uma Edge Function com o segredo do Vault. O pg_net só manda depois
-- do commit, então quem a função for ler (os chamados de um Chamado novo, por
-- exemplo) já está gravado.
create function public.chamar_funcao(p_funcao text, p_corpo jsonb)
returns void
language plpgsql security definer set search_path = public as $$
declare
  base text;
  segredo text;
begin
  select decrypted_secret into base
  from vault.decrypted_secrets where name = 'url_do_projeto';
  select decrypted_secret into segredo
  from vault.decrypted_secrets where name = 'segredo_do_webhook';
  if base is null or segredo is null then return; end if;
  perform net.http_post(
    url := base || '/functions/v1/' || p_funcao,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-sale-segredo', segredo
    ),
    body := p_corpo
  );
exception when others then
  -- Push é aviso: falhar aqui não pode desfazer o Chamado nem a mensagem.
  raise warning 'push não saiu (%): %', p_funcao, sqlerrm;
end
$$;

revoke execute on function public.chamar_funcao(text, jsonb)
  from public, anon, authenticated;

-- O Chamado de agora toca assim que nasce.
create function public.avisar_chamado_novo() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform chamar_funcao('enviar-chamado', jsonb_build_object('record', to_jsonb(new)));
  return new;
end
$$;

create trigger chamado_disparado after insert on public.chamados
  for each row execute function public.avisar_chamado_novo();

-- A mensagem do chat avisa quem não está com a conversa aberta.
create function public.avisar_mensagem_nova() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform chamar_funcao('enviar-mensagem', jsonb_build_object('record', to_jsonb(new)));
  return new;
end
$$;

create trigger mensagem_escrita after insert on public.messages
  for each row execute function public.avisar_mensagem_nova();

-- O relógio do grupo: de minuto em minuto, o encontro fixo, o Chamado marcado,
-- a insistência, a soneca, o lembrete e a expiração (docs/CRON.md).
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'cron') then
    perform cron.schedule(
      'disparar-agendados',
      '* * * * *',
      $cron$ select public.chamar_funcao('disparar-agendados', '{}'::jsonb) $cron$
    );
  end if;
end
$$;
