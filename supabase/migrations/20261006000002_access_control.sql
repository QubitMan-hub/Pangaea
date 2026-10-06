-- Pangaea access control.
--
-- Principles:
--   * RLS is enabled on every table. A table with no policy for a role is
--     closed to that role.
--   * Table privileges are granted explicitly, column by column where clients
--     may write, so a client can never set moderation fields, trust levels,
--     earned space, placement, etc. The server uses the service role for those.
--   * Unmoderated content is never readable by the public. Visitors read
--     items and comments through the *_public views, which only expose
--     approved rows (and blurred rows with their content withheld).
--   * Only the owner can write to their plot's items.

-- ---------------------------------------------------------------------------
-- Helper functions.
--
-- They live in a `private` schema, which the Data API does not expose, so
-- clients can't call them as RPCs. Policies call them as the invoker, so the
-- client roles need USAGE/EXECUTE. Lookups are security definer so policies
-- can call them without recursing through RLS. All pin search_path.
-- ---------------------------------------------------------------------------

create schema private;
grant usage on schema private to anon, authenticated, service_role;
-- Functions are executable by PUBLIC by default; grant explicitly instead.
alter default privileges in schema private revoke execute on functions from public;

create function private.is_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.staff s where s.user_id = (select auth.uid()));
$$;

create function private.owns_plot(target_plot_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.plots p
    where p.id = target_plot_id and p.owner_id = (select auth.uid())
  );
$$;

create function private.plot_is_active(target_plot_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.plots p where p.id = target_plot_id and p.status = 'active'
  );
$$;

-- True if the current user uploaded this asset (so they may place it).
create function private.uploaded_asset(target_asset_sha256 text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.asset_uploads au
    where au.asset_sha256 = target_asset_sha256 and au.user_id = (select auth.uid())
  );
$$;

grant execute on function private.uploaded_asset(text) to anon, authenticated, service_role;

