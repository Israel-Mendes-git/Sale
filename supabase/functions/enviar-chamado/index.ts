// Manda o push de um Chamado assim que ele nasce.
//
// Quem chama esta função é o banco: um webhook em `chamados`, depois de
// inserir. Ela roda com a service_role (lê os aparelhos de todo mundo), por
// isso confere um segredo antes de fazer qualquer coisa.
//
// O envio em si mora em ../_compartilhado/push.ts, porque o cron do Chamado
// marcado para depois (disparar-agendados) manda do mesmo jeito.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { Chamado, enviarChamado } from '../_compartilhado/push.ts';

const url = Deno.env.get('SUPABASE_URL')!;
const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const segredo = Deno.env.get('SEGREDO_DO_WEBHOOK')!;

const db = createClient(url, serviceRole);

Deno.serve(async (req) => {
  if (req.headers.get('x-sale-segredo') !== segredo) {
    return new Response('não autorizado', { status: 401 });
  }

  const { record: chamado } = await req.json() as { record: Chamado & {
    scheduled_for: string | null;
  } };
  if (!chamado?.id) return new Response('sem Chamado', { status: 400 });

  // Chamado marcado para depois é tarefa do cron, não deste disparo.
  if (chamado.scheduled_for && new Date(chamado.scheduled_for) > new Date()) {
    return Response.json({ enviados: 0, motivo: 'agendado' });
  }

  return Response.json(await enviarChamado(db, chamado));
});
