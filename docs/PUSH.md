# Push (o Chamado tocando com o app fechado)

Sem push, o Chamado só aparece com o app aberto — o contrário da ideia. Quem
entrega a mensagem é o Firebase Cloud Messaging; quem decide a quem mandar é uma
Edge Function do Supabase, acionada pelo banco quando um Chamado nasce.

```
alguém chama  →  insert em chamados  →  webhook do banco
                                           ↓
                               Edge Function enviar-chamado
                                           ↓
                          Firebase → celular de quem foi chamado
                                           ↓
                        o app monta a notificação de tela cheia
```

A mensagem vai **sem título e sem corpo**, só com dados. É de propósito: quem monta
a notificação é o app, porque ela precisa abrir em tela cheia como uma ligação, e
isso o Android só deixa o próprio aplicativo fazer.

## 1. Criar o projeto no Firebase

1. <https://console.firebase.google.com> → **Criar um projeto** → nome `Sale`.
   Pode desligar o Google Analytics.
2. Dentro do projeto: **Adicionar app → Android**.
   - *Nome do pacote*: `com.israelmendes.sale` (precisa ser exatamente este; é o
     `applicationId` do `android/app/build.gradle.kts`).
   - *Apelido*: Sale?
   - A impressão digital SHA-1 não é necessária para o push.
3. Baixe o **`google-services.json`** e salve em:

   ```
   android/app/google-services.json
   ```

   Ele está no `.gitignore` e não vai para o repositório. Cada computador que compilar
   precisa do arquivo.

Sem esse arquivo o app continua compilando e funcionando — só fica sem push.

## 2. A conta de serviço (como o servidor fala com o Firebase)

1. No Firebase: **⚙️ → Configurações do projeto → Contas de serviço**.
2. **Gerar nova chave privada** → baixa um `.json`. Guarde bem: é uma chave que
   manda notificação em nome do app.
3. Esse arquivo **não** entra no repositório nem no APK: vai para os segredos da
   Edge Function (passo 4).

## 3. Publicar a Edge Function

Com o [Supabase CLI](https://supabase.com/docs/guides/cli) instalado e o projeto
ligado (`supabase link --project-ref xpzwgofotrqgkdufomts`):

```sh
supabase functions deploy enviar-chamado --no-verify-jwt
```

O `--no-verify-jwt` é porque quem chama é o banco, não uma pessoa logada; a função
se protege com o segredo do passo 4.

## 4. Os segredos da função

```sh
supabase secrets set SEGREDO_DO_WEBHOOK="<invente uma senha longa>"
supabase secrets set FIREBASE_CONTA_DE_SERVICO="$(cat ~/Downloads/sale-firebase.json)"
```

`SUPABASE_URL` e `SUPABASE_SERVICE_ROLE_KEY` o Supabase já injeta sozinho.

## 5. O webhook do banco

No painel: **Database → Webhooks → Create a new hook**.

| Campo | Valor |
|---|---|
| Name | `chamado_disparado` |
| Table | `public.chamados` |
| Events | `Insert` |
| Type | Supabase Edge Functions |
| Edge Function | `enviar-chamado` |
| HTTP Headers | `x-sale-segredo: <o mesmo segredo do passo 4>` |

## 6. Conferir

Dispare um Chamado de um celular para o outro com o app **fechado** no destino.
O caminho para investigar, em ordem:

1. **Logs da função** (painel → Edge Functions → enviar-chamado): mostra quantos
   envios saíram. `enviados: 0` quer dizer que ninguém tinha aparelho registrado —
   confira a tabela `device_tokens`.
2. **`select * from device_tokens`**: cada celular que abriu o app logado deve ter
   uma linha.
3. Notificação chega mas não abre em tela cheia: no Android 14+ a tela cheia
   depende de uma permissão especial; sem ela vira aviso no topo, que ainda toca.

## Chamado marcado para depois

Esta função cuida do Chamado de agora. O marcado para mais tarde e o encontro
fixo são do cron, que acorda na hora certa e usa o mesmo envio
(`supabase/functions/_compartilhado/push.ts`) — ver `docs/CRON.md`.

## O que ainda não existe

- **Insistência**: tocar de novo se ninguém responder em X minutos (fase 4).
