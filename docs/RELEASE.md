# Publicar uma versão

O app confere a última release de `github.com/Israel-Mendes-git/Sale` e oferece a
atualização. Cada release precisa ter um APK anexado.

## Passo a passo

1. Suba a versão em `pubspec.yaml` (`version: 1.2.0+3`: o número depois do `+` também sobe).
2. Escreva a seção `## 1.2.0` no `CHANGELOG.md`. É o texto que aparece no aviso do app.
3. Commit e push.
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
sem novidades, testes reprovados, APK com chave de depuração) e 2 quando o ambiente está
quebrado (sem Flutter, sem SDK, sem a chave).

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
