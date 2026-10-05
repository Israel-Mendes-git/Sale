// O envio pelo Firebase, usado por quem dispara: o webhook do Chamado de
// agora (enviar-chamado) e o cron do resto (disparar-agendados) — o Chamado
// marcado, o encontro fixo, a insistência, a soneca e o lembrete.
//
// A mensagem vai sem título e sem corpo, só com dados: quem monta a
// notificação é o app, porque a do Chamado precisa ser de tela cheia, como
// uma ligação — e isso o Android só deixa o próprio aplicativo fazer.

import { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { JWT } from 'npm:google-auth-library@9';

const contaDeServico = JSON.parse(
  Deno.env.get('FIREBASE_CONTA_DE_SERVICO') ?? '{}',
);

export type Chamado = {
  id: string;
  conversation_id: string;
  author_id: string;
  game_name: string | null;
  note: string | null;
  automatic?: boolean;
  sound_key?: string | null;
};

/// Os campos que o push precisa; serve para o cron reler do banco.
export const camposDoChamado =
  'id, conversation_id, author_id, game_name, note, automatic, sound_key';

/// O token de acesso do Firebase vale uma hora; guardamos entre chamadas.
let token: { valor: string; expiraEm: number } | null = null;

async function tokenDoFirebase(): Promise<string> {
  const agora = Date.now();
  if (token && token.expiraEm > agora + 60_000) return token.valor;

  const jwt = new JWT({
    email: contaDeServico.client_email,
    key: contaDeServico.private_key,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  });
  const { access_token: acesso } = await jwt.authorize();
  if (!acesso) throw new Error('o Firebase não devolveu o token de acesso');
  token = { valor: acesso, expiraEm: agora + 55 * 60_000 };
  return acesso;
}

/// Manda o Chamado para o celular de quem foi chamado. Devolve quantos
/// envios saíram e quantos aparelhos sumiram do caminho.
///
/// `apenas` limita a quem notificar: a soneca e a insistência tocam só para
/// algumas pessoas, não para a roda toda. `motivo` é o que o app escreve na
/// notificação ('soneca', 'insistencia', 'encontro', 'marcado').
export async function enviarChamado(
  db: SupabaseClient,
  chamado: Chamado,
  { apenas, motivo }: { apenas?: string[] | null; motivo?: string } = {},
): Promise<{ enviados: number; limpos: number }> {
  const [{ data: alvos }, { data: autor }] = await Promise.all([
    db.from('chamado_targets').select('user_id').eq('chamado_id', chamado.id),
    db.from('profiles').select('name').eq('id', chamado.author_id).single(),
  ]);
  const todos = (alvos ?? []).map((a: { user_id: string }) => a.user_id);
  const ids = apenas?.length
    ? todos.filter((id: string) => apenas.includes(id))
    : todos;

  // O Chamado que toca para a roda toda também vai para o canal do Discord;
  // a insistência e a soneca, que são só para alguns, não.
  if (!apenas?.length) {
    await postarNoDiscord(db, chamado, autor?.name ?? 'Alguém');
  }

  return await mandar(db, ids, {
    tipo: 'chamado',
    chamadoId: chamado.id,
    conversaId: chamado.conversation_id,
    autor: autor?.name ?? 'Alguém',
    jogo: chamado.game_name ?? '',
    nota: chamado.note ?? '',
    // O encontro fixo não tem ninguém chamando: o app escreve o aviso de
    // outro jeito.
    automatico: chamado.automatic ? '1' : '',
    // Por que está tocando. Vazio = Chamado novo, chegando na hora.
    motivo: motivo ?? '',
    // Com que som tocar: o canal de notificação que o app criou para ele.
    // Vazio, ou som que este aparelho ainda não baixou, toca o da marca.
    som: chamado.sound_key ?? '',
    // Chamado perdido não serve de nada: dez minutos e a mensagem morre.
  }, '600s');
}

/// Posta o Chamado no canal do Discord do grupo, se o grupo tiver um. Falhar
/// aqui não segura o push de ninguém.
async function postarNoDiscord(
  db: SupabaseClient,
  chamado: Chamado,
  autor: string,
): Promise<void> {
  const { data } = await db
    .from('conversations')
    .select('groups(discord_webhook)')
    .eq('id', chamado.conversation_id)
    .single();
  const grupo = data?.groups as { discord_webhook?: string | null } | null;
  const webhook = grupo?.discord_webhook;
  if (!webhook) return;
  const jogo = chamado.game_name ? ` pra jogar **${chamado.game_name}**` : ' pra jogar';
  const linhas = [
    chamado.automatic
      ? `🔔 Hora do encontro do grupo${jogo}!`
      : `🔔 **${autor}** está chamando${jogo}!`,
  ];
  if (chamado.note) linhas.push(`> ${chamado.note}`);
  try {
    const resposta = await fetch(webhook, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: 'Sale?', content: linhas.join('\n') }),
    });
    if (!resposta.ok) {
      console.error('o Discord recusou', resposta.status, await resposta.text());
    }
  } catch (e) {
    console.error('não deu para postar no Discord', e);
  }
}

