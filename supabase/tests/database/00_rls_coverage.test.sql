-- Every table must have RLS on, and anonymous visitors must not be able to
-- reach anything unmoderated or system-managed.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

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
  not has_table_privilege('authenticated', 'public.attention_daily', 'SELECT, INSERT, UPDATE'),
  'clients cannot read or write attention_daily'
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
      and routine_name in ('is_staff', 'owns_plot', 'plot_is_active', 'bump_plot_activity', 'uploaded_asset', 'is_client_role', 'min_trust_for_item_type')
  ),
  'privileged helpers are not exposed in the public (API) schema'
);

select ok(
  not has_table_privilege('authenticated', 'public.assets', 'INSERT, UPDATE, DELETE'),
  'clients cannot create or approve assets'
);

select ok(
  not has_column_privilege('authenticated', 'public.plots', 'earned_space_updated_at', 'UPDATE'),
  'clients cannot move the earned-space clock'
);

select ok(
  not has_column_privilege('anon', 'public.plots', 'cold_storage_key', 'SELECT')
  and not has_column_privilege('anon', 'public.plots', 'embedding', 'SELECT')
  and not has_column_privilege('anon', 'public.plots', 'last_visited_at', 'SELECT'),
  'internal plot fields are not readable by the public'
);

select ok(
  has_column_privilege('anon', 'public.plots', 'thumb_hash', 'SELECT')
  and has_column_privilege('anon', 'public.plots', 'grid_x', 'SELECT'),
  'the fields the public map needs are readable'
);

select * from finish();
rollback;
