#!/usr/bin/env bash
# Gera o APK de release da versão do pubspec e, com --publicar, cria a
# release no GitHub (é de lá que o app baixa a atualização).
# Roda dentro do distrobox mobiledev. Ver docs/RELEASE.md.
#
# Saída: 0 = ok · 1 = recusado (algo fora do lugar) · 2 = ambiente quebrado
set -euo pipefail
cd "$(dirname "$0")/.."

publicar=false
[[ "${1:-}" == "--publicar" ]] && publicar=true

falha() { echo "RECUSADO: $*" >&2; exit 1; }
quebrado() { echo "AMBIENTE: $*" >&2; exit 2; }

command -v flutter >/dev/null || quebrado "flutter não encontrado (está no mobiledev?)"
APKSIGNER=$(ls "${ANDROID_HOME:-$HOME/Android/Sdk}"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -1)
[[ -x "$APKSIGNER" ]] || quebrado "apksigner não encontrado no Android SDK"
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

flutter analyze || falha "flutter analyze reprovou"
flutter test || falha "os testes reprovaram"
# Com config/sale.json o APK fala com o Supabase; sem ele, roda em memória.
build_args=(--release)
modo="em memória (sem config/sale.json)"
if [[ -f config/sale.json ]]; then
  build_args+=(--dart-define-from-file=config/sale.json)
  modo="Supabase ($(sed -n 's/.*"SUPABASE_URL": *"\([^"]*\)".*/\1/p' config/sale.json))"
fi
flutter build apk "${build_args[@]}" || quebrado "o build do APK quebrou"

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
