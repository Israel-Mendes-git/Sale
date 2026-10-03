-- Expiração do Chamado: o batsinal não fica aceso para sempre.
--
-- Hoje um Chamado que ninguém respondeu e que quem chamou não encerrou fica
-- aberto para sempre: continua no alto da lista de quem foi chamado, ainda
-- aceita resposta no dia seguinte e nunca sai do caminho. Duas horas depois
-- de tocar, a hora de jogar passou.
--
-- Quem fecha é o mesmo cron do disparo (docs/CRON.md), antes de tudo o que
-- toca: Chamado que está expirando não insiste nem acorda soneca.

-- Quando o Chamado expirou. Nulo = aberto, respondido, ou encerrado por quem
-- chamou — que é outra coisa, e o card diz qual foi.
alter table public.chamados add column expired_at timestamptz;

-- Quanto tempo um Chamado fica aberto esperando resposta.
create function public.vida_do_chamado() returns interval
language sql immutable as $$ select interval '2 hours' $$;

-- Fecha os Chamados que ficaram abertos tempo demais; devolve quantos.
--
-- A conta começa no toque, como a da insistência. O marcado que o cron poupou
-- por atraso nunca tocou, e esse conta do horário marcado: senão ficaria
-- aberto para sempre, esperando resposta de um Chamado que ninguém viu.
--
-- Só mexe no que está aberto: Chamado respondido fica como está, de registro,
-- e encerrado já está fechado. [p_agora] existe para os testes poderem viajar
-- no tempo.
create function public.expirar_chamados(p_agora timestamptz default now())
returns integer
language plpgsql security definer set search_path = public as $$
declare
  quantos integer;
begin
  with vencidos as (
    update chamados c
    set status = 'closed', expired_at = p_agora
    where c.status = 'open'
      and coalesce(toque_do_chamado(c), c.scheduled_for) + vida_do_chamado()
          <= p_agora
    returning 1
  )
  select count(*) into quantos from vencidos;
  return quantos;
end
$$;

-- Só o servidor fecha pelo relógio: ninguém logado no app chama isso.
revoke execute on function public.expirar_chamados(timestamptz) from public;
grant execute on function public.expirar_chamados(timestamptz) to service_role;