export type Lembrete = {
  meeting_id: string;
  conversation_id: string;
  hora: string;
  jogo: string | null;
  alvos: string[] | null;
};

/// O lembrete do encontro fixo, para quem ainda não confirmou presença.
///
/// Não é Chamado: o app monta um aviso comum, que não toca em tela cheia nem
/// espera resposta na hora. A hora vai como data, e quem a escreve no fuso de
/// quem lê é o próprio app.
export async function enviarLembrete(
  db: SupabaseClient,
  lembrete: Lembrete,
): Promise<{ enviados: number; limpos: number }> {
  return await mandar(db, lembrete.alvos ?? [], {
    tipo: 'lembrete',
    conversaId: lembrete.conversation_id,
    hora: lembrete.hora,
    jogo: lembrete.jogo ?? '',
    // O lembrete ainda vale se o celular só ligar meia hora depois; o que
    // não vale é chegar depois do encontro.
  }, '3600s');
}

export type Mensagem = {
  id: string;
  conversation_id: string;
  author_id: string;
  body: string | null;
  chamado_id: string | null;
  attachment_kind?: string | null;
  mentions?: string[] | null;
};

/// O que o aviso diz da mensagem: o texto, ou a legenda, ou o que veio
/// anexado — imagem e recado de voz também avisam.
function textoDoAviso(mensagem: Mensagem): string {
  const texto = mensagem.body?.trim() ?? '';
  if (texto) return texto;
  if (mensagem.attachment_kind === 'audio') return '🎤 Recado de voz';
  if (mensagem.attachment_kind === 'image') return '📷 Foto';
  return '';
}

/// A mensagem de texto do chat chegando no celular de quem não está com o app
/// aberto.
///
/// Não é Chamado: o app monta um aviso comum, que não toca em tela cheia nem
/// espera resposta na hora. Card de Chamado dentro da conversa não passa por
/// aqui — ele já tem o push dele, que é o do batsinal.
export async function enviarMensagem(
  db: SupabaseClient,
  mensagem: Mensagem,
): Promise<{ enviados: number; limpos: number }> {
  const texto = textoDoAviso(mensagem);
  if (!texto) return { enviados: 0, limpos: 0 };

  const [{ data: membros }, { data: autor }] = await Promise.all([
    db
      .from('conversation_members')
      .select('user_id')
      .eq('conversation_id', mensagem.conversation_id),
    db.from('profiles').select('name').eq('id', mensagem.author_id).single(),
  ]);

  // Quem escreveu não é avisado da própria mensagem.
  const ids = (membros ?? [])
    .map((m: { user_id: string }) => m.user_id)
    .filter((id: string) => id !== mensagem.author_id);

  const dados = {
    tipo: 'mensagem',
    mensagemId: mensagem.id,
    conversaId: mensagem.conversation_id,
    autorId: mensagem.author_id,
    autor: autor?.name ?? 'Alguém',
    texto,
  };
  // Mensagem de chat continua valendo depois: o celular que passou a noite
  // sem rede ainda tem o que ler quando voltar.
  const validade = '86400s';

  // Quem foi mencionado leva o aviso de menção, mais alto; o resto, o comum.
  // A lista vem de quem escreveu, mas só avisa quem está na conversa.
  const mencionados = new Set(mensagem.mentions ?? []);
  const [comMencao, semMencao] = await Promise.all([
    mandar(
      db,
      ids.filter((id: string) => mencionados.has(id)),
      { ...dados, mencao: '1' },
      validade,
    ),
    mandar(
      db,
      ids.filter((id: string) => !mencionados.has(id)),
      dados,
      validade,
    ),
  ]);
  return {
    enviados: comMencao.enviados + semMencao.enviados,
    limpos: comMencao.limpos + semMencao.limpos,
  };
}

