-- Saúde do banco.
--
-- 1. As funções que só o servidor chama ficam só com o servidor. No Supabase
--    toda função nova nasce executável por anon e authenticated, e as
--    migrações antigas só tiravam o execute do public — então qualquer um com
--    a chave pública conseguia chamar o relógio do grupo e, por exemplo,
--    marcar como disparado um Chamado que ainda ia tocar, sem push nenhum.
--
-- 2. As funções auxiliares ganham search_path fixo (aviso do Supabase).
--
-- 3. A versão do esquema: a última migração aplicada, que o publicar confere
--    antes de soltar um APK (produção atrás do repositório já quebrou o app
--    uma vez). TODA migração nova termina recriando esta função com o próprio
--    número — o tool/testar_banco.sh cobra.

revoke execute on function public.disparar_pendentes(timestamptz)
  from public, anon, authenticated;
grant execute on function public.disparar_pendentes(timestamptz) to service_role;

revoke execute on function public.lembretes_pendentes(timestamptz)
  from public, anon, authenticated;
grant execute on function public.lembretes_pendentes(timestamptz) to service_role;

revoke execute on function public.expirar_chamados(timestamptz)
  from public, anon, authenticated;
grant execute on function public.expirar_chamados(timestamptz) to service_role;

alter function public.espera_da_insistencia() set search_path = public;
alter function public.antecedencia_do_lembrete() set search_path = public;
alter function public.janela_do_disparo() set search_path = public;
alter function public.toque_do_chamado(public.chamados) set search_path = public;
alter function public.vida_do_chamado() set search_path = public;
alter function public.uuid_da_pasta(text) set search_path = public;

create or replace function public.versao_do_esquema() returns text
language sql immutable set search_path = public as $$ select '20261007120000' $$;

grant execute on function public.versao_do_esquema() to anon, authenticated;
