-- Imagem na conversa: o print da partida, a foto do setup, o meme do grupo.
--
-- A mensagem passa a ter um anexo além do texto: o arquivo mora no Storage
-- (bucket "anexos", na pasta da conversa) e a linha guarda o caminho, o tipo e
-- o tamanho da imagem. O tamanho vem junto para a bolha já nascer do tamanho
-- certo, em vez de a conversa saltar quando a imagem termina de baixar.
--
-- O tipo é um enum de um valor só por enquanto; o áudio entra nele depois.

create type public.attachment_kind as enum ('image');

alter table public.messages
  add column attachment_path text
    check (char_length(btrim(attachment_path)) between 1 and 300),
  add column attachment_kind public.attachment_kind,
  add column attachment_width integer check (attachment_width > 0),
  add column attachment_height integer check (attachment_height > 0);

-- Caminho e tipo andam juntos: arquivo sem tipo não dá para mostrar, tipo sem
-- arquivo não mostra nada.
alter table public.messages add constraint messages_anexo_completo
  check ((attachment_path is null) = (attachment_kind is null));

-- A regra de conteúdo da mensagem, que antes era "texto ou card de Chamado":
-- agora o card continua sozinho, e a mensagem de gente precisa de texto, de
-- anexo, ou dos dois (a imagem com legenda).
do $$
declare nome text;
begin
  select conname into nome from pg_constraint
  where conrelid = 'public.messages'::regclass and contype = 'c'
    and pg_get_constraintdef(oid) like '%chamado_id IS NULL%';
  if nome is not null then
    execute format('alter table public.messages drop constraint %I', nome);
  end if;
end
$$;

alter table public.messages add constraint messages_conteudo check (
  case when chamado_id is not null
    then body is null and attachment_path is null
    else body is not null or attachment_path is not null
  end
);

-- Quem manda texto agora também manda imagem, e continua só em nome próprio.
drop policy "manda texto em nome próprio" on public.messages;
create policy "manda mensagem em nome próprio" on public.messages
  for insert with check (
    author_id = auth.uid() and chamado_id is null and
    is_conversation_member(conversation_id)
  );

-- A primeira pasta do caminho de um arquivo serve de dono em todo bucket: no
-- "sons" ela é o grupo, no "anexos" é a conversa. O nome antigo
-- (`grupo_do_arquivo`) só contava metade da história; as regras de acesso que
-- já usavam a função seguem valendo, porque apontam para ela, não para o nome.
alter function public.grupo_do_arquivo(text) rename to uuid_da_pasta;

-- ---------------------------------------------------------------------------
-- Os arquivos (Storage)
--
-- Bucket fechado, com os anexos em `<conversa>/<arquivo>`: quem está na
-- conversa manda, lê e apaga; de fora, ninguém. Imagem de celular passa fácil
-- de 5 MB, então o limite é mais alto que o dos sons.

do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit)
    values ('anexos', 'anexos', false, 10485760)
    on conflict (id) do nothing;

    execute $pol$
      create policy "membro lê os anexos da conversa" on storage.objects
        for select using (
          bucket_id = 'anexos'
          and public.is_conversation_member(public.uuid_da_pasta(name))
        )
    $pol$;
    execute $pol$
      create policy "membro manda anexo na conversa" on storage.objects
        for insert with check (
          bucket_id = 'anexos'
          and public.is_conversation_member(public.uuid_da_pasta(name))
        )
    $pol$;
    execute $pol$
      create policy "membro apaga anexo da conversa" on storage.objects
        for delete using (
          bucket_id = 'anexos'
          and public.is_conversation_member(public.uuid_da_pasta(name))
        )
    $pol$;
  end if;
end
$$;
