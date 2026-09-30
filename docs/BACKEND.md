# Backend (Supabase)

## O que tem

- `supabase/migrations/`: o esquema do banco. Tabelas, regras de acesso (RLS) e as ações
  com regra de negócio (`create_group`, `join_group`, `open_direct`, `send_chamado`,
  `respond_chamado`, `veto_game`, `close_chamado`).
- `supabase/tests/`: um Supabase mínimo para rodar num Postgres comum, e os testes das
  regras.

## Por que a chave pública pode ir no app

A *anon key* vai dentro do APK e qualquer um pode extraí-la. Quem protege os dados são as
regras de acesso: cada pessoa só lê e escreve o que é dos grupos dela, e as mudanças de
estado (responder, vetar, sortear) só acontecem pelas ações, que conferem quem está pedindo.
A *service_role key* nunca vai para o app nem para o repositório.

## Testar as regras

```sh
tool/testar_banco.sh
```

Sobe um Postgres descartável com o `podman`, aplica as migrações e roda os testes (cada um
entra como um usuário diferente e confere o que consegue ver e fazer). Sai com 0 quando
passa, 1 quando um teste ou migração reprova e 2 quando o ambiente está quebrado.

## Aplicar no Supabase

Depois do projeto criado: **SQL Editor → New query**, colar o conteúdo de cada arquivo de
`supabase/migrations/` na ordem do nome e rodar. (Os arquivos de `supabase/tests/` não vão
para lá.)
