# Pendentes

O que combinamos e ainda falta fazer. Tire daqui o que for feito.

## Push (a 1.4.0 saiu sem)

A 1.4.0 está publicada, e as migrações e as Edge Functions estão em produção, mas o push
não funciona ainda, por dois motivos:

- [x] **Firebase:** projeto `sale-abfa7` criado. O `google-services.json` está em
      `android/app/` no Windows; na máquina Linux ainda falta copiar. O
      `publicar_versao.sh` recusa publicar sem ele.
- [x] **Segredos das Edge Functions** (`SEGREDO_DO_WEBHOOK` e `FIREBASE_CONTA_DE_SERVICO`)
      gravados em 06/10/2026: o relógio do servidor passou de 401 para 200.
- [ ] **Publicar a próxima versão** com o Firebase dentro. A 1.4.0 dos celulares não tem
      push e nunca vai registrar o aparelho.
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

- **Discord com bot:** hoje o Chamado é postado via webhook e a call aparece pelo widget,
  sem bot. Um bot permitiria responder o Chamado pelo próprio Discord.
