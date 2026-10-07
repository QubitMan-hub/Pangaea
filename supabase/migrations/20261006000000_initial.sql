-- Pangaea V1 schema. One migration because nothing is in production yet;
-- later features add their own migrations.
--
-- Safety model: RLS on every table, privileges granted per column, so a
-- client can never write moderation, trust or growth fields. Visitors read
-- items and comments only through the *_public views, which return approved
-- rows (and reported rows with their content withheld).

create extension if not exists vector with schema extensions;

-- Not exposed by the Data API, so nothing here is callable as an RPC.
create schema private;
grant usage on schema private to anon, authenticated, service_role;
alter default privileges in schema private revoke execute on functions from public;

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------

create type public.moderation_status as enum ('pending', 'approved', 'rejected', 'blurred');
-- 'description' is the plot's required one-line description.
create type public.plot_item_type as enum ('description', 'text', 'link', 'image', 'drawing');
create type public.plot_status as enum ('active', 'suspended');
create type public.placement_kind as enum ('unplaced', 'auto', 'owner_chosen');
create type public.report_target as enum ('plot', 'plot_item', 'comment', 'user');
create type public.report_status as enum ('open', 'actioned', 'dismissed');
create type public.appeal_status as enum ('open', 'upheld', 'overturned');
create type public.staff_role as enum ('moderator', 'admin');
create type public.ai_purpose as enum ('region_label', 'borderline_text', 'image_check');

create function private.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Guards detect clients by role. They run as SECURITY INVOKER because inside
-- a definer function current_user would always be the owner.
create function private.is_client_role()
returns boolean
language sql
stable
set search_path = ''
as $$
  select current_user in ('anon', 'authenticated');
$$;

-- Position is layout only. Moving an item doesn't re-moderate it, so it must
-- not be able to carry text past review.
create function private.is_valid_position(value jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select jsonb_typeof(value) = 'object'
    and not exists (
      select 1 from jsonb_each(value) e
      where e.key not in ('x', 'y', 'width', 'height', 'angle', 'z')
         or jsonb_typeof(e.value) <> 'number'
    );
$$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  handle text not null unique
    constraint users_handle_format check (handle ~ '^[a-z0-9_]{3,24}$'),
  -- 0 new, 1 established, 2 trusted. Decides Claude image checks and report weight.
  trust_level smallint not null default 0
    constraint users_trust_level_range check (trust_level between 0 and 2),
  created_at timestamptz not null default now()
);

-- Separate from users so staff membership is never public.
create table public.staff (
  user_id uuid primary key references public.users (id) on delete cascade,
  role public.staff_role not null,
  created_at timestamptz not null default now()
);

create table public.regions (
  id uuid primary key default gen_random_uuid(),
  -- Named once by Claude, then never again.
  label text not null
    constraint regions_label_length check (char_length(label) between 1 and 60),
  color_slot smallint not null default 1
    constraint regions_color_slot_range check (color_slot between 1 and 8),
  is_frontier boolean not null default false,
  -- voyage-4-lite at 512 dims, half precision: about 1 KB, to fit the free 500 MB.
  centroid_embedding extensions.halfvec(512),
  center_x integer not null,
  center_y integer not null,
  plot_count integer not null default 0
    constraint regions_plot_count_nonnegative check (plot_count >= 0),
  created_at timestamptz not null default now(),
  constraint regions_centroid_required check (is_frontier or centroid_embedding is not null)
);

create unique index regions_single_frontier on public.regions (is_frontier) where is_frontier;

-- Content-addressed media: one row, one stored file, one moderation per hash.
create table public.assets (
  sha256 text primary key
    constraint assets_sha256_format check (sha256 ~ '^[0-9a-f]{64}$'),
  mime_type text not null
    constraint assets_mime_type check (mime_type in ('image/webp', 'image/jpeg')),
  byte_size integer not null
    constraint assets_byte_size_positive check (byte_size > 0),
  width integer not null
    constraint assets_width_positive check (width > 0),
  height integer not null
    constraint assets_height_positive check (height > 0),
  moderation_status public.moderation_status not null default 'pending',
  moderation_reason text,
  moderated_at timestamptz,
  -- A hash that passed the Claude check never needs it again.
  claude_checked_at timestamptz,
  -- From the Claude check; used for placement and as fallback alt text.
  ai_description text
    constraint assets_ai_description_length check (char_length(ai_description) <= 500),
  created_at timestamptz not null default now()
);

