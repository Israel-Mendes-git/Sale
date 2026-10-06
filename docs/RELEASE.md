# Publicar uma versão

O app confere a última release de `github.com/Israel-Mendes-git/Sale` e oferece a
atualização. Cada release precisa ter um APK anexado.

## Passo a passo

1. Suba a versão em `pubspec.yaml` (`version: 1.2.0+3`: o número depois do `+` também sobe).
2. Escreva a seção `## 1.2.0` no `CHANGELOG.md`. É o texto que aparece no aviso do app.
3. Commit e push. Se a versão traz migração nova, aplique em produção antes (pelo MCP do
   Supabase, `apply_migration`): o ensaio recusa quando o esquema de produção está atrás.
4. Ensaio (roda análise, testes e build, e confere a assinatura, sem publicar nada):

   Linux:

   ```sh
   distrobox enter mobiledev -- bash -ic 'cd ~/Documentos/GitHub/Sale && tool/publicar_versao.sh'
   ```

   Windows (Git Bash):

   ```sh
   cd ~/Documents/GitHub/Sale && tool/publicar_versao.sh
   ```

5. Com o resumo conferido, publique acrescentando `--publicar` ao comando.

O script sai com 0 quando dá certo, 1 quando recusa (árvore suja, versão já publicada,
sem novidades, testes reprovados, APK com chave de depuração, sem
`android/app/google-services.json`) e 2 quando o ambiente está quebrado (sem Flutter,
sem SDK, sem a chave).

Sem o `google-services.json` o build pula o Firebase sem avisar e o APK sai sem push
nenhum, nem Chamado, nem mensagem; foi assim que a 1.4.0 saiu. Para soltar uma versão
sem push de propósito, rode com `SEM_PUSH=1`. O resumo do ensaio mostra a linha `push:`.

## Produção em dia

O app novo pede ao banco o que as migrações criaram; produção atrás do repositório
quebra o app na mão de todo mundo. Por isso cada migração termina recriando
`versao_do_esquema()` com o próprio número, e o `publicar_versao.sh` pergunta essa
versão a produção (com a chave pública de `config/sale.json`) e recusa se ela não
bater com a última migração do repositório. O `tool/testar_banco.sh` reprova a
migração que esquecer de atualizar a função.

## A chave de assinatura

- Fica em `~/.config/sale/` (`sale-release.jks` e `key.properties`), fora do repositório.
  No Windows é a mesma pasta: `C:\Users\<você>\.config\sale\`.
- O build lê `android/key.properties`, que está no `.gitignore` do Android. O modelo é
  `android/key.properties.example`; no Windows, escreva o caminho com barras normais
  (`C:/Users/...`).
- **Guarde uma cópia dessa pasta em lugar seguro.** O Android só aceita atualizar o app com
  um APK assinado pela mesma chave. Se ela se perder, todo mundo tem de desinstalar e
  instalar de novo.
- Pelo mesmo motivo, publicar do Linux e do Windows exige a **mesma** chave nos dois. Em
  dual boot, copie `~/.config/sale/` para um disco que os dois enxergam (os discos `D:` e
  `E:` são exFAT) e leve de lá para o outro sistema.
- Sem a chave, o build de release falha de propósito, para não sair um APK assinado com a
  chave de depuração.

## O que cada sistema precisa

| | Linux | Windows |
|---|---|---|
| Flutter | no `PATH` do `mobiledev` | `flutter.bat` no `PATH` |
| Android SDK | `ANDROID_HOME` | `ANDROID_HOME` (usa `apksigner.bat`) |
| GitHub CLI | `gh` autenticado | `gh` autenticado |
| Terminal | bash | Git Bash (o script não roda no PowerShell) |

Com 8 GB livres no disco do sistema, aponte os caches para outro disco antes de compilar:
`PUB_CACHE` e `GRADLE_USER_HOME`.

## Tropeços do Windows

- **O Gradle não instala pacotes do SDK sozinho.** Ele chama `sdkmanager "ndk;28.2.13676358"`,
  o `cmd` parte o nome no `;` e o erro vira `Package ndk not found`. Instale à mão, por
  arquivo (é o único jeito que escapa do `;`):

  ```sh
  printf 'ndk;28.2.13676358\n' > /tmp/pacotes.txt
  "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager.bat" \
    --sdk_root="$ANDROID_HOME" --package_file=/tmp/pacotes.txt
  ```

- **SDK do Flutter em disco exFAT** (`D:`/`E:`): o git recusa com *dubious ownership* —
  resolva com `git config --global --add safe.directory D:/flutter`. O aviso
  `Unblock-File ... Zone.Identifier` que aparece a cada comando é só ruído: exFAT não tem
  fluxos alternativos de arquivo.

- **Disco do sistema.** O NDK sozinho ocupa 2,1 GB. Aponte `PUB_CACHE` e
  `GRADLE_USER_HOME` para outro disco antes do primeiro build.