export type Destaque = {
  conversation_id: string;
  dia: string;
  message_id: string | null;
  votos: number;
};

/// A do dia escolhida: o aviso vai para todo mundo da conversa do grupo, com
/// quem escreveu e o que era. Aviso comum, como o da mensagem.
export async function enviarDestaque(
  db: SupabaseClient,
  destaque: Destaque,
): Promise<{ enviados: number; limpos: number }> {
  if (!destaque.message_id) return { enviados: 0, limpos: 0 };
  const [{ data: membros }, { data: mensagem }] = await Promise.all([
    db
      .from('conversation_members')
      .select('user_id')
      .eq('conversation_id', destaque.conversation_id),
    db
      .from('messages')
      .select('body, attachment_kind, author:profiles(name)')
      .eq('id', destaque.message_id)
      .single(),
  ]);
  if (!mensagem) return { enviados: 0, limpos: 0 };
  const ids = (membros ?? []).map((m: { user_id: string }) => m.user_id);
  const autor = (mensagem.author as { name?: string } | null)?.name ?? 'Alguém';
  return await mandar(db, ids, {
    tipo: 'destaque',
    conversaId: destaque.conversation_id,
    mensagemId: destaque.message_id,
    autor,
    texto: textoDoAviso({
      id: destaque.message_id,
      conversation_id: destaque.conversation_id,
      author_id: '',
      body: mensagem.body,
      chamado_id: null,
      attachment_kind: mensagem.attachment_kind,
    }),
    votos: String(destaque.votos),
  }, '86400s');
}

export type Resumo = { conversation_id: string; texto: string };

/// O resumo da semana, para todo mundo da conversa do grupo. Aviso comum.
export async function enviarResumo(
  db: SupabaseClient,
  resumo: Resumo,
): Promise<{ enviados: number; limpos: number }> {
  const { data: membros } = await db
    .from('conversation_members')
    .select('user_id')
    .eq('conversation_id', resumo.conversation_id);
  const ids = (membros ?? []).map((m: { user_id: string }) => m.user_id);
  return await mandar(db, ids, {
    tipo: 'resumo',
    conversaId: resumo.conversation_id,
    texto: resumo.texto,
    // Resumo de domingo lido na segunda ainda vale; na outra semana, não.
  }, '86400s');
}

/// Manda os dados para os aparelhos de [ids]. Devolve quantos envios saíram e
/// quantos aparelhos sumiram do caminho.
async function mandar(
  db: SupabaseClient,
  ids: string[],
  dados: Record<string, string>,
  ttl: string,
): Promise<{ enviados: number; limpos: number }> {
  if (ids.length === 0) return { enviados: 0, limpos: 0 };

  const { data: aparelhos } = await db
    .from('device_tokens')
    .select('token, user_id')
    .in('user_id', ids);
  if (!aparelhos?.length) return { enviados: 0, limpos: 0 };

  const acesso = await tokenDoFirebase();
  const envio =
    `https://fcm.googleapis.com/v1/projects/${contaDeServico.project_id}/messages:send`;

  let enviados = 0;
  const mortos: string[] = [];
  for (const aparelho of aparelhos) {
    const resposta = await fetch(envio, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${acesso}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: aparelho.token,
          data: dados,
          // Alta prioridade acorda o app mesmo parado; sem isso o Android
          // segura a mensagem até a próxima vez que ele abrir.
          android: { priority: 'HIGH', ttl },
        },
      }),
    });
    if (resposta.ok) {
      enviados++;
    } else if (resposta.status === 404 || resposta.status === 400) {
      // Aparelho que desinstalou o app ou trocou de token.
      mortos.push(aparelho.token);
    } else {
      console.error('falhou o envio', resposta.status, await resposta.text());
    }
  }

  if (mortos.length) {
    await db.from('device_tokens').delete().in('token', mortos);
  }
  return { enviados, limpos: mortos.length };
}