-- Hash of the original file (computed in the browser), so a re-upload of the
-- same file skips uploading and moderation.
create table public.asset_sources (
  source_sha256 text primary key
    constraint asset_sources_sha256_format check (source_sha256 ~ '^[0-9a-f]{64}$'),
  asset_sha256 text not null references public.assets (sha256) on delete cascade
);

-- Users may only place assets they uploaded themselves.
create table public.asset_uploads (
  asset_sha256 text not null references public.assets (sha256) on delete cascade,
  user_id uuid not null references public.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (asset_sha256, user_id)
);

create index asset_uploads_user_idx on public.asset_uploads (user_id);

create table public.plots (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references public.users (id) on delete cascade,
  region_id uuid references public.regions (id) on delete set null,
  placement public.placement_kind not null default 'unplaced',
  grid_x integer,
  grid_y integer,
  base_size integer not null default 1
    constraint plots_base_size_positive check (base_size > 0),
  -- Value as of earned_space_updated_at; decay is computed on read, so no job
  -- ever rewrites every plot.
  earned_space double precision not null default 0
    constraint plots_earned_space_nonnegative check (earned_space >= 0),
  earned_space_updated_at timestamptz not null default now(),
  -- Unchanged hash of the approved text means no embedding call.
  text_hash text,
  embedding extensions.halfvec(512),
  embedding_model text,
  thumbnail_asset_sha256 text references public.assets (sha256) on delete set null,
  thumb_hash text
    constraint plots_thumb_hash_length check (char_length(thumb_hash) <= 64),
  snapshot_version integer not null default 0,
  -- Includes signed-out visitors; display only, never growth.
  display_view_count bigint not null default 0
    constraint plots_display_views_nonnegative check (display_view_count >= 0),
  status public.plot_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plots_grid_both_or_neither check ((grid_x is null) = (grid_y is null)),
  constraint plots_grid_cell_unique unique (grid_x, grid_y)
);

create index plots_region_id_idx on public.plots (region_id);

create trigger plots_set_updated_at
  before update on public.plots
  for each row execute function private.set_updated_at();

create table public.plot_items (
  id uuid primary key default gen_random_uuid(),
  plot_id uuid not null references public.plots (id) on delete cascade,
  type public.plot_item_type not null,
  content jsonb not null
    constraint plot_items_content_object check (jsonb_typeof(content) = 'object')
    constraint plot_items_content_size check (pg_column_size(content) <= 65536),
  position jsonb not null default '{}'::jsonb
    constraint plot_items_position_shape check (private.is_valid_position(position)),
  -- Images must come through the asset pipeline: no hotlinked URLs.
  asset_sha256 text references public.assets (sha256) on delete restrict,
  moderation_status public.moderation_status not null default 'pending',
  -- Shown to the owner, kindly worded, when rejected.
  moderation_reason text,
  moderated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plot_items_image_has_asset check (type <> 'image' or asset_sha256 is not null),
  constraint plot_items_description_text check (
    type <> 'description' or char_length(coalesce(content ->> 'text', '')) between 1 and 120
  )
);

create index plot_items_plot_id_idx on public.plot_items (plot_id);
create index plot_items_asset_idx on public.plot_items (asset_sha256) where asset_sha256 is not null;
create index plot_items_pending_idx on public.plot_items (created_at) where moderation_status = 'pending';
create unique index plot_items_one_description on public.plot_items (plot_id) where type = 'description';

create trigger plot_items_set_updated_at
  before update on public.plot_items
  for each row execute function private.set_updated_at();

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  plot_id uuid not null references public.plots (id) on delete cascade,
  author_id uuid not null references public.users (id) on delete cascade,
  body text not null
    constraint comments_body_length check (char_length(body) between 1 and 2000),
  moderation_status public.moderation_status not null default 'pending',
  moderation_reason text,
  moderated_at timestamptz,
  -- Soft delete: hidden from everyone except staff.
  deleted_at timestamptz,
  deleted_by uuid references public.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint comments_deleted_pair check ((deleted_at is null) = (deleted_by is null))
);

create index comments_plot_id_idx on public.comments (plot_id, created_at);
create index comments_pending_idx on public.comments (created_at) where moderation_status = 'pending';

