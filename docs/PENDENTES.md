# Pendentes

O que combinamos e ainda falta fazer. Tire daqui o que for feito.

## Push (a 1.4.0 saiu sem)

A 1.4.0 está publicada, e as migrações e as Edge Functions estão em produção, mas o push
não funciona ainda, por dois motivos:

- [ ] **O APK não tem Firebase.** A 1.4.0 foi gerada sem `android/app/google-services.json`
      e nenhum celular registrou o push (`device_tokens` vazia). Crie o projeto "Sale" no
      Firebase com o app Android `com.israelmendes.sale` e coloque o arquivo na máquina de
      build. Agora o `publicar_versao.sh` recusa publicar sem ele.
- [ ] **As funções recusam o servidor.** O relógio chama `disparar-agendados` a cada minuto
      e recebe `401 não autorizado`, porque o segredo `SEGREDO_DO_WEBHOOK` das Edge Functions
      falta ou não bate com o `segredo_do_webhook` do Vault. Enquanto isso não for
      resolvido, não saem Chamado agendado, lembrete, insistência, soneca, a do dia nem o
      resumo da semana. Em Edge Functions → Secrets, configure:
  - `SEGREDO_DO_WEBHOOK`: o mesmo valor do Vault.
  - `FIREBASE_CONTA_DE_SERVICO`: o JSON inteiro da conta de serviço do Firebase.
- [ ] **Publicar a 1.4.1** com o Firebase dentro.
- [ ] **Testar no celular:**
  - Chamado com a tela bloqueada.
  - Os botões da notificação ("Bora!", "Chego em 20", "Hoje não"), com e sem rede.
  - O atalho "Chamar o grupo".
  - Recado de voz: gravar e ouvir.
  - Menção com o grupo calado.
  - Aviso da do dia às 6h.
  - Resumo da semana no domingo às 20h.

## Configuração

- [ ] **Steam:** criar uma chave da Steam Web API e salvar como o segredo `STEAM_API_KEY`
      no Supabase. Sem a chave, "Importar da Steam" responde com erro. A Steam saiu das
      novidades da 1.4.0 e volta ao CHANGELOG quando a chave entrar.
- [ ] **Discord:** no app, em Meu perfil → Seu grupo → Discord do grupo, colar o webhook
      do canal e, se quiser "quem está na call", o ID do servidor com o widget ligado.
- [ ] **Senha do banco:** trocar no painel do Supabase. A senha atual ficou exposta na
      conversa.

## Ideias que ficaram pela metade

- **Widget na tela inicial:** a ideia era "atalho ou widget de um toque", e só o atalho
  (segurar o ícone) foi feito.
- **Número de jogadores dos jogos da Steam:** a Steam não informa, então o jogo importado
  entra com a faixa de 1 a 10 jogadores. Vale ajustar à mão na biblioteca, ou buscar
  essa informação em outra fonte.
- **Discord com bot:** hoje o Chamado é postado via webhook e a call aparece pelo widget,
  sem bot. Um bot permitiria responder o Chamado pelo próprio Discord.
