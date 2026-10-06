-- Content-addressed assets: images go through the asset pipeline, users can
-- only place assets they uploaded, and media is public only once approved.
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice@example.test'),
  ('00000000-0000-0000-0000-0000000000b2', 'bob@example.test');
insert into public.users (id, handle) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice'),
  ('00000000-0000-0000-0000-0000000000b2', 'bob');
insert into public.plots (id, owner_id) values
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-0000000000b2');

-- The server re-encodes and stores one image Alice uploaded.
insert into public.assets (sha256, mime_type, byte_size, width, height)
values (repeat('a', 64), 'image/webp', 1234, 800, 600);
insert into public.asset_uploads (asset_sha256, user_id)
values (repeat('a', 64), '00000000-0000-0000-0000-0000000000a1');

select throws_ok(
  $$ insert into public.assets (sha256, mime_type, byte_size, width, height)
     values ('NOT-A-HASH', 'image/webp', 1, 1, 1) $$,
  '23514',
  null,
  'asset keys must be lowercase SHA-256 hex'
);

-- Alice --------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select throws_ok(
  $$ insert into public.plot_items (plot_id, type, content)
     values ('00000000-0000-0000-0000-00000000aa01', 'image', '{"url":"https://evil.example/x.png"}') $$,
  '23514',
  null,
  'an image item must reference an asset (no hotlinked URLs)'
);

insert into public.plot_items (id, plot_id, type, content, asset_sha256)
values ('00000000-0000-0000-0000-0000000000f1', '00000000-0000-0000-0000-00000000aa01',
        'image', '{"alt":"a cat"}', repeat('a', 64));

select is(
  (select moderation_status::text from public.assets where sha256 = repeat('a', 64)),
  'pending',
  'an uploader can see their own pending asset'
);

-- Bob ----------------------------------------------------------------------
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}';

select is(
  (select count(*)::int from public.assets),
  0,
  'other users cannot see a pending asset'
);

select throws_ok(
  $$ insert into public.plot_items (plot_id, type, content, asset_sha256)
     values ('00000000-0000-0000-0000-00000000bb01', 'image', '{}', repeat('a', 64)) $$,
  '42501',
  null,
  'a user cannot place an asset they did not upload'
);

-- Item approved but asset still pending: still not public ------------------
reset role;
update public.plot_items set moderation_status = 'approved'
  where id = '00000000-0000-0000-0000-0000000000f1';

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is(
  (select count(*)::int from public.plot_items_public),
  0,
  'an item is not public while its media is unapproved'
);

reset role;
update public.assets set moderation_status = 'approved' where sha256 = repeat('a', 64);

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is(
  (select asset_sha256 from public.plot_items_public where id = '00000000-0000-0000-0000-0000000000f1'),
  repeat('a', 64),
  'approved item with approved media is public'
);

-- Swapping the image sends the item back to pending ------------------------
reset role;
insert into public.assets (sha256, mime_type, byte_size, width, height, moderation_status)
values (repeat('b', 64), 'image/webp', 99, 10, 10, 'approved');
insert into public.asset_uploads (asset_sha256, user_id)
values (repeat('b', 64), '00000000-0000-0000-0000-0000000000a1');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

update public.plot_items set asset_sha256 = repeat('b', 64)
  where id = '00000000-0000-0000-0000-0000000000f1';

select is(
  (select moderation_status::text from public.plot_items where id = '00000000-0000-0000-0000-0000000000f1'),
  'pending',
  'changing an item''s media sends it back to pending'
);

-- Taking an asset down hides every item that uses it -----------------------
reset role;
update public.plot_items set moderation_status = 'approved';
update public.assets set moderation_status = 'rejected' where sha256 = repeat('b', 64);

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is(
  (select count(*)::int from public.plot_items_public),
  0,
  'rejecting an asset removes it from every plot at once'
);

select * from finish();
rollback;
