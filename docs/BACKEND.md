# Backend (Supabase)

## O que tem

- `supabase/migrations/`: o esquema do banco. Tabelas, regras de acesso (RLS) e as ações
  com regra de negócio (`create_group`, `join_group`, `open_direct`, `send_chamado`,
  `respond_chamado`, `arrive_chamado`, `veto_game`, `close_chamado`).
- `supabase/tests/`: um Supabase mínimo para rodar num Postgres comum, e os testes das
  regras.
- `lib/data/supabase_repository.dart`: o app falando com tudo isso. Lê por consulta,
  escreve pelas ações e escuta o tempo real para atualizar as telas sozinho.

## Por que a chave pública pode ir no app

A *anon key* (ou *publishable key*) vai dentro do APK e qualquer um pode extraí-la. Quem
protege os dados são as regras de acesso: cada pessoa só lê e escreve o que é dos grupos
dela, e as mudanças de estado (responder, vetar, sortear) só acontecem pelas ações, que
conferem quem está pedindo. A *service_role key* nunca vai para o app nem para o
repositório.

## Configurar o projeto no Supabase

Uma vez só, no navegador. O endereço do projeto aparece em **Project Settings → Data API**
como `https://SEU-PROJETO.supabase.co`; a parte `SEU-PROJETO` é a *referência* usada
abaixo.

### 1. Aplicar o esquema

**SQL Editor → New query**, colar o conteúdo de cada arquivo de `supabase/migrations/` na
ordem do nome e rodar. (Os arquivos de `supabase/tests/` não vão para lá.)

Confira depois em **Table Editor**: devem aparecer `profiles`, `groups`, `chamados`,
`messages` e as outras, todas com o cadeado de RLS ligado.

Versão nova do app às vezes traz migração nova. Ao atualizar o APK, rode os arquivos que
ainda não passaram por aqui: sem isso o app procura coluna que não existe e as telas
mostram erro.

### 2. Dizer para onde o login volta

**Authentication → URL Configuration**:

- *Site URL*: `sale://login-callback`
- *Redirect URLs*: adicionar `sale://login-callback`

É o mesmo endereço que está em `AppConfig.authRedirect` e no `intent-filter` do
`android/app/src/main/AndroidManifest.xml`. Se os três não baterem, o navegador abre, o
login funciona e o app nunca recebe a sessão de volta.

### 3. Entrar com Discord

1. <https://discord.com/developers/applications> → **New Application** (nome: Sale?).
2. **OAuth2 → Redirects**: adicionar `https://SEU-PROJETO.supabase.co/auth/v1/callback`
   e salvar.
3. Copiar o **Client ID** e gerar o **Client Secret** na mesma página.
4. No Supabase: **Authentication → Sign In / Providers → Discord**, ligar e colar os dois.

### 4. Entrar com Google

1. <https://console.cloud.google.com> → criar um projeto (ou usar um já existente).
2. **APIs e serviços → Tela de consentimento OAuth**: tipo *Externo*, nome do app, e-mail
   de suporte e e-mail do desenvolvedor. Pode ficar em *Teste* com os três e-mails do
   grupo em *Usuários de teste*.
3. **Credenciais → Criar credenciais → ID do cliente OAuth → Aplicativo da Web**. Em
   *URIs de redirecionamento autorizados*, pôr
   `https://SEU-PROJETO.supabase.co/auth/v1/callback`.
4. No Supabase: **Authentication → Sign In / Providers → Google**, ligar e colar o
   *Client ID* e o *Client Secret*.

O app abre esses dois no navegador do celular (Custom Tabs), que é o jeito que o Google
aceita.

### 5. Guardar a configuração no computador

`config/sale.json` (fora do Git; modelo em `config/sale.example.json`):

```json
{
  "SUPABASE_URL": "https://SEU-PROJETO.supabase.co",
  "SUPABASE_KEY": "sb_publishable_..."
}
```

A chave está em **Project Settings → API Keys**. Use a publicável (ou a *anon public*, nos
projetos mais antigos) — nunca a `service_role`.

## Rodar com o servidor

```sh
flutter run --dart-define-from-file=config/sale.json
```

Sem esse arquivo o app usa o backend em memória, com os perfis de desenvolvimento. O
`tool/publicar_versao.sh` usa o arquivo quando ele existe e mostra no resumo qual backend
o APK vai usar.

## Primeiro acesso

1. Entrar com Discord ou Google. O perfil nasce sozinho, com o nome do provedor como
   sugestão.
2. Quem chegar primeiro cria o grupo; os outros entram com o código que aparece em
   **Meu perfil → Seu grupo**.
3. Em "Meu perfil", cada um confirma como quer ser chamado e cadastra as respostas
   próprias.

## Testar as regras

```sh
tool/testar_banco.sh
```

Sobe um Postgres descartável com o `podman`, aplica as migrações e roda os testes (cada um
entra como um usuário diferente e confere o que consegue ver e fazer). Sai com 0 quando
passa, 1 quando um teste ou migração reprova e 2 quando o ambiente está quebrado.

## Ainda não está lá

- **Encontro fixo e Chamado agendado disparados no servidor** (Edge Function + cron). O
  Chamado de agora já toca com o app fechado — ver `docs/PUSH.md`.
