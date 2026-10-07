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

- [x] **Steam:** `STEAM_API_KEY` no Supabase desde 06/10/2026; a importação voltou ao
      CHANGELOG (1.5.0).
- [ ] **Discord:** no app, em Meu perfil → Seu grupo → Discord do grupo, colar o ID do
      servidor com o widget ligado (e o canal de convite escolhido, para o "Abrir no
      Discord"); cada um diz o seu nome no Discord na engrenagem da mesma tela.
- [ ] **Discord ao vivo em produção:** a migração `20261010000000_discord_ao_vivo.sql`
      está aplicada e a `disparar-agendados` nova está no ar desde 06/10/2026. Falta
      subir de novo a `enviar-chamado`, que ainda posta o Chamado no webhook, como em
      `docs/PUSH.md`: a CLI disse que subiu, mas produção ficou na versão 4.
- [ ] **Senha do banco:** trocar no painel do Supabase. A senha atual ficou exposta na
      conversa.

## Ideias que ficaram pela metade

- **Discord com bot:** hoje o Sale? só lê o widget do servidor, sem bot e sem postar
  nada. Um bot permitiria postar o Chamado no canal e responder pelo próprio Discord.
- **Coluna `groups.discord_webhook`:** fica até a 1.4.0 sair dos celulares, que ainda a
  lê. Depois, uma migração a apaga.
