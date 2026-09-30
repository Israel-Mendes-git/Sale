# Sale? — Documento de requisitos

> Versão 0.1 · 30/09/2026 · status: rascunho

## 1. O que é

App Android para chamar os amigos pra jogar. Funciona como um "batsinal": um toque dispara um
**Chamado** que toca forte no celular de quem foi chamado, e cada um responde com um toque
("bora", "chego em 20 min", "tô jantando"). Junto vem um chat de texto estilo WhatsApp e uma
agenda semanal com o encontro fixo do grupo.

## 2. Para quem

- Grupo inicial: 3 amigos (Israel, Beto e Caio), todos com Android e jogando no PC.
- Deve aceitar mais pessoas e mais grupos depois, sem reescrever nada.

### Perfis de uso que guiam o produto

| Pessoa | Situações comuns |
|---|---|
| Israel | no trabalho, já jogando |
| Beto | se atrasa: tá na casa da namorada, passeando com os gatos, jantando |
| Caio | fora de casa, ocupado, tem que sair |

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
  cancelado.

### 3.2 Respostas rápidas

- Respostas comuns a todos: ✅ Bora · ⏱️ Chego em 10/20/30 min · ❌ Hoje não · 💤 Me chama daqui a pouco.
- Respostas próprias de cada pessoa, editáveis no perfil (ex.: "🐈 Passeando com os gatos").
- Uma resposta pode pedir tempo estimado; aí vira "chega em ~X min".
- "Me chama daqui a pouco" reagenda o Chamado só para quem pediu.

### 3.3 Chat

- Conversas individuais e em grupo.
- Texto, com status de entregue/lido.
- Cards de Chamado e de encontro fixo dentro da conversa.

### 3.4 Encontro fixo semanal

- Configurado no app, por grupo: dia da semana, hora e jogo opcional.
- Lembrete antes (ex.: 2 h antes) e Chamado disparado automaticamente na hora.
- Cada um confirma presença com antecedência: vou, talvez ou não vou (com motivo).
- Dá para pular uma semana ou mudar o horário só daquele dia sem mexer no fixo.

### 3.5 Calendário semanal

- Grade da semana com o encontro fixo, os Chamados agendados e a disponibilidade de cada um.
- Cada pessoa marca as faixas em que costuma estar livre.
- O calendário destaca os horários em que **todos estão livres**.
- Tocar num horário cria um Chamado agendado.

### 3.6 Jogos (fase 2)

- Biblioteca de jogos do grupo (todos de PC), com o mínimo e o máximo de jogadores.
- Cada pessoa marca quais jogos tem.
- Sorteio só entre os jogos que cabem em quem confirmou e que todos têm; cada um pode vetar uma vez.

### 3.7 Extras (fase 5)

- Insistência: o Chamado toca de novo se ninguém responder em X min.
- Placar do atraso: compara o "chego em X min" com a chegada real.
- Estatísticas: quem mais chama, quem mais recusa, jogo mais jogado.

## 4. Fora do escopo por enquanto

- Integração com o Discord (anotada como ideia futura: login com Discord, widget do servidor
  para saber quem está na call, webhook para postar o Chamado).
- iPhone.
- Publicação na Play Store: o APK é instalado direto nos celulares.

## 5. Fases

| Fase | Conteúdo |
|---|---|
| 1 — MVP | login, perfis, chat individual e em grupo, Chamado com respostas rápidas, notificação em tela cheia |
| 2 — Jogos | biblioteca, jogo no Chamado, sorteio |
| 3 — Agenda | encontro fixo, calendário semanal, disponibilidade, Chamado agendado |
| 4 — Extras | soneca, insistência, placar do atraso, estatísticas |
| Futuro | Discord |

## 6. Arquitetura (proposta)

- **App:** Android, framework a definir (ver 6.1).
- **Backend:** Supabase — Postgres, Auth, Realtime (chat e cards vivos), Edge Functions e cron
  (encontro fixo e Chamados agendados).
- **Push:** Firebase Cloud Messaging, só para entregar as notificações.
- **Distribuição:** APK instalado direto.

### 6.1 Framework do app — decisão pendente

| | Expo / React Native | Flutter |
|---|---|---|
| Ambiente na máquina | já existe (distrobox `mobiledev`, Node, build na nuvem pelo EAS) | instalar Flutter, JDK e Android SDK |
| Linguagem | TypeScript, a mesma das Edge Functions | Dart |
| Tela cheia estilo ligação | biblioteca `notifee` com build de desenvolvimento | `flutter_local_notifications` com `fullScreenIntent` |

## 7. Modelo de dados (rascunho)

- `profiles` — id, nome, apelido, avatar, token de push.
- `groups` / `group_members` — grupos e quem participa.
- `conversations` / `conversation_members` — conversas individuais ou de grupo.
- `messages` — conversa, autor, tipo (texto, chamado, encontro), conteúdo, criado em.
- `quick_replies` — respostas rápidas: dono (ou nulo = comum a todos), emoji, texto, pede tempo?
- `calls` — Chamados: autor, conversa, jogo, horário, mensagem, estado.
- `call_targets` — quem foi chamado, resposta escolhida, tempo estimado, respondido em.
- `games` / `user_games` — biblioteca e quem tem cada jogo (fase 2).
- `weekly_meetings` / `meeting_exceptions` / `meeting_rsvps` — encontro fixo, exceções e
  confirmações (fase 3).
- `availability` — faixas livres de cada pessoa por dia da semana (fase 3).

## 8. Perguntas em aberto

- Framework do app (6.1).
- Login do MVP: e-mail com link mágico, Google ou conta criada à mão para os 3?
- Tempo até o Chamado expirar.
- Ícone, cores e som do Chamado.
