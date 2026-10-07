-- Access rules: RLS everywhere, nothing writable that shouldn't be, and
-- system-managed fields out of clients' reach.
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice@example.test'),
  ('00000000-0000-0000-0000-0000000000b2', 'bob@example.test');
insert into public.users (id, handle) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice'),
  ('00000000-0000-0000-0000-0000000000b2', 'bob');
insert into public.plots (id, owner_id, grid_x, grid_y) values
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a1', 1, 1),
  ('00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-0000000000b2', 2, 1);

-- Grants ------------------------------------------------------------------------
select is(
  (select coalesce(array_agg(c.relname::text order by c.relname), '{}')
   from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity),
  '{}'::text[],
  'RLS is enabled on every table'
);

select is(
  (select coalesce(array_agg(c.relname::text order by c.relname), '{}')
   from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'
     and has_table_privilege('anon', c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE')),
  '{}'::text[],
  'anon cannot write any table'
);

select ok(
  not has_table_privilege('anon', 'public.plot_items', 'SELECT')
  and not has_table_privilege('anon', 'public.comments', 'SELECT'),
  'anon reads items and comments only through the public views'
);

select ok(
  not has_table_privilege('authenticated', 'public.attention_daily', 'SELECT, INSERT, UPDATE')
  and not has_table_privilege('authenticated', 'public.ai_spend_daily', 'SELECT, INSERT, UPDATE')
  and not has_table_privilege('authenticated', 'public.asset_sources', 'SELECT, INSERT'),
  'server-only tables are closed to clients'
);

select ok(
  not has_table_privilege('authenticated', 'public.plots', 'INSERT, UPDATE, DELETE')
  and not has_table_privilege('authenticated', 'public.assets', 'INSERT, UPDATE, DELETE'),
  'clients cannot write plots or assets'
);

select ok(
  not has_column_privilege('anon', 'public.plots', 'embedding', 'SELECT')
  and not has_column_privilege('anon', 'public.plots', 'earned_space', 'SELECT')
  and has_column_privilege('anon', 'public.plots', 'thumb_hash', 'SELECT'),
  'the public reads only the plot fields the map needs'
);

select ok(
  not exists (
    select 1 from information_schema.routines
    where routine_schema = 'public' and routine_name in ('is_staff', 'owns_plot', 'uploaded_asset', 'can_appeal')
  ),
  'privileged helpers are not callable through the API'
);

-- Schema rules -------------------------------------------------------------------
select throws_ok(
  $$ insert into public.plots (owner_id) values ('00000000-0000-0000-0000-0000000000a1') $$,
  '23505', null, 'a user has only one plot'
);

select throws_ok(
  $$ update public.plots set grid_x = 1, grid_y = 1 where id = '00000000-0000-0000-0000-00000000bb01' $$,
  '23505', null, 'two plots cannot share a grid cell'
);

select throws_ok(
  $$ insert into public.users (id, handle) values (gen_random_uuid(), 'Not Valid!') $$,
  '23514', null, 'handles are lowercase letters, digits or underscores'
);

select throws_ok(
  $$ insert into public.regions (label, is_frontier, center_x, center_y) values ('Second', true, 5, 5) $$,
  '23505', null, 'there is only one frontier region'
);

-- As Alice -------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select throws_ok(
  $$ update public.plots set earned_space = 1000 where id = '00000000-0000-0000-0000-00000000aa01' $$,
  '42501', null, 'an owner cannot grant themselves earned space'
);

select throws_ok(
  $$ update public.users set trust_level = 2 where id = '00000000-0000-0000-0000-0000000000a1' $$,
  '42501', null, 'a user cannot raise their own trust level'
);

update public.users set handle = 'alice_new' where id = '00000000-0000-0000-0000-0000000000b2';
update public.users set handle = 'alice_new' where id = '00000000-0000-0000-0000-0000000000a1';

select is(
  (select array_agg(handle order by handle) from public.users),
  array['alice_new', 'bob'],
  'a user can change only their own handle'
);

select throws_ok(
  $$ insert into public.staff (user_id, role) values ('00000000-0000-0000-0000-0000000000a1', 'admin') $$,
  '42501', null, 'a user cannot make themselves staff'
);

select throws_ok(
  $$ insert into public.plot_items (plot_id, type, content)
     values ('00000000-0000-0000-0000-00000000bb01', 'text', '{"text":"vandalism"}') $$,
  '42501', null, 'a user cannot add items to someone else''s plot'
);

-- As Bob, trying to change Alice's item --------------------------------------------
reset role;
insert into public.plot_items (id, plot_id, type, content, moderation_status)
values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-00000000aa01',
        'text', '{"text":"hello"}', 'approved');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}';

select is(
  (select count(*)::int from public.plot_items where id = '00000000-0000-0000-0000-0000000000f1'),
  0,
  'another user cannot read someone else''s items from the base table'
);

update public.plot_items set content = '{"text":"hijacked"}' where id = '00000000-0000-0000-0000-0000000000f1';
delete from public.plot_items where id = '00000000-0000-0000-0000-0000000000f1';

reset role;
select is(
  (select content ->> 'text' from public.plot_items where id = '00000000-0000-0000-0000-0000000000f1'),
  'hello',
  'another user cannot change or delete someone else''s item'
);

select * from finish();
rollback;
