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
};

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
  if (!mensagem.body) return { enviados: 0, limpos: 0 };

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

  return await mandar(db, ids, {
    tipo: 'mensagem',
    mensagemId: mensagem.id,
    conversaId: mensagem.conversation_id,
    autorId: mensagem.author_id,
    autor: autor?.name ?? 'Alguém',
    texto: mensagem.body,
    // Mensagem de chat continua valendo depois: o celular que passou a noite
    // sem rede ainda tem o que ler quando voltar.
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
