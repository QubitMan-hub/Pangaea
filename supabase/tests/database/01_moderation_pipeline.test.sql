-- Brief 5.4: nothing appears publicly until it passes moderation, and
-- clients can never mark their own content as approved.
begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

-- Fixtures (as postgres) ------------------------------------------------------
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice@example.test'),
  ('00000000-0000-0000-0000-0000000000b2', 'bob@example.test');
insert into public.users (id, handle) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice'),
  ('00000000-0000-0000-0000-0000000000b2', 'bob');
insert into public.plots (id, owner_id) values
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-0000000000b2');

-- Alice adds an item, trying to approve it herself ---------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select throws_ok(
  $$ insert into public.plot_items (plot_id, type, content, moderation_status)
     values ('00000000-0000-0000-0000-00000000aa01', 'text', '{"text":"hi"}', 'approved') $$,
  '42501',
  null,
  'a client cannot set moderation_status on insert'
);

insert into public.plot_items (id, plot_id, type, content)
values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-00000000aa01', 'text', '{"text":"hello world"}');

select is(
  (select moderation_status::text from public.plot_items where id = '00000000-0000-0000-0000-0000000000f1'),
  'pending',
  'new items start pending'
);

select is(
  (select count(*)::int from public.plot_items_public where plot_id = '00000000-0000-0000-0000-00000000aa01'),
  0,
  'pending items are not in the public view, even for the owner'
);

-- Bob cannot see Alice's pending item anywhere ------------------------------
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}';

select is(
  (select count(*)::int from public.plot_items where id = '00000000-0000-0000-0000-0000000000f1'),
  0,
  'another user cannot read a pending item from the base table'
);

select throws_ok(
  $$ insert into public.plot_items (plot_id, type, content)
     values ('00000000-0000-0000-0000-00000000aa01', 'text', '{"text":"vandalism"}') $$,
  '42501',
  null,
  'a user cannot add items to someone else''s plot'
);

update public.plot_items set content = '{"text":"hijacked"}'
  where id = '00000000-0000-0000-0000-0000000000f1';
delete from public.plot_items where id = '00000000-0000-0000-0000-0000000000f1';

-- Server approves -----------------------------------------------------------
reset role;

select is(
  (select content ->> 'text' from public.plot_items where id = '00000000-0000-0000-0000-0000000000f1'),
  'hello world',
  'another user cannot update or delete someone else''s item'
);

update public.plot_items
  set moderation_status = 'approved', moderated_at = now()
  where id = '00000000-0000-0000-0000-0000000000f1';

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is(
  (select content ->> 'text' from public.plot_items_public where id = '00000000-0000-0000-0000-0000000000f1'),
  'hello world',
  'approved items are visible to anonymous visitors'
);

-- Owner edits: moving keeps approval, changing content does not -------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

update public.plot_items set position = '{"x":10,"y":20}'
  where id = '00000000-0000-0000-0000-0000000000f1';

select is(
  (select moderation_status::text from public.plot_items where id = '00000000-0000-0000-0000-0000000000f1'),
  'approved',
  'moving an item keeps its approval'
);

select throws_ok(
  $$ update public.plot_items set position = '{"x":1,"note":"unmoderated words"}'
     where id = '00000000-0000-0000-0000-0000000000f1' $$,
  '23514',
  null,
  'position cannot carry text past moderation'
);

select throws_ok(
  $$ update public.plot_items set position = '{"x":"1"}'
     where id = '00000000-0000-0000-0000-0000000000f1' $$,
  '23514',
  null,
  'position values must be numbers'
);

update public.plot_items set content = '{"text":"something new"}'
  where id = '00000000-0000-0000-0000-0000000000f1';

select is(
  (select moderation_status::text from public.plot_items where id = '00000000-0000-0000-0000-0000000000f1'),
  'pending',
  'changing content sends the item back to pending'
);

select is(
  (select count(*)::int from public.plot_items_public where id = '00000000-0000-0000-0000-0000000000f1'),
  0,
  'edited content disappears from public until re-approved'
);

select throws_ok(
  $$ update public.plot_items set moderation_status = 'approved'
     where id = '00000000-0000-0000-0000-0000000000f1' $$,
  '42501',
  null,
  'a client cannot approve their own item by update'
);

-- Rejection reason is visible to the owner ----------------------------------
reset role;
update public.plot_items
  set moderation_status = 'rejected', moderation_reason = 'Contains spam links', moderated_at = now()
  where id = '00000000-0000-0000-0000-0000000000f1';

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select is(
  (select moderation_reason from public.plot_items where id = '00000000-0000-0000-0000-0000000000f1'),
  'Contains spam links',
  'the owner can read why their item was rejected'
);

-- Blurred items keep their slot but hide content ----------------------------
reset role;
update public.plot_items set moderation_status = 'blurred'
  where id = '00000000-0000-0000-0000-0000000000f1';

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is(
  (select content from public.plot_items_public where id = '00000000-0000-0000-0000-0000000000f1'),
  null,
  'blurred items are listed publicly with their content withheld'
);

-- Trust levels (brief 5.4.3) -------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select throws_ok(
  $$ insert into public.plot_items (plot_id, type, content)
     values ('00000000-0000-0000-0000-00000000aa01', 'webpage', '{"html":"<p>x</p>"}') $$,
  '42501',
  null,
  'trust level 0 cannot post webpages'
);

select lives_ok(
  $$ insert into public.plot_items (plot_id, type, content)
     values ('00000000-0000-0000-0000-00000000aa01', 'code', '{"code":"print(1)"}') $$,
  'trust level 0 can post code'
);

-- Comments ------------------------------------------------------------------
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}';

insert into public.comments (id, plot_id, author_id, body)
values ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-00000000aa01',
        '00000000-0000-0000-0000-0000000000b2', 'Nice plot!');

select throws_ok(
  $$ insert into public.comments (plot_id, author_id, body)
     values ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a1', 'impersonation') $$,
  '42501',
  null,
  'a user cannot comment as someone else'
);

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select is(
  (select count(*)::int from public.comments_public where plot_id = '00000000-0000-0000-0000-00000000aa01'),
  0,
  'pending comments are hidden from the plot owner'
);

reset role;
update public.comments set moderation_status = 'approved'
  where id = '00000000-0000-0000-0000-0000000000c1';

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is(
  (select body from public.comments_public where id = '00000000-0000-0000-0000-0000000000c1'),
  'Nice plot!',
  'approved comments are public'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}';
update public.comments set body = 'Nice plot! (edited)'
  where id = '00000000-0000-0000-0000-0000000000c1';

select is(
  (select moderation_status::text from public.comments where id = '00000000-0000-0000-0000-0000000000c1'),
  'pending',
  'editing a comment sends it back to pending'
);

-- Suspended plots vanish from public views ----------------------------------
reset role;
update public.plot_items set moderation_status = 'approved';
update public.plots set status = 'suspended' where id = '00000000-0000-0000-0000-00000000aa01';

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is(
  (select count(*)::int from public.plot_items_public where plot_id = '00000000-0000-0000-0000-00000000aa01'),
  0,
  'items on a suspended plot are not public'
);

select * from finish();
rollback;
