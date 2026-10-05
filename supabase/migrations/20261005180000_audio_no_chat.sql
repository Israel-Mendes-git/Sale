-- Áudio no chat: o recado de voz.
--
-- O enum do anexo ganha 'audio' (a migração da imagem já previa isso), e a
-- mensagem ganha a duração em segundos, que a bolha mostra antes de baixar o
-- arquivo. O áudio usa o mesmo bucket "anexos" e a mesma regra de acesso por
-- conversa da imagem.

alter type public.attachment_kind add value 'audio';

alter table public.messages
  add column attachment_duration integer check (attachment_duration > 0);
