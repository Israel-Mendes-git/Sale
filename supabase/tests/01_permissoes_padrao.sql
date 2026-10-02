-- Depois das migrações: as permissões de tabela que o Supabase dá por
-- padrão. Quem decide o que cada um vê e mexe são as regras (RLS).

grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage on all sequences in schema public to authenticated;
grant select, insert, update, delete on all tables in schema public to service_role;
grant usage on all sequences in schema public to service_role;
