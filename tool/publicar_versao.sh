#!/usr/bin/env bash
# Gera o APK de release da versão do pubspec e, com --publicar, cria a
# release no GitHub (é de lá que o app baixa a atualização).
# Roda no Linux (distrobox mobiledev) e no Windows (Git Bash).
# Ver docs/RELEASE.md.
#
# Saída: 0 = ok · 1 = recusado (algo fora do lugar) · 2 = ambiente quebrado
set -euo pipefail
cd "$(dirname "$0")/.."

publicar=false
[[ "${1:-}" == "--publicar" ]] && publicar=true

falha() { echo "RECUSADO: $*" >&2; exit 1; }
quebrado() { echo "AMBIENTE: $*" >&2; exit 2; }

# No Git Bash do Windows os executáveis do Flutter e do SDK são .bat.
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) bat=.bat ;;
  *) bat= ;;
esac

FLUTTER="flutter$bat"
command -v "$FLUTTER" >/dev/null ||
  quebrado "$FLUTTER não encontrado no PATH (no Linux, está no mobiledev?)"

sdk="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
# No Linux não existe LOCALAPPDATA, e com set -u o nome solto derruba o
# script. A cópia local, vazia lá, deixa a troca de contrabarra do caminho
# do Windows seguir valendo quando a variável existe.
localappdata="${LOCALAPPDATA:-}"
for tentativa in "$HOME/Android/Sdk" "$HOME/AndroidSdk" "${localappdata//\\//}/Android/Sdk"; do
  [[ -n "$sdk" ]] && break
  [[ -d "$tentativa" ]] && sdk=$tentativa
done
APKSIGNER=$(ls "$sdk"/build-tools/*/"apksigner$bat" 2>/dev/null | sort -V | tail -1)
[[ -n "$APKSIGNER" && -f "$APKSIGNER" ]] ||
  quebrado "apksigner não encontrado no Android SDK (${sdk:-indefinido})"
[[ -f android/key.properties ]] || quebrado "falta android/key.properties (chave de release)"

versao=$(sed -n 's/^version: \([0-9.]*\).*/\1/p' pubspec.yaml)
[[ -n "$versao" ]] || quebrado "não achei a versão no pubspec.yaml"
tag="v$versao"

[[ -z "$(git status --porcelain)" ]] || falha "há mudanças não commitadas"
if $publicar; then
  command -v gh >/dev/null || quebrado "gh não encontrado"
  git fetch -q origin
  [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] ||
    falha "o HEAD não é o origin/main; faça push antes de publicar"
  if gh release view "$tag" >/dev/null 2>&1; then falha "a release $tag já existe"; fi
fi

notas=$(awk -v cab="## $versao" '$0 == cab {f = 1; next} /^## / {f = 0} f' CHANGELOG.md |
  sed '/./,$!d')
[[ -n "${notas//[[:space:]]/}" ]] || falha "CHANGELOG.md sem a seção '## $versao'"

# Produção atrás do repositório quebra o app na mão de todo mundo (já
# aconteceu): o APK pede colunas que o banco não tem. Cada migração recria
# versao_do_esquema() com o próprio número, e aqui ela tem de bater com a
# última do repositório. Ver docs/RELEASE.md.
if [[ -f config/sale.json ]]; then
  url=$(sed -n 's/.*"SUPABASE_URL": *"\([^"]*\)".*/\1/p' config/sale.json)
  chave=$(sed -n 's/.*"SUPABASE_KEY": *"\([^"]*\)".*/\1/p' config/sale.json)
  ultima=$(ls supabase/migrations/*.sql | sort | tail -1)
  ultima=$(basename "$ultima")
  ultima=${ultima%%_*}
  emprod=$(curl -fsS -X POST "$url/rest/v1/rpc/versao_do_esquema" \
    -H "apikey: $chave" -H "Authorization: Bearer $chave" \
    -H 'Content-Type: application/json' -d '{}' | tr -d '"') ||
    quebrado "não deu para perguntar a versão do esquema a produção"
  [[ "$emprod" == "$ultima" ]] ||
    falha "produção está na migração ${emprod:-?} e o repositório na $ultima: aplique as migrações antes de publicar"
  echo "esquema de produção em dia: $emprod"
fi

# Sem android/app/google-services.json o build pula o Firebase calado e o APK
# sai sem push nenhum — nem Chamado, nem mensagem (a 1.4.0 saiu assim). Para
# soltar uma versão sem push de propósito: SEM_PUSH=1.
push="ligado (android/app/google-services.json)"
if [[ ! -f android/app/google-services.json ]]; then
  [[ "${SEM_PUSH:-}" == 1 ]] ||
    falha "falta android/app/google-services.json: o APK sairia sem push (SEM_PUSH=1 para soltar assim mesmo)"
  push="DESLIGADO (SEM_PUSH=1)"
fi

"$FLUTTER" analyze || falha "flutter analyze reprovou"
"$FLUTTER" test || falha "os testes reprovaram"
# Com config/sale.json o APK fala com o Supabase; sem ele, roda em memória.
build_args=(--release)
modo="em memória (sem config/sale.json)"
if [[ -f config/sale.json ]]; then
  build_args+=(--dart-define-from-file=config/sale.json)
  modo="Supabase ($(sed -n 's/.*"SUPABASE_URL": *"\([^"]*\)".*/\1/p' config/sale.json))"
fi
"$FLUTTER" build apk "${build_args[@]}" || quebrado "o build do APK quebrou"

mkdir -p dist
apk="dist/Sale-$tag.apk"
cp build/app/outputs/flutter-apk/app-release.apk "$apk"

certs=$("$APKSIGNER" verify --print-certs "$apk") || falha "assinatura do APK inválida"
if grep -q "CN=Android Debug" <<<"$certs"; then
  falha "o APK saiu assinado com a chave de depuração"
fi

echo
echo "== Sale? $versao =="
echo "arquivo: $apk"
echo "tamanho: $(du -h "$apk" | cut -f1)"
echo "sha256:  $(sha256sum "$apk" | cut -d' ' -f1)"
echo "chave:   $(grep -m1 'certificate DN' <<<"$certs" | sed 's/.*DN: //')"
echo "backend: $modo"
echo "push:    $push"
echo "novidades:"
echo "$notas"
echo

if $publicar; then
  gh release create "$tag" "$apk" --title "Sale? $versao" --notes "$notas" \
    --target "$(git rev-parse HEAD)"
  echo "Publicado. Os celulares vão avisar na próxima abertura do app."
else
  echo "Ensaio: nada foi publicado. Para publicar: tool/publicar_versao.sh --publicar"
fi