-- True if the caller may appeal this target: it must be their own content and
-- a moderation decision must actually be against it (rejected or blurred
-- content, or their own suspended plot). Stops anyone flooding the review
-- queue with appeals about other people's content.
create function private.can_appeal(target public.report_target, target_uuid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case target
    when 'plot_item' then exists (
      select 1 from public.plot_items i
      join public.plots p on p.id = i.plot_id
      where i.id = target_uuid
        and p.owner_id = (select auth.uid())
        and i.moderation_status in ('rejected', 'blurred'))
    when 'comment' then exists (
      select 1 from public.comments c
      where c.id = target_uuid
        and c.author_id = (select auth.uid())
        and c.moderation_status in ('rejected', 'blurred'))
    when 'plot' then exists (
      select 1 from public.plots p
      where p.id = target_uuid
        and p.owner_id = (select auth.uid())
        and p.status = 'suspended')
    else false
  end;
$$;

grant execute on function private.can_appeal(public.report_target, uuid) to authenticated, service_role;
grant execute on function private.is_staff() to anon, authenticated, service_role;
grant execute on function private.owns_plot(uuid) to anon, authenticated, service_role;
grant execute on function private.plot_is_active(uuid) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Reset table privileges. Supabase grants ALL to anon/authenticated by
-- default; we grant back only what each role needs.
-- ---------------------------------------------------------------------------

revoke all on all tables in schema public from anon, authenticated;

alter table public.users enable row level security;
alter table public.staff enable row level security;
alter table public.regions enable row level security;
alter table public.plots enable row level security;
alter table public.plot_items enable row level security;
alter table public.comments enable row level security;
alter table public.missions enable row level security;
alter table public.mission_completions enable row level security;
alter table public.attention_daily enable row level security;
alter table public.assets enable row level security;
alter table public.asset_sources enable row level security;
alter table public.asset_uploads enable row level security;
alter table public.region_visits enable row level security;
alter table public.reports enable row level security;
alter table public.continents enable row level security;
alter table public.appeals enable row level security;
alter table public.ai_spend_daily enable row level security;

-- ---------------------------------------------------------------------------
-- users: public handles; a user may change only their own handle.
-- Rows are created server-side on signup (Phase 1).
-- ---------------------------------------------------------------------------

grant select on public.users to anon, authenticated;
grant update (handle) on public.users to authenticated;

create policy users_select_all on public.users
  for select to anon, authenticated
  using (true);

create policy users_update_own on public.users
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- staff: a user can see only their own staff row (so the app can show the
-- admin link). Membership is managed with the service role.
-- ---------------------------------------------------------------------------

grant select on public.staff to authenticated;

create policy staff_select_own on public.staff
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- regions & missions: public reference data, written server-side.
-- ---------------------------------------------------------------------------

grant select on public.regions to anon, authenticated;
create policy regions_select_all on public.regions
  for select to anon, authenticated
  using (true);

grant select on public.continents to anon, authenticated;
create policy continents_select_all on public.continents
  for select to anon, authenticated
  using (true);

grant select on public.missions to anon, authenticated;
create policy missions_select_all on public.missions
  for select to anon, authenticated
  using (true);

-- ---------------------------------------------------------------------------
-- plots: everything about a plot (placement, size, embedding, thumbnail,
-- status) is system-managed. Clients only read. The thumbnail is published by
-- the server only after it and everything it shows are approved.
-- ---------------------------------------------------------------------------

-- Column-level: only what the public map and plot pages need. Internal
-- fields (embedding, text_hash, cold_storage_key, visit and activity times,
-- raw earned space) stay server-side; the server publishes computed sizes.
grant select (
  id, owner_id, region_id, placement, grid_x, grid_y, base_size,
  thumbnail_asset_sha256, thumb_hash, snapshot_version, display_view_count,
  status, created_at
) on public.plots to anon, authenticated;

create policy plots_select_visible on public.plots
  for select to anon, authenticated
  using (
    status = 'active'
    or owner_id = (select auth.uid())
    or (select private.is_staff())
  );

-- ---------------------------------------------------------------------------
-- plot_items: base table is owner (and staff) only. Visitors use
-- plot_items_public. Owners may write type/content/position, never the
-- moderation columns (see also the guard trigger in the next migration).
-- ---------------------------------------------------------------------------

grant select, delete on public.plot_items to authenticated;
grant insert (id, plot_id, type, content, position, asset_sha256) on public.plot_items to authenticated;
grant update (content, position, asset_sha256) on public.plot_items to authenticated;

create policy plot_items_select_owner_or_staff on public.plot_items
  for select to authenticated
  using ((select private.owns_plot(plot_id)) or (select private.is_staff()));

-- Owners may only place assets they uploaded themselves.
create policy plot_items_insert_owner on public.plot_items
  for insert to authenticated
  with check (
    (select private.owns_plot(plot_id))
    and (asset_sha256 is null or (select private.uploaded_asset(asset_sha256)))
  );

create policy plot_items_update_owner on public.plot_items
  for update to authenticated
  using ((select private.owns_plot(plot_id)))
  with check (
    (select private.owns_plot(plot_id))
    and (asset_sha256 is null or (select private.uploaded_asset(asset_sha256)))
  );

create policy plot_items_delete_owner on public.plot_items
  for delete to authenticated
  using ((select private.owns_plot(plot_id)));

-- ---------------------------------------------------------------------------
-- comments: base table is author (and staff) only; visitors, including the
-- plot owner, see comments_public. Unmoderated comments never reach the plot
-- owner, which matters for harassment. Deletion is soft and goes through
-- public.delete_comment(), so moderators keep deleted comments.
-- ---------------------------------------------------------------------------

grant select on public.comments to authenticated;
grant insert (id, plot_id, author_id, body) on public.comments to authenticated;
grant update (body) on public.comments to authenticated;

create policy comments_select_author_or_staff on public.comments
  for select to authenticated
  using (author_id = (select auth.uid()) or (select private.is_staff()));

create policy comments_insert_author on public.comments
  for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and (select private.plot_is_active(plot_id))
  );

create policy comments_update_author on public.comments
  for update to authenticated
  using (author_id = (select auth.uid()))
  with check (author_id = (select auth.uid()));

