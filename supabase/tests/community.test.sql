-- Descriptions, comments, reports and appeals: who can do what to whom.
begin;
create extension if not exists pgtap with schema extensions;
select plan(23);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice@example.test'),
  ('00000000-0000-0000-0000-0000000000b2', 'bob@example.test'),
  ('00000000-0000-0000-0000-0000000000c3', 'carol@example.test');
insert into public.users (id, handle, trust_level) values
  ('00000000-0000-0000-0000-0000000000a1', 'alice', 0),
  ('00000000-0000-0000-0000-0000000000b2', 'bob', 1),
  ('00000000-0000-0000-0000-0000000000c3', 'carol', 2);
insert into public.plots (id, owner_id) values
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a1'),
  ('00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-0000000000b2');

-- Descriptions -------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

insert into public.plot_items (id, plot_id, type, content)
values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-00000000aa01',
        'description', '{"text":"Tiny puzzle games about tides"}');

select is(
  (select moderation_status::text from public.plot_items where id = '00000000-0000-0000-0000-0000000000d1'),
  'pending', 'a description is moderated like any text'
);

select throws_ok(
  $$ insert into public.plot_items (plot_id, type, content)
     values ('00000000-0000-0000-0000-00000000aa01', 'description', '{"text":"a second one"}') $$,
  '23505', null, 'a plot has exactly one description'
);

select throws_ok(
  $$ update public.plot_items set content = jsonb_build_object('text', repeat('x', 121))
     where id = '00000000-0000-0000-0000-0000000000d1' $$,
  '23514', null, 'descriptions are at most 120 characters'
);

select throws_ok(
  $$ delete from public.plot_items where id = '00000000-0000-0000-0000-0000000000d1' $$,
  '42501', null, 'a description can be edited but not deleted'
);

-- Comments -------------------------------------------------------------------------
reset role;
insert into public.comments (id, plot_id, author_id, body, moderation_status) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-00000000aa01',
   '00000000-0000-0000-0000-0000000000b2', 'Lovely tides', 'approved'),
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-00000000aa01',
   '00000000-0000-0000-0000-0000000000b2', 'Second thought', 'approved'),
  ('00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-00000000bb01',
   '00000000-0000-0000-0000-0000000000c3', 'On Bob''s plot', 'approved');

set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}';

select throws_ok(
  $$ insert into public.comments (plot_id, author_id, body)
     values ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a1', 'impersonation') $$,
  '42501', null, 'a user cannot comment as someone else'
);

insert into public.comments (id, plot_id, author_id, body)
values ('00000000-0000-0000-0000-0000000000e4', '00000000-0000-0000-0000-00000000aa01',
        '00000000-0000-0000-0000-0000000000b2', 'A fresh thought');

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select is(
  (select count(*)::int from public.comments_public where id = '00000000-0000-0000-0000-0000000000e4'),
  0, 'pending comments are hidden even from the plot owner'
);

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}';

update public.comments set body = 'Lovely tides!' where id = '00000000-0000-0000-0000-0000000000e1';
select is(
  (select moderation_status::text from public.comments where id = '00000000-0000-0000-0000-0000000000e1'),
  'pending', 'editing a comment sends it back to review'
);

select throws_ok(
  $$ delete from public.comments where id = '00000000-0000-0000-0000-0000000000e2' $$,
  '42501', null, 'comments cannot be hard-deleted by clients'
);

select ok(public.delete_comment('00000000-0000-0000-0000-0000000000e2'), 'an author can delete their comment');

select throws_ok(
  $$ update public.comments set body = 'resurrected' where id = '00000000-0000-0000-0000-0000000000e2' $$,
  '42501', null, 'a deleted comment cannot be edited back'
);

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select ok(public.delete_comment('00000000-0000-0000-0000-0000000000e1'), 'a plot owner can delete comments on their plot');
select ok(
  not public.delete_comment('00000000-0000-0000-0000-0000000000e3'),
  'a user cannot delete comments on someone else''s plot'
);

set local role anon;
set local request.jwt.claims = '{"role":"anon"}';

select is(
  (select count(*)::int from public.comments_public where plot_id = '00000000-0000-0000-0000-00000000aa01'),
  0, 'deleted comments disappear from public view'
);

select is(
  (select body from public.comments_public where id = '00000000-0000-0000-0000-0000000000e3'),
  'On Bob''s plot', 'approved comments are public'
);

reset role;
select is(
  (select count(*)::int from public.comments where deleted_at is not null),
  2, 'deleted comments stay stored for moderators'
);

-- Reports ---------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000c3","role":"authenticated"}';
insert into public.reports (target_type, target_id, reporter_id, reason)
values ('plot', '00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000c3', 'spam');

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
insert into public.reports (target_type, target_id, reporter_id, reason)
values ('plot', '00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-0000000000a1', 'spam');

select throws_ok(
  $$ insert into public.reports (target_type, target_id, reporter_id, reason, weight, status)
     values ('comment', '00000000-0000-0000-0000-0000000000e3', '00000000-0000-0000-0000-0000000000a1', 'x', 1.0, 'dismissed') $$,
  '42501', null, 'a client cannot set a report''s weight or status'
);

select throws_ok(
  $$ insert into public.reports (target_type, target_id, reporter_id, reason)
     values ('plot', '00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-0000000000b2', 'framed') $$,
  '42501', null, 'a user cannot report as someone else'
);

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}';
select is(
  (select count(*)::int from public.reports), 0, 'a reported user cannot see who reported them'
);

reset role;
select is(
  (select array_agg(weight order by weight) from public.reports),
  array[0.25, 1.0]::real[],
  'report weight comes from the reporter''s trust: new 0.25, trusted 1.0'
);

-- Appeals -------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';

select throws_ok(
  $$ insert into public.appeals (target_type, target_id, user_id, message)
     values ('plot_item', '00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a1', 'still pending') $$,
  '42501', null, 'there is nothing to appeal while content is pending'
);

reset role;
update public.plot_items set moderation_status = 'rejected' where id = '00000000-0000-0000-0000-0000000000d1';
set local role authenticated;
set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000b2","role":"authenticated"}';

select throws_ok(
  $$ insert into public.appeals (target_type, target_id, user_id, message)
     values ('plot_item', '00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b2', 'flooding') $$,
  '42501', null, 'a user cannot appeal decisions about other people''s content'
);

set local request.jwt.claims = '{"sub":"00000000-0000-0000-0000-0000000000a1","role":"authenticated"}';
insert into public.appeals (target_type, target_id, user_id, message)
values ('plot_item', '00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a1', 'Please look again');

select throws_ok(
  $$ insert into public.appeals (target_type, target_id, user_id, message)
     values ('plot_item', '00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a1', 'again') $$,
  '23505', null, 'only one open appeal per item at a time'
);

reset role;
update public.appeals set status = 'upheld', resolved_at = now();
set local role authenticated;

select lives_ok(
  $$ insert into public.appeals (target_type, target_id, user_id, message)
     values ('plot_item', '00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000a1', 'edited, rejected again') $$,
  'after a decision, the same item can be appealed again'
);

select * from finish();
rollback;
