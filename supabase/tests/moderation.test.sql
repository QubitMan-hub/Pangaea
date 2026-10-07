-- Nothing appears publicly until it passes moderation, and clients can never
-- approve their own content (CLAUDE.md, product rules).
begin;
create extension if not exists pgtap with schema extensions;
select plan(20);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice@example.test'),
  ('00000000-0000-0000-0000-0000000000b2', 'bob@example.test');
insert into public.users (id, handle) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice'),
  ('00000000-0000-0000-0000-0000000000b2', 'bob');
insert into public.plots (id, owner_id) values
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-0000000000b2');
-- An image Alice uploaded, verified and stored by the server.
insert into public.assets (sha256, mime_type, byte_size, width, height)
values (repeat('a', 64), 'image/webp', 1234, 800, 600);
insert into public.asset_uploads (asset_sha256, user_id)
values (repeat('a', 64), '00000000-0000-0000-0000-0000000000a1');

-- Items ----------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select throws_ok(
  $$ insert into public.plot_items (plot_id, type, content, moderation_status)
     values ('00000000-0000-0000-0000-00000000aa01', 'text', '{"text":"hi"}', 'approved') $$,
  '42501', null, 'a client cannot set moderation_status'
);

insert into public.plot_items (id, plot_id, type, content)
values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-00000000aa01', 'text', '{"text":"hello world"}');

select is(
  (select moderation_status::text from public.plot_items where id = '00000000-0000-0000-0000-0000000000f1'),
  'pending', 'new items start pending'
);

select is(
  (select count(*)::int from public.plot_items_public), 0,
  'pending items are not public, even to their owner'
);

reset role;
update public.plot_items set moderation_status = 'approved' where id = '00000000-0000-0000-0000-0000000000f1';
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is(
  (select content ->> 'text' from public.plot_items_public where id = '00000000-0000-0000-0000-0000000000f1'),
  'hello world', 'approved items are public'
);

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

update public.plot_items set position = '{"x":10,"y":20}' where id = '00000000-0000-0000-0000-0000000000f1';
select is(
  (select moderation_status::text from public.plot_items where id = '00000000-0000-0000-0000-0000000000f1'),
  'approved', 'moving an item keeps its approval'
);

select throws_ok(
  $$ update public.plot_items set position = '{"x":1,"note":"unmoderated words"}'
     where id = '00000000-0000-0000-0000-0000000000f1' $$,
  '23514', null, 'position cannot carry text past moderation'
);

update public.plot_items set content = '{"text":"something new"}' where id = '00000000-0000-0000-0000-0000000000f1';
select is(
  (select moderation_status::text from public.plot_items where id = '00000000-0000-0000-0000-0000000000f1'),
  'pending', 'changing content sends the item back to review'
);

select throws_ok(
  $$ update public.plot_items set moderation_status = 'approved' where id = '00000000-0000-0000-0000-0000000000f1' $$,
  '42501', null, 'a client cannot approve their own item'
);

reset role;
update public.plot_items
  set moderation_status = 'rejected', moderation_reason = 'Contains spam links'
  where id = '00000000-0000-0000-0000-0000000000f1';
set local role authenticated;

select is(
  (select moderation_reason from public.plot_items where id = '00000000-0000-0000-0000-0000000000f1'),
  'Contains spam links', 'the owner can read why an item was rejected'
);

reset role;
update public.plot_items set moderation_status = 'blurred' where id = '00000000-0000-0000-0000-0000000000f1';
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is(
  (select content from public.plot_items_public where id = '00000000-0000-0000-0000-0000000000f1'),
  null, 'reported (blurred) items keep their slot with content withheld'
);

-- Images ------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select throws_ok(
  $$ insert into public.plot_items (plot_id, type, content)
     values ('00000000-0000-0000-0000-00000000aa01', 'image', '{"url":"https://evil.example/x.png"}') $$,
  '23514', null, 'an image must come through the asset pipeline (no hotlinks)'
);

insert into public.plot_items (id, plot_id, type, content, asset_sha256)
values ('00000000-0000-0000-0000-0000000000f2', '00000000-0000-0000-0000-00000000aa01',
        'image', '{"alt":"a cat"}', repeat('a', 64));

select is(
  (select moderation_status::text from public.assets where sha256 = repeat('a', 64)),
  'pending', 'an uploader sees their own pending image'
);

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}';

select is((select count(*)::int from public.assets), 0, 'others cannot see a pending image');

select throws_ok(
  $$ insert into public.plot_items (plot_id, type, content, asset_sha256)
     values ('00000000-0000-0000-0000-00000000bb01', 'image', '{}', repeat('a', 64)) $$,
  '42501', null, 'a user cannot place an image they did not upload'
);

reset role;
update public.plot_items set moderation_status = 'approved' where id = '00000000-0000-0000-0000-0000000000f2';
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is(
  (select count(*)::int from public.plot_items_public where id = '00000000-0000-0000-0000-0000000000f2'),
  0, 'an item is not public while its image is unapproved'
);

reset role;
update public.assets set moderation_status = 'approved' where sha256 = repeat('a', 64);
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is(
  (select asset_sha256 from public.plot_items_public where id = '00000000-0000-0000-0000-0000000000f2'),
  repeat('a', 64), 'an approved item with an approved image is public'
);

reset role;
insert into public.assets (sha256, mime_type, byte_size, width, height, moderation_status)
values (repeat('b', 64), 'image/webp', 99, 10, 10, 'approved');
insert into public.asset_uploads (asset_sha256, user_id)
values (repeat('b', 64), '00000000-0000-0000-0000-0000000000a1');
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

update public.plot_items set asset_sha256 = repeat('b', 64) where id = '00000000-0000-0000-0000-0000000000f2';
select is(
  (select moderation_status::text from public.plot_items where id = '00000000-0000-0000-0000-0000000000f2'),
  'pending', 'swapping an image sends the item back to review'
);

reset role;
update public.plot_items set moderation_status = 'approved' where id = '00000000-0000-0000-0000-0000000000f2';
update public.assets set moderation_status = 'rejected' where sha256 = repeat('b', 64);
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is(
  (select count(*)::int from public.plot_items_public where id = '00000000-0000-0000-0000-0000000000f2'),
  0, 'rejecting an image hides it on every plot at once'
);

-- Suspended plots ------------------------------------------------------------------
reset role;
update public.plot_items set moderation_status = 'approved';
update public.assets set moderation_status = 'approved';
update public.plots set status = 'suspended' where id = '00000000-0000-0000-0000-00000000aa01';
set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is(
  (select count(*)::int from public.plot_items_public where plot_id = '00000000-0000-0000-0000-00000000aa01'),
  0, 'nothing on a suspended plot is public'
);

select is(
  (select count(*)::int from public.plots where id = '00000000-0000-0000-0000-00000000aa01'),
  0, 'a suspended plot itself is hidden'
);

select * from finish();
rollback;
