// Manda o push de um Chamado para quem foi chamado.
//
// Quem chama esta função é o banco: um webhook em `chamados`, depois de
// inserir. Ela roda com a service_role (lê os aparelhos de todo mundo), por
// isso confere um segredo antes de fazer qualquer coisa.
//
// O push vai sem título nem corpo, só com dados: quem monta a notificação é
// o app, porque ela precisa ser de tela cheia, como uma ligação — e isso o
// Android só deixa o próprio aplicativo fazer.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { JWT } from 'npm:google-auth-library@9';

const url = Deno.env.get('SUPABASE_URL')!;
const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const segredo = Deno.env.get('SEGREDO_DO_WEBHOOK')!;
const contaDeServico = JSON.parse(
  Deno.env.get('FIREBASE_CONTA_DE_SERVICO') ?? '{}',
);

const db = createClient(url, serviceRole);

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

Deno.serve(async (req) => {
  if (req.headers.get('x-sale-segredo') !== segredo) {
    return new Response('não autorizado', { status: 401 });
  }

  const { record: chamado } = await req.json();
  if (!chamado?.id) return new Response('sem Chamado', { status: 400 });

  // Chamado marcado para depois é tarefa do cron, não deste disparo.
  if (chamado.scheduled_for && new Date(chamado.scheduled_for) > new Date()) {
    return Response.json({ enviados: 0, motivo: 'agendado' });
  }

  const [{ data: alvos }, { data: autor }] = await Promise.all([
    db.from('chamado_targets').select('user_id').eq('chamado_id', chamado.id),
    db.from('profiles').select('name').eq('id', chamado.author_id).single(),
  ]);
  const ids = (alvos ?? []).map((a: { user_id: string }) => a.user_id);
  if (ids.length === 0) return Response.json({ enviados: 0 });

  const { data: aparelhos } = await db
    .from('device_tokens')
    .select('token, user_id')
    .in('user_id', ids);
  if (!aparelhos?.length) return Response.json({ enviados: 0 });

  const acesso = await tokenDoFirebase();
  const envio = `https://fcm.googleapis.com/v1/projects/${contaDeServico.project_id}/messages:send`;
  const dados = {
    chamadoId: chamado.id,
    conversaId: chamado.conversation_id,
    autor: autor?.name ?? 'Alguém',
    jogo: chamado.game_name ?? '',
    nota: chamado.note ?? '',
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
  return Response.json({ enviados, limpos: mortos.length });
});
