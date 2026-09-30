-- O mínimo do Supabase para testar as migrações num Postgres comum:
-- o esquema auth com auth.uid() e os papéis anon/authenticated.
-- Não vai para o Supabase de verdade (lá isso já existe).

create schema auth;

create table auth.users (
  id uuid primary key,
  email text,
  raw_user_meta_data jsonb not null default '{}'
);

create function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create role anon nologin;
create role authenticated nologin;
grant usage on schema auth to anon, authenticated;
