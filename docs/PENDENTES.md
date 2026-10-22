# Pendentes

O que combinamos e ainda falta fazer. Tire daqui o que for feito.

## 1.8.0 (chat e lista de conversas)

O app novo lê `conversation_prefs` e `messages.forwarded`: sem a migração em produção,
a lista de conversas e o chat quebram. A ordem é esta:

- [ ] Aplicar `20261022000000_lista_de_conversas.sql` em produção.
- [ ] Subir a função `enviar-mensagem` (o `_compartilhado/push.ts` passou a pular quem
      silenciou): `supabase functions deploy enviar-mensagem --use-api`.
- [ ] Só então publicar o APK 1.8.0.
- [ ] Testar no celular: arrastar para responder, dois toques, silenciar o grupo e
      receber uma mensagem (não avisa) e uma menção (avisa).

## Push (a 1.4.0 saiu sem)

A 1.4.0 está publicada, e as migrações e as Edge Functions estão em produção, mas o push
não funciona ainda, por dois motivos:

- [x] **Firebase:** projeto `sale-abfa7` criado. O `google-services.json` está em
      `android/app/` no Windows e no Linux (copiado em 15/10/2026). O
      `publicar_versao.sh` recusa publicar sem ele.
- [x] **Segredos das Edge Functions** (`SEGREDO_DO_WEBHOOK` e `FIREBASE_CONTA_DE_SERVICO`)
      gravados em 06/10/2026: o relógio do servidor passou de 401 para 200.
- [x] **Publicar a próxima versão** com o Firebase dentro: a 1.5.0 saiu em 15/10/2026,
      do Windows, com `push: ligado`. A chave de release agora está nas duas máquinas.
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
- [x] **Discord ao vivo em produção:** migração `20261010000000_discord_ao_vivo.sql`
      aplicada e `disparar-agendados` e `enviar-chamado` no ar desde 06/10/2026. Para
      subir função sem abrir o Docker, `supabase functions deploy ... --use-api`.
- [ ] **Senha do banco:** trocar no painel do Supabase. A senha atual ficou exposta na
      conversa.

## Ideias que ficaram pela metade

- **Discord com bot:** hoje o Sale? só lê o widget do servidor, sem bot e sem postar
  nada. Um bot permitiria postar o Chamado no canal e responder pelo próprio Discord.
- **Coluna `groups.discord_webhook`:** fica até a 1.4.0 sair dos celulares, que ainda a
  lê. Depois, uma migração a apaga.
