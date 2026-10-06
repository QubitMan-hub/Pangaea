-- Ownership rules and system-managed fields (brief 2, 4, 5.2).
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice@example.test'),
  ('00000000-0000-0000-0000-0000000000b2', 'bob@example.test');
insert into public.users (id, handle) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice'),
  ('00000000-0000-0000-0000-0000000000b2', 'bob');
insert into public.plots (id, owner_id, grid_x, grid_y, last_active_at) values
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a1', 1, 1, now() - interval '10 days'),
  ('00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-0000000000b2', 2, 1, now() - interval '10 days');

-- Schema-level rules ----------------------------------------------------------
select throws_ok(
  $$ insert into public.plots (owner_id) values ('00000000-0000-0000-0000-0000000000a1') $$,
  '23505',
  null,
  'a user can have only one plot'
);

select throws_ok(
  $$ update public.plots set grid_x = 1, grid_y = 1 where id = '00000000-0000-0000-0000-00000000bb01' $$,
  '23505',
  null,
  'two plots cannot share a grid cell'
);

select throws_ok(
  $$ insert into public.users (id, handle) values (gen_random_uuid(), 'Not Valid!') $$,
  '23514',
  null,
  'handles must be lowercase letters, digits or underscores'
);

select throws_ok(
  $$ insert into public.regions (label, is_frontier, center_x, center_y) values ('Second frontier', true, 5, 5) $$,
  '23505',
  null,
  'there is only one frontier region'
);

-- Alice, as a client ----------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select throws_ok(
  $$ update public.plots set earned_space = 1000 where id = '00000000-0000-0000-0000-00000000aa01' $$,
  '42501',
  null,
  'an owner cannot grant themselves earned space'
);

select throws_ok(
  $$ update public.users set trust_level = 2 where id = '00000000-0000-0000-0000-0000000000a1' $$,
  '42501',
  null,
  'a user cannot raise their own trust level'
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
  '42501',
  null,
  'a user cannot make themselves staff'
);

insert into public.plot_items (plot_id, type, content)
values ('00000000-0000-0000-0000-00000000aa01', 'text', '{"text":"hi"}');

reset role;

select ok(
  (select last_active_at > now() - interval '1 minute' from public.plots where id = '00000000-0000-0000-0000-00000000aa01'),
  'editing a plot records owner activity'
);

-- Reports -------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}';

select throws_ok(
  $$ insert into public.reports (target_type, target_id, reporter_id, reason)
     values ('plot', '00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a1', 'framed') $$,
  '42501',
  null,
  'a user cannot file a report as someone else'
);

select throws_ok(
  $$ insert into public.reports (target_type, target_id, reporter_id, reason, status)
     values ('plot', '00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000b2', 'x', 'dismissed') $$,
  '42501',
  null,
  'a user cannot set a report''s status'
);

insert into public.reports (target_type, target_id, reporter_id, reason)
values ('plot', '00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000b2', 'spam');

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select is(
  (select count(*)::int from public.reports),
  0,
  'a reported user cannot see who reported them'
);

select * from finish();
rollback;
