// Manda o push de uma mensagem do chat assim que ela é escrita.
//
// Quem chama esta função é o banco: um webhook em `messages`, depois de
// inserir. Ela roda com a service_role (lê os aparelhos de todo mundo), por
// isso confere um segredo antes de fazer qualquer coisa.
//
// O envio em si mora em ../_compartilhado/push.ts, o mesmo do Chamado — o que
// muda é o aviso que o app monta do outro lado: mensagem é notificação comum,
// não batsinal.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import { enviarMensagem, Mensagem } from '../_compartilhado/push.ts';

const url = Deno.env.get('SUPABASE_URL')!;
const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const segredo = Deno.env.get('SEGREDO_DO_WEBHOOK')!;

const db = createClient(url, serviceRole);

Deno.serve(async (req) => {
  if (req.headers.get('x-sale-segredo') !== segredo) {
    return new Response('não autorizado', { status: 401 });
  }

  const { record: mensagem } = await req.json() as { record: Mensagem };
  if (!mensagem?.id) return new Response('sem mensagem', { status: 400 });

  // Card de Chamado é mensagem na conversa, mas o aviso dele é o do batsinal,
  // que já saiu pelo enviar-chamado.
  if (mensagem.chamado_id) {
    return Response.json({ enviados: 0, motivo: 'chamado' });
  }

  return Response.json(await enviarMensagem(db, mensagem));
});
