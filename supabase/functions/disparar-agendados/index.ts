// O relógio do grupo: dispara o encontro fixo, os Chamados marcados para
// depois, a insistência, a soneca e o lembrete do encontro, fecha o Chamado
// que ficou aberto tempo demais, e tudo sem ninguém com o app aberto.
//
// Quem acorda esta função é um cron, de minuto em minuto (ver docs/CRON.md).
// Ela pergunta ao banco o que venceu — `expirar_chamados()` fecha o que passou
// da hora, `disparar_pendentes()` cria o Chamado do encontro, libera os
// marcados, insiste com quem não respondeu e acorda quem pediu soneca, e
// `lembretes_pendentes()` devolve o encontro que está chegando — e manda o
// push de cada um, para quem o banco apontar.
//
// Rodar atrasado não faz mal: a função do banco ignora o que passou da
// janela e nunca dispara a mesma ocorrência duas vezes.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import {
  camposDoChamado,
  Chamado,
  enviarChamado,
  enviarLembrete,
  Lembrete,
} from '../_compartilhado/push.ts';

const url = Deno.env.get('SUPABASE_URL')!;
const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const segredo = Deno.env.get('SEGREDO_DO_WEBHOOK')!;

const db = createClient(url, serviceRole);

Deno.serve(async (req) => {
  if (req.headers.get('x-sale-segredo') !== segredo) {
    return new Response('não autorizado', { status: 401 });
  }

  // Primeiro o que fecha, depois o que toca: Chamado que está expirando não
  // insiste com ninguém nem acorda quem pediu soneca.
  const { data: expirados, error: erroDaExpiracao } = await db.rpc(
    'expirar_chamados',
  );
  if (erroDaExpiracao) {
    console.error('o banco recusou a expiração', erroDaExpiracao);
    return new Response(erroDaExpiracao.message, { status: 500 });
  }

  const { data: pendentes, error } = await db.rpc('disparar_pendentes');
  if (error) {
    console.error('o banco recusou o disparo', error);
    return new Response(error.message, { status: 500 });
  }

  // O lembrete do encontro não é Chamado, mas vence no mesmo relógio.
  const { data: lembretes, error: erroDoLembrete } = await db.rpc(
    'lembretes_pendentes',
  );
  if (erroDoLembrete) {
    console.error('o banco recusou o lembrete', erroDoLembrete);
    return new Response(erroDoLembrete.message, { status: 500 });
  }

  // Cada linha é um push: o Chamado e quem notificar nele (nulo = todo
  // mundo que foi chamado).
  const fila = (pendentes ?? []) as {
    chamado_id: string;
    alvos: string[] | null;
    motivo: string;
  }[];
  const avisos = (lembretes ?? []) as Lembrete[];
  if (fila.length === 0 && avisos.length === 0) {
    return Response.json({ chamados: 0, lembretes: 0, enviados: 0, expirados });
  }

  const porId = new Map<string, Chamado>();
  if (fila.length > 0) {
    const { data: chamados } = await db
      .from('chamados')
      .select(camposDoChamado)
      .in('id', fila.map((p) => p.chamado_id));
    for (const chamado of (chamados ?? []) as Chamado[]) {
      porId.set(chamado.id, chamado);
    }
  }

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
  for (const aviso of avisos) {
    const resultado = await enviarLembrete(db, aviso);
    enviados += resultado.enviados;
    limpos += resultado.limpos;
  }
  return Response.json({
    chamados: fila.length,
    lembretes: avisos.length,
    enviados,
    limpos,
    expirados,
  });
});
