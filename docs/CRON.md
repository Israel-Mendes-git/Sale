# Cron (o encontro fixo e o Chamado marcado tocando sozinhos)

Sem isto, o encontro fixo da quinta só vira Chamado se alguém abrir o app e
disparar na mão, e o Chamado marcado para as 22h nunca toca. Quem resolve é um
cron no Supabase que acorda de minuto em minuto e pergunta ao banco o que
venceu.

```
cron (a cada minuto)  →  Edge Function disparar-agendados
                                      ↓
                         banco: disparar_pendentes()
                           ↓                      ↓
            cria o Chamado do encontro    libera o que estava marcado
                                      ↓
                        Firebase → celular de quem foi chamado
```

A conta de quando disparar mora no banco, junto das outras regras. A função
devolve os Chamados a notificar e a Edge Function só manda os pushes — os
mesmos do `docs/PUSH.md`, pelo mesmo código.

Rodar atrasado não faz mal: a mesma ocorrência nunca dispara duas vezes, e o
que passou de **15 minutos** da hora marcada não acorda mais ninguém — um
servidor que ficou fora do ar não chama o grupo no meio da madrugada.

## 1. O fuso do grupo

"Quinta, 21h" é o horário de quem joga, não o do servidor. Cada grupo tem a
coluna `timezone`, que já nasce `America/Sao_Paulo`. Para conferir:

```sql
select name, timezone from groups;
```

## 2. Publicar a Edge Function

Com o [Supabase CLI](https://supabase.com/docs/guides/cli) e o projeto ligado:

```sh
supabase functions deploy disparar-agendados --no-verify-jwt
```

Ela usa os mesmos segredos do push (`SEGREDO_DO_WEBHOOK` e
`FIREBASE_CONTA_DE_SERVICO`), que já foram configurados em `docs/PUSH.md`. O
`--no-verify-jwt` é porque quem chama é o cron, não uma pessoa logada; a
função se protege com o segredo.

> Publicar o `disparar-agendados` também republica o `enviar-chamado` se o
> código compartilhado (`supabase/functions/_compartilhado/push.ts`) mudar —
> os dois dividem o envio. Na dúvida, publique os dois.

## 3. Ligar o cron

No **SQL Editor**, uma vez só. Troque o endereço do projeto e o segredo:

```sql
create extension if not exists pg_cron;
create extension if not exists pg_net;

select cron.schedule(
  'disparar-agendados',
  '* * * * *',
  $$
  select net.http_post(
    url := 'https://SEU-PROJETO.supabase.co/functions/v1/disparar-agendados',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'x-sale-segredo', 'O-MESMO-SEGREDO-DO-PUSH'
    ),
    body := '{}'::jsonb
  );
  $$
);
```

No painel o mesmo aparece em **Integrations → Cron**, onde dá para pausar e
ver as últimas execuções.

Para trocar o agendamento depois, rode `select cron.unschedule('disparar-agendados');`
e agende de novo.

## 4. Conferir

1. **O cron está rodando?**

   ```sql
   select jobname, schedule, active from cron.job;
   select status, return_message, start_time
   from cron.job_run_details order by start_time desc limit 10;
   ```

2. **O encontro disparou?** Cada ocorrência deixa uma linha:

   ```sql
   select * from meeting_fires order by fired_at desc limit 10;
   ```

3. **Sem esperar a quinta-feira**: a função aceita a hora de propósito, então
   dá para simular (isto cria Chamado de verdade, com push):

   ```sql
   select * from disparar_pendentes(now());
   ```

4. **Logs da função** (painel → Edge Functions → disparar-agendados): mostram
   `{"chamados": N, "enviados": N}`. `chamados: 0` o tempo todo é o esperado —
   ela só tem trabalho na hora do encontro ou de um Chamado marcado.

## O que ainda não existe

- **Insistência**: tocar de novo se ninguém responder em X minutos.
- **Soneca**: "me chama daqui a pouco" reagendando o Chamado só para quem
  pediu.

Os dois cabem nesta mesma função: é onde o relógio do grupo já bate.
