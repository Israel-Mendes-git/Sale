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

-- O papel do servidor: as Edge Functions entram com ele e passam por cima
-- das regras de acesso (no Supabase de verdade já existe assim).
create role service_role nologin bypassrls;
grant usage on schema auth to service_role;

-- Como no Supabase de verdade: toda função que as migrações criarem no public
-- já nasce executável por anon, authenticated e service_role. Por isso
-- "revoke ... from public" não tranca nada lá — e sem isto aqui os testes
-- passavam achando que trancava.
alter default privileges in schema public
  grant execute on functions to anon, authenticated, service_role;
