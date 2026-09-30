# Sale?

App Android para chamar os amigos pra jogar: um "batsinal" que toca no celular de quem foi
chamado, respostas com um toque, chat estilo WhatsApp e agenda semanal com o encontro fixo.

Projeto pessoal. Requisitos em [`docs/PRD.md`](docs/PRD.md).

## Estado

Fase 1 (MVP) em andamento. O app roda com um backend em memória: dá para entrar como
Israel, Beto ou Caio, conversar, disparar e responder Chamados e usar a aba Semana
(encontro fixo, confirmação de presença, disponibilidade e horários em que todos estão
livres). Ainda faltam login real, Supabase e notificação push.

## Desenvolvimento

Requisitos: Flutter (stable), JDK 21 e Android SDK.

```sh
flutter pub get
flutter analyze
flutter test
flutter run            # com o celular conectado por USB/Wi-Fi
flutter build apk      # APK em build/app/outputs/flutter-apk/
```

Para testar as três pontas de um Chamado num só aparelho, use o avatar no canto da lista de
conversas para trocar de usuário.
