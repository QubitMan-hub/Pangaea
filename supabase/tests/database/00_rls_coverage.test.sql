-- Every table must have RLS on, and anonymous visitors must not be able to
-- reach anything unmoderated or system-managed.
begin;
create extension if not exists pgtap with schema extensions;
select plan(8);

select is(
  (
    select coalesce(array_agg(c.relname::text order by c.relname), '{}')
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity
  ),
  '{}'::text[],
  'RLS is enabled on every table in public'
);

select is(
  (
    select coalesce(array_agg(c.relname::text order by c.relname), '{}')
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'
      and has_table_privilege('anon', c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE')
  ),
  '{}'::text[],
  'anon has no write privilege on any table'
);

select ok(
  not has_table_privilege('anon', 'public.plot_items', 'SELECT'),
  'anon cannot read the plot_items base table'
);

select ok(
  not has_table_privilege('anon', 'public.comments', 'SELECT'),
  'anon cannot read the comments base table'
);

select ok(
  not has_table_privilege('authenticated', 'public.attention_events', 'SELECT, INSERT'),
  'clients cannot read or write attention_events'
);

select ok(
  not has_column_privilege('authenticated', 'public.plot_items', 'moderation_status', 'INSERT')
  and not has_column_privilege('authenticated', 'public.plot_items', 'moderation_status', 'UPDATE'),
  'clients cannot write plot_items.moderation_status'
);

select ok(
  not has_table_privilege('authenticated', 'public.plots', 'INSERT, UPDATE, DELETE'),
  'clients cannot write plots (placement and growth are system-managed)'
);

select ok(
  not exists (
    select 1 from information_schema.routines
    where routine_schema = 'public'
      and routine_name in ('is_staff', 'owns_plot', 'plot_is_active', 'bump_plot_activity')
  ),
  'privileged helpers are not exposed in the public (API) schema'
);

select * from finish();
rollback;
