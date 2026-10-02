// O relógio do grupo: dispara o encontro fixo e os Chamados marcados para
// depois, sem ninguém com o app aberto.
//
// Quem acorda esta função é um cron, de minuto em minuto (ver docs/CRON.md).
// Ela pergunta ao banco o que venceu — `disparar_pendentes()` cria o Chamado
// do encontro e libera os marcados — e manda o push de cada um.
//
// Rodar atrasado não faz mal: a função do banco ignora o que passou da
// janela e nunca dispara a mesma ocorrência duas vezes.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { camposDoChamado, Chamado, enviarChamado } from '../_compartilhado/push.ts';

const url = Deno.env.get('SUPABASE_URL')!;
const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const segredo = Deno.env.get('SEGREDO_DO_WEBHOOK')!;

const db = createClient(url, serviceRole);

Deno.serve(async (req) => {
  if (req.headers.get('x-sale-segredo') !== segredo) {
    return new Response('não autorizado', { status: 401 });
  }

  const { data: pendentes, error } = await db.rpc('disparar_pendentes');
  if (error) {
    console.error('o banco recusou o disparo', error);
    return new Response(error.message, { status: 500 });
  }

  const ids = (pendentes ?? []).map((p: { chamado_id: string }) => p.chamado_id);
  if (ids.length === 0) return Response.json({ chamados: 0, enviados: 0 });

  const { data: chamados } = await db
    .from('chamados')
    .select(camposDoChamado)
    .in('id', ids);

  let enviados = 0;
  let limpos = 0;
  for (const chamado of (chamados ?? []) as Chamado[]) {
    const resultado = await enviarChamado(db, chamado);
    enviados += resultado.enviados;
    limpos += resultado.limpos;
  }
  return Response.json({ chamados: ids.length, enviados, limpos });
});
