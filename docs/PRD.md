# Sale? — Documento de requisitos

> Versão 0.7 · 03/10/2026 · status: rascunho

## 1. O que é

App Android para chamar os amigos pra jogar. Funciona como um "batsinal": um toque dispara um
**Chamado** que toca forte no celular de quem foi chamado, e cada um responde com um toque
("bora", "chego em 20 min", "tô jantando"). Junto vem um chat de texto estilo WhatsApp e uma
agenda semanal com o encontro fixo do grupo.

## 2. Para quem

- Grupo inicial: 3 amigos, todos com Android e jogando no PC.
- Deve aceitar mais pessoas e mais grupos depois, sem reescrever nada.

### Situações que guiam o produto

Cada pessoa tem as suas: um trabalha até tarde, outro sempre se atrasa, outro quase nunca
está em casa. Por isso o app não traz nomes nem hábitos prontos: cada um digita o próprio
nome e cadastra as próprias situações (3.2).

## 3. Funcionalidades

### 3.1 Chamado (núcleo)

- Quem dispara escolhe:
  - **destino:** uma pessoa, várias ou o grupo todo;
  - **jogo:** um da biblioteca, "qualquer coisa" ou sorteio (fase 2);
  - **quando:** agora ou num horário marcado;
  - **mensagem** opcional ("partida rápida", "só 1 hora").
- Quem recebe:
  - notificação de alta prioridade com som próprio;
  - com o celular bloqueado, abre em **tela cheia**, como uma ligação;
  - responde sem digitar, com os botões de resposta rápida (3.2).
- O Chamado aparece na conversa como um **card vivo**, com a resposta de cada um em tempo real.
- Estados do Chamado: aberto → fechado (todos responderam, quem chamou encerrou ou expirou) ou
  cancelado. Expira **duas horas** depois de tocar: aí a hora de jogar passou, e o card
  diz "expirou" em vez de "encerrado".

### 3.2 Respostas rápidas

- Respostas comuns a todos: ✅ Bora · ⏱️ Chego em 10/20/30 min · ❌ Hoje não · 💤 Me chama daqui a pouco.
- Respostas próprias, que cada pessoa cadastra e remove em "Meu perfil" (ex.: "💼 No trabalho"),
  dizendo se significam "vou já", "vou, mas depois" (pergunta o tempo) ou "não vou".
- O nome exibido também é digitado pela própria pessoa.
- Uma resposta pode pedir tempo estimado; aí vira "chega em ~X min".
- "Me chama daqui a pouco" pergunta daqui a quanto e reagenda o Chamado só
  para quem pediu: na hora, o servidor o faz tocar de novo, e só para ela.

### 3.3 Chat

- Conversas individuais e em grupo.
- Texto, com as marquinhas em cada mensagem que a pessoa manda: um tique quando ela está
  no servidor, dois quando chegou no aparelho de quem vai ler e dois na cor da
  confirmação quando essa pessoa abriu a conversa. No grupo a marca é a do último: só
  anda quando todos receberam, e só fica lida quando todos abriram.
- Mensagem de texto não manda push: ela chega quando o app da outra pessoa está aberto, e
  é isso que o segundo tique diz.
- Na lista de conversas, cada conversa mostra quantas mensagens chegaram depois da última
  vez que a pessoa a abriu.
- Cards de Chamado e de encontro fixo dentro da conversa.

### 3.4 Encontro fixo semanal

- Configurado no app, por grupo: dia da semana, hora e jogo opcional.
- Na hora marcada o servidor dispara o Chamado sozinho, sem ninguém com o app aberto: ele
  chama todo mundo da conversa (ninguém é "quem chamou") e o card diz "Encontro fixo".
  O horário é o do grupo — cada grupo tem o seu fuso. Disparo atrasado mais de 15 minutos
  não vale: servidor que ficou fora do ar não acorda a turma de madrugada.
- Cada um confirma presença com antecedência: vou, talvez ou não vou (com motivo).
- Dá para pular uma semana ou mudar o horário só daquele dia sem mexer no fixo — o disparo
  automático respeita as duas coisas.
- **Duas horas antes**, quem ainda não confirmou recebe um lembrete: uma
  notificação comum no celular (não um Chamado, não toca em tela cheia) e o
  "você vai?" no alto da lista de conversas.

### 3.5 Calendário semanal

- Grade da semana com o encontro fixo, os Chamados agendados e a disponibilidade de cada um.
- Cada pessoa marca as faixas em que costuma estar livre.
- O calendário destaca os horários em que **todos estão livres**.
- Tocar num horário cria um Chamado agendado.

### 3.6 Jogos (fase 2)

- Biblioteca de jogos do grupo (todos de PC), com o mínimo e o máximo de jogadores.
- Cada pessoa marca quais jogos tem.
- Sorteio só entre os jogos que todos os participantes (quem chama e quem é chamado) têm e que
  cabem nesse número de pessoas; cada participante pode vetar uma vez, e o app sorteia outro sem
  repetir os vetados.

