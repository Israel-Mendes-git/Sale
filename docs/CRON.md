# Cron (o relógio do grupo)

Sem isto, o encontro fixo da quinta só vira Chamado se alguém abrir o app e
disparar na mão, o Chamado marcado para as 22h nunca toca, ninguém é chamado de
novo e o encontro chega com meio grupo sem confirmar. Quem resolve é um cron no
Supabase que acorda de minuto em minuto e pergunta ao banco o que venceu.

```
cron (a cada minuto)  →  Edge Function disparar-agendados
            ↓               ↓                        ↓
   expirar_chamados()   disparar_pendentes()   lembretes_pendentes()
            ↓        ↓          ↓           ↓        ↓
   fecha o que   cria o      libera o   insiste   avisa quem não
   esperou       Chamado do  marcado    com quem  confirmou, duas
   demais        encontro               calou     horas antes
                               ↓     acorda quem pediu soneca
                        Firebase → celular de quem foi chamado
```

A conta de quando disparar mora no banco, junto das outras regras. A função
devolve os Chamados a notificar, cada um com **quem notificar** (a soneca e a
insistência tocam só para algumas pessoas) e com o **motivo**, que é o que o
app escreve na notificação. A Edge Function só manda os pushes — os mesmos do
`docs/PUSH.md`, pelo mesmo código.

Rodar atrasado não faz mal: a mesma ocorrência nunca dispara duas vezes, e o
que passou de **15 minutos** da hora marcada não acorda mais ninguém — um
servidor que ficou fora do ar não chama o grupo no meio da madrugada. Vale para
os cinco: encontro, Chamado marcado, insistência, soneca e lembrete.

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

Já vem na migração `20261006120000_push_no_servidor.sql`: ela liga o `pg_cron` e o
`pg_net` e agenda o `disparar-agendados` de minuto em minuto, chamando a função com o
segredo do Vault (ver o passo 5 de `docs/PUSH.md`). No painel o agendamento aparece em
**Integrations → Cron**, onde dá para pausar e ver as últimas execuções.

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
   `{"chamados": N, "lembretes": N, "enviados": N, "expirados": N}`. Tudo em
   zero o tempo todo é o esperado — ela só tem trabalho na hora do encontro, de
   um Chamado marcado, de uma soneca, de uma insistência ou de um lembrete.

## 5. A soneca e a insistência

As duas são o mesmo relógio, na mesma função, e as duas tocam **só para
algumas pessoas** — o resto do grupo não é incomodado de novo.

**Soneca.** Quem responde "💤 Me chama daqui a pouco" escolhe daqui a quanto
(15 minutos, se não escolher). Na hora, a resposta cai e a pessoa volta para a
fila de quem não respondeu — é isso que faz o Chamado tocar de novo só para
ela. Quem muda de ideia antes ("Bora!") perde a soneca. Chamado encerrado por
quem chamou também não acorda mais ninguém.

**Insistência.** Chamado que ficou sem resposta toca uma segunda vez, **cinco
minutos** depois, para quem ficou calado. Uma vez por Chamado: o batsinal
insiste, não fica apitando a noite toda. O relógio conta do toque — e um
Chamado que o cron poupou por atraso nunca tocou, então também não insiste.

```sql
-- As duas acompanham o Chamado:
select nudged_at from chamados where id = '...';
select user_id, snoozed_until from chamado_targets where chamado_id = '...';
```

Para simular sem esperar, a mesma viagem no tempo do passo 4:

```sql
select * from disparar_pendentes(now() + interval '5 minutes');
```

## 6. O lembrete do encontro

**Duas horas antes** do encontro fixo, quem ainda não confirmou presença
recebe um aviso. Não é Chamado: não toca em tela cheia nem espera resposta na
hora. É uma notificação comum, em canal próprio ("Lembretes do encontro"), que
leva a pessoa a dizer se vai — dentro do app, o mesmo "você vai?" espera no
alto da lista de conversas.

Quem já respondeu não é lembrado, semana pulada não lembra ninguém e horário
trocado da semana manda na conta. Cada ocorrência avisada fica anotada em
`meeting_reminders`, como o disparo faz em `meeting_fires`:

```sql
select * from meeting_reminders order by sent_at desc limit 10;

-- Sem esperar a quinta (isto manda push de verdade):
select * from lembretes_pendentes(now());
```

A conta dentro do app é a mesma (`meetingReminderAhead`, em
`lib/domain/calendar.dart`), e por isso o aviso na tela aparece junto com o
push, sem o servidor precisar contar nada para o app.

## 7. O Chamado expirando

**Duas horas** depois de tocar, o Chamado que ninguém respondeu e que quem
chamou não encerrou fecha sozinho: sai do alto da lista, não aceita mais
resposta e o card diz "expirou" — que não é "encerrado", porque ninguém
encerrou.

A conta começa no toque, como a da insistência, e o marcado que o cron poupou
por atraso conta do horário marcado: senão ficaria aberto para sempre,
esperando resposta de um Chamado que ninguém viu. Chamado respondido não expira;
fica de registro, para o placar.

`expirar_chamados()` roda **antes** de tudo o que toca, de propósito: Chamado
que está expirando não insiste com ninguém nem acorda quem pediu soneca.

```sql
-- Sem esperar as duas horas:
select expirar_chamados(now() + interval '2 hours');
select id, status, expired_at from chamados where expired_at is not null;
```
