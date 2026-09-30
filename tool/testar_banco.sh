#!/usr/bin/env bash
# Aplica as migrações do Supabase num Postgres descartável (podman) e roda
# os testes das regras de acesso.
#
# Saída: 0 = passou · 1 = teste ou migração reprovou · 2 = ambiente quebrado
set -euo pipefail
cd "$(dirname "$0")/.."

imagem=docker.io/library/postgres:16-alpine
nome="sale-teste-banco-$$"

quebrado() { echo "AMBIENTE: $*" >&2; exit 2; }
reprovou() { echo "REPROVOU: $*" >&2; exit 1; }

command -v podman >/dev/null || quebrado "podman não encontrado"
shopt -s nullglob
migracoes=(supabase/migrations/*.sql)
((${#migracoes[@]})) || quebrado "nenhuma migração em supabase/migrations"

podman run -d --rm --name "$nome" -e POSTGRES_PASSWORD=teste "$imagem" >/dev/null ||
  quebrado "não subiu o Postgres ($imagem)"
trap 'podman rm -f "$nome" >/dev/null 2>&1 || true' EXIT

# A imagem sobe um servidor provisório antes do definitivo: espera o 2º "pronto".
for _ in $(seq 120); do
  prontos=$(podman logs "$nome" 2>&1 | grep -c "ready to accept connections" || true)
  ((prontos >= 2)) && break
  sleep 0.5
done
((prontos >= 2)) || quebrado "o Postgres não ficou pronto"

rodar() { podman exec -i "$nome" psql -U postgres -v ON_ERROR_STOP=1 -q "$@"; }

rodar <supabase/tests/00_supabase_local.sql || quebrado "falhou o Supabase de mentira"
for m in "${migracoes[@]}"; do
  echo "migração: $m"
  rodar <"$m" || reprovou "a migração $m falhou"
done
rodar <supabase/tests/01_permissoes_padrao.sql || quebrado "falhou dar as permissões padrão"

saida=$(rodar <supabase/tests/10_regras.sql 2>&1) || {
  echo "$saida" | grep -E "FALHOU|ERROR|ERRO" >&2
  reprovou "testes do banco"
}
echo "$saida" | grep -c "NOTICE:  ok" | xargs -I{} echo "{} verificações passaram"
echo "$saida" | grep "TODOS OS TESTES" || reprovou "os testes não chegaram ao fim"