create trigger comments_set_updated_at
  before update on public.comments
  for each row execute function private.set_updated_at();

-- One row per plot, signed-in visitor and day. Browser batches are folded in,
-- so the table grows with visitors, not clicks; credited_score makes the
-- per-visitor daily cap exact.
create table public.attention_daily (
  plot_id uuid not null references public.plots (id) on delete cascade,
  visitor_id uuid not null references public.users (id) on delete cascade,
  day date not null,
  views integer not null default 0 constraint attention_daily_views_nonnegative check (views >= 0),
  dwell_seconds integer not null default 0
    constraint attention_daily_dwell_nonnegative check (dwell_seconds >= 0),
  credited_score double precision not null default 0
    constraint attention_daily_credited_nonnegative check (credited_score >= 0),
  updated_at timestamptz not null default now(),
  primary key (plot_id, visitor_id, day)
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  target_type public.report_target not null,
  target_id uuid not null,
  reporter_id uuid references public.users (id) on delete set null,
  -- Filled by the database from the reporter's trust, never by the client.
  reporter_trust_level smallint not null default 0
    constraint reports_trust_range check (reporter_trust_level between 0 and 2),
  weight real not null default 0.25 constraint reports_weight_range check (weight > 0 and weight <= 1),
  reason text not null constraint reports_reason_length check (char_length(reason) between 1 and 1000),
  status public.report_status not null default 'open',
  resolved_by uuid references public.users (id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  constraint reports_once_per_reporter unique (reporter_id, target_type, target_id)
);

create index reports_open_idx on public.reports (created_at) where status = 'open';
create index reports_target_idx on public.reports (target_type, target_id);

create table public.appeals (
  id uuid primary key default gen_random_uuid(),
  target_type public.report_target not null,
  target_id uuid not null,
  user_id uuid not null references public.users (id) on delete cascade,
  message text not null constraint appeals_message_length check (char_length(message) between 1 and 1000),
  status public.appeal_status not null default 'open',
  resolved_by uuid references public.users (id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

-- One open appeal per target; after a decision, a later rejection can be appealed again.
create unique index appeals_one_open_per_target on public.appeals (user_id, target_type, target_id)
  where status = 'open';

-- Every Claude call is counted here; the daily cap reads it.
create table public.ai_spend_daily (
  day date not null,
  purpose public.ai_purpose not null,
  requests integer not null default 0,
  input_tokens bigint not null default 0,
  output_tokens bigint not null default 0,
  estimated_cost_usd numeric(12, 6) not null default 0
    constraint ai_spend_cost_nonnegative check (estimated_cost_usd >= 0),
  primary key (day, purpose)
);

-- ---------------------------------------------------------------------------
-- Policy helpers (security definer so policies don't recurse through RLS)
-- ---------------------------------------------------------------------------

create function private.is_staff()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.staff s where s.user_id = (select auth.uid()));
$$;

create function private.owns_plot(target_plot_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.plots p where p.id = target_plot_id and p.owner_id = (select auth.uid())
  );
$$;

create function private.plot_is_active(target_plot_id uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.plots p where p.id = target_plot_id and p.status = 'active');
$$;

create function private.uploaded_asset(target_asset_sha256 text)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.asset_uploads au
    where au.asset_sha256 = target_asset_sha256 and au.user_id = (select auth.uid())
  );
$$;

-- Only your own content, and only when a decision is actually against it,
-- so nobody can flood human review with appeals about other people.
create function private.can_appeal(target public.report_target, target_uuid uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select case target
    when 'plot_item' then exists (
      select 1 from public.plot_items i join public.plots p on p.id = i.plot_id
      where i.id = target_uuid and p.owner_id = (select auth.uid())
        and i.moderation_status in ('rejected', 'blurred'))
    when 'comment' then exists (
      select 1 from public.comments c
      where c.id = target_uuid and c.author_id = (select auth.uid())
        and c.moderation_status in ('rejected', 'blurred'))
    when 'plot' then exists (
      select 1 from public.plots p
      where p.id = target_uuid and p.owner_id = (select auth.uid()) and p.status = 'suspended')
    else false
  end;
$$;

grant execute on all functions in schema private to anon, authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Guards: rules column grants can't express
-- ---------------------------------------------------------------------------

-- Any client change to content or media sends the item back to review.
create function private.plot_items_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if private.is_client_role()
    and (new.content is distinct from old.content or new.asset_sha256 is distinct from old.asset_sha256)
  then
    new.moderation_status := 'pending';
    new.moderation_reason := null;
    new.moderated_at := null;
  end if;
  return new;
end;
$$;

create trigger plot_items_guard
  before update on public.plot_items
  for each row execute function private.plot_items_guard();

create function private.plot_items_keep_description()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if private.is_client_role() and old.type = 'description' then
    raise exception 'A plot always has a description. Edit it instead.'
      using errcode = 'insufficient_privilege';
  end if;
  return old;
end;
$$;

create trigger plot_items_keep_description
  before delete on public.plot_items
  for each row execute function private.plot_items_keep_description();

create function private.comments_guard()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if private.is_client_role() then
    if old.deleted_at is not null then
      raise exception 'This comment was deleted' using errcode = 'insufficient_privilege';
    end if;
    if new.body is distinct from old.body then
      new.moderation_status := 'pending';
      new.moderation_reason := null;
      new.moderated_at := null;
    end if;
  end if;
  return new;
end;
$$;

create trigger comments_guard
  before update on public.comments
  for each row execute function private.comments_guard();

create function private.reports_weight()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  select u.trust_level into new.reporter_trust_level from public.users u where u.id = new.reporter_id;
  new.reporter_trust_level := coalesce(new.reporter_trust_level, 0);
  new.weight := case new.reporter_trust_level when 2 then 1.0 when 1 then 0.5 else 0.25 end;
  return new;
end;
$$;

create trigger reports_weight
  before insert on public.reports
  for each row execute function private.reports_weight();

-- Authors, and owners of the plot a comment is on, can delete it. Soft only:
-- moderators keep the row.
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
      and (c.author_id = caller
        or exists (select 1 from public.plots p where p.id = c.plot_id and p.owner_id = caller));
  get diagnostics updated = row_count;
  return updated = 1;
end;
$$;

revoke all on function public.delete_comment(uuid) from public, anon;
grant execute on function public.delete_comment(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Access control. Supabase grants ALL to anon/authenticated by default; we
-- revoke that and grant back only what each role needs.
-- ---------------------------------------------------------------------------

revoke all on all tables in schema public from anon, authenticated;

alter table public.users enable row level security;
alter table public.staff enable row level security;
alter table public.regions enable row level security;
alter table public.assets enable row level security;
alter table public.asset_sources enable row level security;
alter table public.asset_uploads enable row level security;
alter table public.plots enable row level security;
alter table public.plot_items enable row level security;
alter table public.comments enable row level security;
alter table public.attention_daily enable row level security;
alter table public.reports enable row level security;
alter table public.appeals enable row level security;
alter table public.ai_spend_daily enable row level security;
-- asset_sources, attention_daily and ai_spend_daily: server only (no grants).

grant select on public.users to anon, authenticated;
grant update (handle) on public.users to authenticated;
create policy users_select on public.users for select to anon, authenticated using (true);
create policy users_update_own on public.users for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

grant select on public.staff to authenticated;
create policy staff_select_own on public.staff for select to authenticated
  using (user_id = (select auth.uid()));

grant select on public.regions to anon, authenticated;
create policy regions_select on public.regions for select to anon, authenticated using (true);

-- Uploaders see their own pending and rejected media (with the reason).
grant select on public.assets to anon, authenticated;
create policy assets_select on public.assets for select to anon, authenticated
  using (
    moderation_status = 'approved'
    or (select private.uploaded_asset(sha256))
    or (select private.is_staff())
  );

grant select on public.asset_uploads to authenticated;
create policy asset_uploads_select_own on public.asset_uploads for select to authenticated
  using (user_id = (select auth.uid()));

-- Placement, size, embedding and thumbnail are system-managed: clients only
-- read, and only the columns the map needs.
grant select (
  id, owner_id, region_id, placement, grid_x, grid_y, base_size,
  thumbnail_asset_sha256, thumb_hash, snapshot_version, display_view_count, status, created_at
) on public.plots to anon, authenticated;
create policy plots_select on public.plots for select to anon, authenticated
  using (status = 'active' or owner_id = (select auth.uid()) or (select private.is_staff()));

-- Base table is owner and staff only; visitors use plot_items_public. Client
-- ids are allowed so the editor can upsert by its own element ids.
grant select, delete on public.plot_items to authenticated;
grant insert (id, plot_id, type, content, position, asset_sha256) on public.plot_items to authenticated;
grant update (content, position, asset_sha256) on public.plot_items to authenticated;
create policy plot_items_select on public.plot_items for select to authenticated
  using ((select private.owns_plot(plot_id)) or (select private.is_staff()));
create policy plot_items_insert on public.plot_items for insert to authenticated
  with check (
    (select private.owns_plot(plot_id))
    and (asset_sha256 is null or (select private.uploaded_asset(asset_sha256)))
  );
create policy plot_items_update on public.plot_items for update to authenticated
  using ((select private.owns_plot(plot_id)))
  with check (
    (select private.owns_plot(plot_id))
    and (asset_sha256 is null or (select private.uploaded_asset(asset_sha256)))
  );
create policy plot_items_delete on public.plot_items for delete to authenticated
  using ((select private.owns_plot(plot_id)));

-- Pending comments are hidden from the plot owner too, so harassment never
-- reaches its target before review. No client deletes: see delete_comment().
grant select on public.comments to authenticated;
grant insert (id, plot_id, author_id, body) on public.comments to authenticated;
grant update (body) on public.comments to authenticated;
create policy comments_select on public.comments for select to authenticated
  using (author_id = (select auth.uid()) or (select private.is_staff()));
create policy comments_insert on public.comments for insert to authenticated
  with check (author_id = (select auth.uid()) and (select private.plot_is_active(plot_id)));
create policy comments_update on public.comments for update to authenticated
  using (author_id = (select auth.uid())) with check (author_id = (select auth.uid()));

grant select on public.reports to authenticated;
grant insert (target_type, target_id, reporter_id, reason) on public.reports to authenticated;
create policy reports_select on public.reports for select to authenticated
  using (reporter_id = (select auth.uid()) or (select private.is_staff()));
create policy reports_insert on public.reports for insert to authenticated
  with check (reporter_id = (select auth.uid()));

grant select on public.appeals to authenticated;
grant insert (target_type, target_id, user_id, message) on public.appeals to authenticated;
create policy appeals_select on public.appeals for select to authenticated
  using (user_id = (select auth.uid()) or (select private.is_staff()));
create policy appeals_insert on public.appeals for insert to authenticated
  with check (user_id = (select auth.uid()) and (select private.can_appeal(target_type, target_id)));

-- Public views run with the owner's rights on purpose: they are the one place
-- that decides what the public sees. Check any new column is safe to publish.
create view public.plot_items_public with (security_barrier = true) as
select
  i.id, i.plot_id, i.type, i.position, i.moderation_status,
  -- Reported (blurred) items keep their slot, but their content is withheld.
  case when i.moderation_status = 'approved' then i.content end as content,
  case when i.moderation_status = 'approved' then i.asset_sha256 end as asset_sha256,
  i.created_at, i.updated_at
from public.plot_items i
join public.plots p on p.id = i.plot_id
left join public.assets a on a.sha256 = i.asset_sha256
where p.status = 'active'
  and i.moderation_status in ('approved', 'blurred')
  and (i.asset_sha256 is null or a.moderation_status = 'approved');

create view public.comments_public with (security_barrier = true) as
select
  c.id, c.plot_id, c.author_id, c.moderation_status,
  case when c.moderation_status = 'approved' then c.body end as body,
  c.created_at
from public.comments c
join public.plots p on p.id = c.plot_id
where p.status = 'active' and c.deleted_at is null and c.moderation_status in ('approved', 'blurred');

revoke all on public.plot_items_public, public.comments_public from anon, authenticated;
grant select on public.plot_items_public, public.comments_public to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Reference data and local storage
-- ---------------------------------------------------------------------------

-- Plots wait here until they fit a region.
insert into public.regions (label, is_frontier, color_slot, center_x, center_y)
values ('Frontier', true, 4, 0, 0);

-- Local stand-ins for the two R2 buckets (Supabase Storage speaks S3 too).
-- Clients upload through presigned URLs for single-use keys, so no storage
-- policies are needed. SVG is never accepted: it can carry script.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('private', 'private', false, 5242880, array['image/webp', 'image/jpeg']),
  ('public', 'public', true, 5242880, array['image/webp', 'image/jpeg', 'application/json'])
on conflict (id) do nothing;
