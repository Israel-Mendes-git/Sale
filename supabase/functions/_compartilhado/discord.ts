// A call do Discord de cada grupo, pelo widget público do servidor (o mesmo
// que o app lê para mostrar quem está lá). O cron do disparo passa aqui a
// cada minuto: anota quem está na call (registrar_call) e, quando a call
// acabou de abrir, avisa o grupo.
//
// Falhar aqui — widget desligado, Discord fora do ar — não segura o resto do
// relógio: o minuto simplesmente fica sem anotação.

import { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { enviarCallAberta } from './push.ts';

export type NaCall = { nome: string; canal: string | null };

/// Quem está numa call, pelo JSON do widget: o nome e o canal de voz.
export function quemEstaNaCall(widget: unknown): NaCall[] {
  const w = widget as {
    channels?: { id: string; name: string }[];
    members?: { username?: string; channel_id?: string | null }[];
  } | null;
  const canais = new Map((w?.channels ?? []).map((c) => [c.id, c.name]));
  return (w?.members ?? [])
    .filter((m) => m.channel_id && m.username)
    .map((m) => ({
      nome: m.username!,
      canal: canais.get(m.channel_id!) ?? null,
    }));
}

/// Passa por todos os grupos com servidor do Discord. Devolve quantos
/// avisos de call aberta saíram.
export async function vigiarCalls(
  db: SupabaseClient,
): Promise<{ avisos: number; enviados: number; limpos: number }> {
  const total = { avisos: 0, enviados: 0, limpos: 0 };
  const { data: grupos, error } = await db
    .from('groups')
    .select('id, discord_servidor')
    .not('discord_servidor', 'is', null);
  if (error) {
    console.error('não deu para ler os servidores do Discord', error);
    return total;
  }
  for (const grupo of grupos ?? []) {
    try {
      const resposta = await fetch(
        `https://discord.com/api/guilds/${grupo.discord_servidor}/widget.json`,
        { signal: AbortSignal.timeout(8000) },
      );
      if (!resposta.ok) continue;
      const pessoas = quemEstaNaCall(await resposta.json());
      const { data: abriu, error: erro } = await db.rpc('registrar_call', {
        p_grupo: grupo.id,
        p_pessoas: pessoas,
      });
      if (erro) {
        console.error('o banco recusou a call', erro);
        continue;
      }
      if (abriu && pessoas.length) {
        const r = await enviarCallAberta(db, grupo.id, pessoas);
        total.avisos++;
        total.enviados += r.enviados;
        total.limpos += r.limpos;
      }
    } catch (e) {
      console.error('não deu para ler o widget do Discord', e);
    }
  }
  return total;
}
