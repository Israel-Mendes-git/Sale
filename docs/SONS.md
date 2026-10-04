# Os sons do Chamado

O Chamado toca o som que quem chamou escolheu. São dois tipos: os que vêm no app, dentro
do APK, e os que o grupo sobe, que ficam no Storage e cada aparelho baixa uma vez.

## Onde moram os sons que vêm no app

Cada som é o mesmo arquivo em dois lugares, porque quem o toca são dois:

| Lugar | Quem toca | Por quê |
|---|---|---|
| `android/app/src/main/res/raw/<chave>.ogg` | o Android, na notificação | o som é propriedade do canal de notificação, e o sistema o lê do APK |
| `assets/sons/<chave>.ogg` | o app, na prévia | é o "ouvir antes de escolher", nas telas do Chamado e do perfil |

A chave (`batsinal`, `sirene`, …) aparece em três lugares, e os três precisam combinar:

1. o nome dos dois arquivos acima;
2. `builtInSounds`, em `lib/domain/sounds.dart` (a chave e o nome que a pessoa lê);
3. a linha da tabela `sounds` com `group_id` nulo, na migração dos sons.

## Trocar um som por um melhor

Nada de código: troque os dois arquivos, mantendo a chave e a extensão.

```sh
ffmpeg -i sirene-nova.wav -ac 1 -ar 44100 -c:a libvorbis -q:a 2 assets/sons/sirene.ogg
cp assets/sons/sirene.ogg android/app/src/main/res/raw/sirene.ogg
```

Quem já tem o app instalado continua ouvindo o som antigo até atualizar o APK: o canal
guarda o endereço do arquivo, e o arquivo vem dentro dele.

## Como os cinco de hoje foram feitos

Não são gravações: são sintetizados por `ffmpeg`, o suficiente para o recurso andar de
ponta a ponta. São para trocar sem cerimônia — alguns segundos de seno não competem com um
som gravado com cuidado.

```sh
# Batsinal: dois "whoops" subindo, como o sinal acendendo.
ffmpeg -f lavfi -i "aevalsrc='0.6*sin(2*PI*(260+900*pow(mod(t,1.2)/1.2,1.5))*t)*between(mod(t,1.2),0,0.85)*(1-0.3*mod(t,1.2))':d=2.4:s=44100" -ac 1 -c:a libvorbis -q:a 2 assets/sons/batsinal.ogg

# Sirene: a frequência indo e voltando.
ffmpeg -f lavfi -i "aevalsrc='0.55*sin(2*PI*(700+260*sin(2*PI*1.6*t))*t)':d=3:s=44100" -ac 1 -c:a libvorbis -q:a 2 assets/sons/sirene.ogg

# Telefone antigo: dois tons juntos, pulsando.
ffmpeg -f lavfi -i "aevalsrc='0.3*(sin(2*PI*440*t)+sin(2*PI*480*t))*lt(mod(t,0.14),0.07)*between(mod(t,2),0,1.1)':d=3:s=44100" -ac 1 -c:a libvorbis -q:a 2 assets/sons/telefone.ogg

# Alarme: bipes curtos e agudos.
ffmpeg -f lavfi -i "aevalsrc='0.5*sin(2*PI*1180*t)*lt(mod(t,0.3),0.14)':d=2.4:s=44100" -ac 1 -c:a libvorbis -q:a 2 assets/sons/alarme.ogg

# Radar: um bip com cauda longa, espaçado.
ffmpeg -f lavfi -i "aevalsrc='0.6*sin(2*PI*880*t)*exp(-7*mod(t,1.1))':d=3.3:s=44100" -ac 1 -c:a libvorbis -q:a 2 assets/sons/radar.ogg
```

Depois de gerar, copie todos para `res/raw`:

```sh
cp assets/sons/*.ogg android/app/src/main/res/raw/
```

## Pôr um som novo na lista do app

Além dos dois arquivos e da entrada em `builtInSounds`, o som precisa existir no banco:

```sql
insert into public.sounds (name, file) values ('Buzina', 'buzina');
```

Vale mais a pena como som do grupo (abaixo), que entra pelo app, sem migração nem APK
novo. A lista do app é só o que vem de fábrica.

## Os sons do grupo

Quem está no grupo escolhe um arquivo de áudio do celular em **Meu perfil → Som do
Chamado → Som novo**. O caminho dele:

1. o app sobe o arquivo para o bucket `sons`, em `<grupo>/<arquivo>`, e insere a linha em
   `sounds` com o `group_id` do grupo (até 2 MB — é um toque, não um disco);
2. em cada aparelho, na próxima vez que o app abrir, o som é baixado, registrado no acervo
   de sons do aparelho (`MainActivity.kt`, via MediaStore) e ganha um canal de notificação
   com esse endereço;
3. a partir daí o Chamado com esse som toca nele, inclusive com o app fechado.

O registro no acervo existe porque quem monta o som da notificação é o sistema, e ele não
lê a pasta privada do app. Em Android anterior ao 10 isso pediria acesso a todos os
arquivos do aparelho, e aí o app não registra: o Chamado toca o som da marca.

Som do grupo que um aparelho ainda não baixou também toca o som da marca. Não é erro: é o
app não ter aberto lá desde que o som entrou na lista.

Quando alguém remove um som da lista, cada aparelho apaga o canal e o arquivo baixado na
próxima vez que o app abrir. A entrada no acervo de sons do aparelho fica para trás — ela
não duplica se o som voltar, e quem quiser pode apagá-la pelo gerenciador de arquivos, em
`Notifications/Sale`.
