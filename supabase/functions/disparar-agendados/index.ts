// O relógio do grupo: dispara o encontro fixo, os Chamados marcados para
// depois, a insistência e a soneca, sem ninguém com o app aberto.
//
// Quem acorda esta função é um cron, de minuto em minuto (ver docs/CRON.md).
// Ela pergunta ao banco o que venceu — `disparar_pendentes()` cria o Chamado
// do encontro, libera os marcados, insiste com quem não respondeu e acorda
// quem pediu soneca — e manda o push de cada um, para quem o banco apontar.
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

  // Cada linha é um push: o Chamado e quem notificar nele (nulo = todo
  // mundo que foi chamado).
  const fila = (pendentes ?? []) as {
    chamado_id: string;
    alvos: string[] | null;
    motivo: string;
  }[];
  if (fila.length === 0) return Response.json({ chamados: 0, enviados: 0 });

  const { data: chamados } = await db
    .from('chamados')
    .select(camposDoChamado)
    .in('id', fila.map((p) => p.chamado_id));
  const porId = new Map(
    ((chamados ?? []) as Chamado[]).map((c) => [c.id, c]),
  );

  let enviados = 0;
  let limpos = 0;
  for (const pendente of fila) {
    const chamado = porId.get(pendente.chamado_id);
    if (!chamado) continue;
    const resultado = await enviarChamado(db, chamado, {
      apenas: pendente.alvos,
      motivo: pendente.motivo,
    });
    enviados += resultado.enviados;
    limpos += resultado.limpos;
  }
  return Response.json({ chamados: fila.length, enviados, limpos });
});
