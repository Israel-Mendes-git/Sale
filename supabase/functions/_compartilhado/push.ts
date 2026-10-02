// O envio do Chamado pelo Firebase, usado por quem dispara: o webhook do
// Chamado de agora (enviar-chamado) e o cron do que estava marcado para
// depois (disparar-agendados).
//
// A mensagem vai sem título e sem corpo, só com dados: quem monta a
// notificação é o app, porque ela precisa ser de tela cheia, como uma
// ligação — e isso o Android só deixa o próprio aplicativo fazer.

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
};

/// Os campos que o push precisa; serve para o cron reler do banco.
export const camposDoChamado =
  'id, conversation_id, author_id, game_name, note, automatic';

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
export async function enviarChamado(
  db: SupabaseClient,
  chamado: Chamado,
): Promise<{ enviados: number; limpos: number }> {
  const [{ data: alvos }, { data: autor }] = await Promise.all([
    db.from('chamado_targets').select('user_id').eq('chamado_id', chamado.id),
    db.from('profiles').select('name').eq('id', chamado.author_id).single(),
  ]);
  const ids = (alvos ?? []).map((a: { user_id: string }) => a.user_id);
  if (ids.length === 0) return { enviados: 0, limpos: 0 };

  const { data: aparelhos } = await db
    .from('device_tokens')
    .select('token, user_id')
    .in('user_id', ids);
  if (!aparelhos?.length) return { enviados: 0, limpos: 0 };

  const acesso = await tokenDoFirebase();
  const envio =
    `https://fcm.googleapis.com/v1/projects/${contaDeServico.project_id}/messages:send`;
  const dados = {
    chamadoId: chamado.id,
    conversaId: chamado.conversation_id,
    autor: autor?.name ?? 'Alguém',
    jogo: chamado.game_name ?? '',
    nota: chamado.note ?? '',
    // O encontro fixo não tem ninguém chamando: o app escreve o aviso de
    // outro jeito.
    automatico: chamado.automatic ? '1' : '',
  };

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
          android: { priority: 'HIGH', ttl: '600s' },
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
