# Sale?

App Android para chamar os amigos pra jogar: um batsinal que toca no celular de quem foi
chamado, respostas com um toque, chat estilo WhatsApp e agenda semanal com o encontro fixo.

## Desenvolvimento

Requisitos: Flutter (stable), JDK 21 e Android SDK.

```sh
flutter pub get
flutter analyze
flutter test
flutter run            # com o celular conectado por USB/Wi-Fi
flutter build apk      # APK em build/app/outputs/flutter-apk/
```

Os hooks ficam em `.githooks` — um deles recusa mensagem de commit com marca de
ferramenta. Ligue uma vez em cada cópia do repositório:

```sh
git config core.hooksPath .githooks
```

Ainda em busca do MVP.
