# Sale? — Documento de requisitos

> Versão 0.13 · 05/10/2026 · status: rascunho

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
  - **som:** um da lista do grupo (3.8);
  - **mensagem** opcional ("partida rápida", "só 1 hora").
- Quem recebe:
  - notificação de alta prioridade, no som que quem chamou escolheu;
  - com o celular bloqueado, abre em **tela cheia**, como uma ligação;
  - responde sem digitar, com os botões de resposta rápida (3.2);
  - ou direto pela notificação, sem abrir o app: "Bora!", "Chego em 20" e "Hoje não"
    (o Android cabe três botões; o resto fica a um toque, abrindo o app).
- Atalho no ícone do app ("Chamar o grupo", segurando o ícone na tela inicial): abre o
  Chamado já com a conversa do grupo.
- Quem está por aí: bolinha verde em quem está com o app aberto agora, na lista de
  conversas e na escolha de quem chamar. Sai do "online" quem manda o app para o fundo.
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
- A mensagem avisa no celular de quem não está com o app aberto: notificação comum, em
  canal próprio, com as mensagens novas empilhadas num aviso por conversa. Não é Chamado —
  não abre em tela cheia nem toca como ligação —, e quem está com aquela conversa na tela
  não é avisado dela.
- O segundo tique vale com o celular no bolso: o aparelho que recebe o aviso conta ao
  servidor que a mensagem chegou.
- Na lista de conversas, cada conversa mostra quantas mensagens chegaram depois da última
  vez que a pessoa a abriu.
- Imagem na conversa, da câmera ou da galeria, com legenda opcional: o print da partida,
  a foto do setup. A bolha mostra a miniatura, e um toque abre a imagem em tela cheia, com
  zoom. O arquivo é comprimido antes de subir e cada aparelho o baixa uma vez.
- Recado de voz: com o campo vazio, o botão vira microfone; gravando, uma barra mostra o
  tempo correndo e dá para descartar ou mandar. Na bolha, tocar/pausar com uma barra que
  anda e o tempo. Até cinco minutos; usa o mesmo bucket e download por aparelho da imagem.
- Resposta citada: um toque longo na mensagem e a próxima responde a ela, com a citação
  em cima da bolha. Em grupo de três conversando ao mesmo tempo, "não dá" não diz a que
  pergunta. A citada é sempre da mesma conversa, e apagá-la não leva a resposta com ela.
- Reação na mensagem, no mesmo toque longo: uma fileira de emojis (👍 ❤️ 😂 🔥 😮 😢) e um
  deles vai para o pé da bolha, com a contagem quando mais de um reage. Uma reação por
  pessoa: tocar em outra troca, tocar na sua tira.
- No topo da conversa, quem está digitando ou gravando áudio e, a dois, se o outro está
  online.
- Menção: no grupo, "@" sugere os nomes e "@todos". A menção sai em destaque na bolha, e
  quem foi mencionado recebe um aviso próprio (canal "Menções"), mais alto que o das
  mensagens comuns.
- Mensagem fixada: uma por conversa, numa faixa no topo; tocar mostra inteira. Qualquer um
  da conversa fixa e desafixa; apagar a fixada a tira do topo.
- Busca na conversa: a lupa no topo abre um campo que mostra só as mensagens com o termo,
  com o trecho em destaque. Ignora acento e maiúscula ("nao" acha "não").
- Apagar e editar a própria mensagem, no toque longo. Editada mostra "(editado)"; apagada
  vira uma lápide ("mensagem apagada") sem texto, anexo nem reações, e some da citação de
  quem a respondeu. Só o autor edita e apaga.
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

### 3.8 Som do Chamado

- O app traz cinco sons (Batsinal, Sirene, Telefone, Alarme, Radar), e o grupo pode subir
  os seus: um arquivo de áudio do celular, com um nome, que entra na mesma lista para
  todos. Som do grupo qualquer um do grupo remove; os que vêm no app ficam.
- Quem dispara escolhe o som na tela do Chamado, ouvindo antes de mandar. Já vem marcado
  o som que a pessoa guardou em "Meu perfil → Som do Chamado"; sem escolha nenhuma, toca
  o som da marca (o Batsinal), que é também o do encontro fixo.
- O som acompanha o Chamado: o que ele guarda é a escolha daquele disparo, então som
  removido depois não muda o que já tocou.
- No Android o som é propriedade do canal de notificação e não troca depois de criado, por
  isso cada som tem o canal dele — e todos aparecem juntos, debaixo de "Chamados", nas
  configurações do aparelho, onde dá para desligar um sem perder os outros.
- Som do grupo só toca num aparelho depois que o app abriu lá uma vez e o baixou. Até
  então o Chamado dele toca o som da marca: ninguém fica sem aviso por causa de um
  arquivo que não chegou.

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
- `sounds` — a lista de sons: `group_id` nulo = vem no app; preenchido = do grupo, com o
  arquivo no Storage. O som escolhido fica em `chamados.sound_key` (a chave com que o app
  toca) e o padrão de cada pessoa em `profiles.sound_id`.
- `message_reactions` — a reação de cada pessoa em cada mensagem (uma por pessoa, que é a
  chave da tabela).
- `messages` — conversa, autor, tipo (texto, chamado, encontro), conteúdo, criado em. A
  mensagem de gente precisa de texto, de anexo, ou dos dois (a imagem com legenda); o anexo
  guarda o caminho no Storage, o tipo e o tamanho da imagem. `reply_to` aponta para a
  mensagem citada, sempre da mesma conversa.
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

- Nenhuma. O som do Chamado, que era a última, virou a seção 3.8: os cinco sons que vêm
  no app foram gerados por síntese (ver `docs/SONS.md`) e são trocáveis sem mexer em
  código.
- Ideias que ficaram anotadas, sem decisão: som próprio do encontro fixo (hoje ele toca o
  da marca) e som escolhido por quem recebe, em vez de por quem chama.
