-- Final pass over privileges, run after every table and function exists.

-- Sign-in is required for everything; anon gets nothing.
revoke all on all tables in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke execute on all functions in schema public from anon, public;

-- TRUNCATE ignores row-level security.
revoke truncate, references, trigger on all tables in schema public from authenticated;

-- Fail the migration if any table in the API schema is missing row-level security.
do $$
declare
  r record;
begin
  for r in
    select c.relname
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity
  loop
    raise exception 'Table public.% does not have row-level security enabled', r.relname;
  end loop;
end;
$$;