-- Authors, and the owner of the plot a comment is on, can delete it. Soft
-- delete only: the row stays for moderators (CLAUDE.md section 3).
create function public.delete_comment(target_comment_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  caller uuid := (select auth.uid());
  updated integer;
begin
  if caller is null then
    raise exception 'Sign in to delete comments' using errcode = 'insufficient_privilege';
  end if;

  update public.comments c
    set deleted_at = now(), deleted_by = caller
    where c.id = target_comment_id
      and c.deleted_at is null
      and (
        c.author_id = caller
        or exists (select 1 from public.plots p where p.id = c.plot_id and p.owner_id = caller)
      );
  get diagnostics updated = row_count;
  return updated = 1;
end;
$$;

revoke all on function public.delete_comment(uuid) from public, anon;
grant execute on function public.delete_comment(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- mission_completions & region_visits: users read their own; the server
-- verifies and writes.
-- ---------------------------------------------------------------------------

grant select on public.mission_completions to authenticated;
create policy mission_completions_select_own on public.mission_completions
  for select to authenticated
  using (user_id = (select auth.uid()));

grant select on public.region_visits to authenticated;
create policy region_visits_select_own on public.region_visits
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- attention_daily & asset_sources: no client access at all (RLS on, no
-- policies, no grants). Attention is folded in by the server so per-visitor
-- caps can't be bypassed.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- assets: anyone may read metadata of approved assets; uploaders also see
-- their own pending/rejected ones (with the reason). Written server-side.
-- ---------------------------------------------------------------------------

grant select on public.assets to anon, authenticated;

create policy assets_select_approved_or_own on public.assets
  for select to anon, authenticated
  using (
    moderation_status = 'approved'
    or (select private.uploaded_asset(sha256))
    or (select private.is_staff())
  );

grant select on public.asset_uploads to authenticated;

create policy asset_uploads_select_own on public.asset_uploads
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- reports: signed-in users file reports as themselves and can see their own.
-- ---------------------------------------------------------------------------

grant select on public.reports to authenticated;
grant insert (target_type, target_id, reporter_id, reason) on public.reports to authenticated;

create policy reports_select_own_or_staff on public.reports
  for select to authenticated
  using (reporter_id = (select auth.uid()) or (select private.is_staff()));

create policy reports_insert_own on public.reports
  for insert to authenticated
  with check (reporter_id = (select auth.uid()));

-- ---------------------------------------------------------------------------
-- appeals: a user appeals decisions about their own content and sees their
-- own appeals. Staff resolve them server-side.
-- ---------------------------------------------------------------------------

grant select on public.appeals to authenticated;
grant insert (target_type, target_id, user_id, message) on public.appeals to authenticated;

create policy appeals_select_own_or_staff on public.appeals
  for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_staff()));

create policy appeals_insert_own on public.appeals
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (select private.can_appeal(target_type, target_id))
  );

-- ai_spend_daily: server only (RLS on, no policies, no grants).

-- ---------------------------------------------------------------------------
-- Public read views.
--
-- These are deliberately NOT security_invoker: they run with the owner's
-- rights so they can read past the owner-only RLS on the base tables, and
-- they are the single place that decides what the public may see. Supabase's
-- linter flags this pattern ("security definer view"); it is intentional.
-- Do not add columns here without checking they are safe to publish.
-- ---------------------------------------------------------------------------

create view public.plot_items_public
with (security_barrier = true)
as
select
  i.id,
  i.plot_id,
  i.type,
  i.position,
  i.moderation_status,
  -- Blurred (reported, under review) items keep their slot on the plot but
  -- their content is withheld.
  case when i.moderation_status = 'approved' then i.content end as content,
  case when i.moderation_status = 'approved' then i.asset_sha256 end as asset_sha256,
  i.created_at,
  i.updated_at
from public.plot_items i
join public.plots p on p.id = i.plot_id
left join public.assets a on a.sha256 = i.asset_sha256
where p.status = 'active'
  and i.moderation_status in ('approved', 'blurred')
  -- Defense in depth: an item never shows media that isn't itself approved.
  and (i.asset_sha256 is null or a.moderation_status = 'approved');

create view public.comments_public
with (security_barrier = true)
as
select
  c.id,
  c.plot_id,
  c.author_id,
  c.moderation_status,
  case when c.moderation_status = 'approved' then c.body end as body,
  c.created_at
from public.comments c
join public.plots p on p.id = c.plot_id
where p.status = 'active'
  and c.deleted_at is null
  and c.moderation_status in ('approved', 'blurred');

revoke all on public.plot_items_public, public.comments_public from anon, authenticated;
grant select on public.plot_items_public, public.comments_public to anon, authenticated;