### 3.7 Extras (fase 4)

- **Placar do atraso:** quem responde que vem marca **Cheguei** ao chegar, e o app compara
  com o que havia prometido. No Chamado de agora, "Bora!" promete a hora da resposta e
  "chego em 20 min" promete vinte minutos depois dela; no Chamado marcado para mais tarde, a
  conta começa no horário marcado. A hora da chegada é a do servidor. O botão está no card
  do Chamado e, nas primeiras horas depois da promessa, também num aviso na lista de
  conversas.
- **Estatísticas:** quem mais chama, quem mais diz "hoje não" e o jogo mais chamado, junto
  do placar em "Meu perfil → Placar".
- **Insistência:** Chamado sem resposta toca de novo cinco minutos depois, só
  para quem ficou calado, e uma vez por Chamado — o batsinal insiste, não fica
  apitando a noite toda. Chamado que o servidor poupou por atraso não insiste.
- **Soneca:** o "me chama daqui a pouco" de 3.2, pelo mesmo cron do encontro
  fixo (`docs/CRON.md`).

## 4. Fora do escopo por enquanto

- Integração com o Discord além do login (ideia futura: widget do servidor para saber quem está
  na call, webhook para postar o Chamado).
- iPhone.
- Publicação na Play Store: o APK é instalado direto nos celulares.

## 5. Fases

| Fase | Conteúdo |
|---|---|
| 1 — MVP | login com Discord ou Google, perfis, grupos com código de convite, chat individual e em grupo, Chamado com respostas rápidas e notificação em tela cheia |
| 2 — Jogos | biblioteca, jogo no Chamado, sorteio com veto |
| 3 — Agenda | encontro fixo, calendário semanal, disponibilidade, Chamado agendado, o disparo automático no servidor e o lembrete antes da hora |
| 4 — Extras | placar do atraso, estatísticas, soneca e insistência |
| Futuro | Discord |

## 6. Arquitetura

- **App:** Android, em Flutter (decidido em 30/09).
- **Login:** Discord ou Google, pelo Supabase Auth. O login com Discord já serve de ponte para a
  integração futura.
- **Backend:** Supabase — Postgres, Auth, Realtime (chat e cards vivos), Edge Functions e cron
  (encontro fixo e Chamados agendados).
- **Push:** Firebase Cloud Messaging, só para entregar as notificações.
- **Distribuição:** APK instalado direto.

### 6.1 Organização do código

- `lib/domain` — modelos (Chamado, resposta rápida, conversa, mensagem).
- `lib/data` — interface `SaleRepository`, com duas implementações: a em memória, com os
  dados de desenvolvimento (`seed.dart`), e a do Supabase (`supabase_repository.dart`),
  usada quando o APK sai com a configuração do servidor.
- `lib/state` — providers do Riverpod.
- `lib/ui` — telas e widgets.

## 7. Modelo de dados (rascunho)

- `profiles` — id, nome, foto do Discord/Google (com emoji e cor de reserva), token de push.
- `groups` / `group_members` — grupos e quem participa.
- `conversations` / `conversation_members` — conversas individuais ou de grupo; em cada
  membro, até onde ele recebeu e até onde viu as mensagens (as marquinhas, em duas datas
  em vez de uma marca por mensagem).
- `messages` — conversa, autor, tipo (texto, chamado, encontro), conteúdo, criado em.
- `quick_replies` — respostas rápidas: dono (ou nulo = comum a todos), ícone, texto, pede tempo?
- `calls` — Chamados: autor, conversa, jogo, horário, mensagem, estado.
- `call_targets` — quem foi chamado, resposta escolhida, tempo estimado, respondido em,
  chegou em (o "Cheguei" do placar), volta da soneca.
- `games` / `user_games` — biblioteca e quem tem cada jogo (fase 2).
- `weekly_meetings` / `meeting_exceptions` / `meeting_rsvps` / `meeting_fires` /
  `meeting_reminders` — encontro fixo, exceções, confirmações, as ocorrências que o
  servidor já disparou e as que ele já lembrou (fase 3).
- `availability` — faixas livres de cada pessoa por dia da semana (fase 3).

## 8. Aparência

- A marca é um controle com o chamado saindo dele (`assets/marca.svg`), e o mesmo desenho
  serve de ícone na tela inicial e de tela de abertura.
- A cor não é uma só: o app traz sete temas prontos, em claro e escuro, e cada pessoa
  escolhe o seu em "Meu perfil → Aparência". Em todos eles o papel das cores é fixo —
  uma cor para as ações, outra só para o Chamado e outra para a confirmação.

## 9. Perguntas em aberto

- Som do Chamado: falta escolher o arquivo. Hoje toca o som padrão de notificação do
  aparelho, no canal de importância máxima.
