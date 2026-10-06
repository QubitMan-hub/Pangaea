-- Pangaea core schema: tables, enums, indexes.
-- Access control (RLS, grants, views) lives in the next migration so the two
-- can be reviewed separately.

create extension if not exists vector with schema extensions;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type public.moderation_status as enum ('pending', 'approved', 'rejected', 'blurred');

-- 'description' is the plot's one-line description (exactly one per plot,
-- required at signup). It is moderated like any text and not drawn on the canvas.
create type public.plot_item_type as enum (
  'description', 'text', 'drawing', 'image', 'link', 'code', 'webpage', 'video', 'document'
);

-- How a plot got its place: automatically, chosen by its owner when it
-- couldn't be placed automatically, or not yet placed.
create type public.placement_kind as enum ('unplaced', 'auto', 'owner_chosen');

-- 'suspended' hides a whole plot from the public (e.g. owner banned).
create type public.plot_status as enum ('active', 'suspended');

create type public.report_target as enum ('plot', 'plot_item', 'comment', 'user');

create type public.report_status as enum ('open', 'actioned', 'dismissed');

create type public.staff_role as enum ('moderator', 'admin');

create type public.appeal_status as enum ('open', 'upheld', 'overturned');

-- What a Claude call was for; each counts against the daily spend cap.
create type public.ai_purpose as enum (
  'region_label', 'continent_label', 'borderline_text', 'image_check'
);

-- ---------------------------------------------------------------------------
-- Shared trigger: keep updated_at current
-- ---------------------------------------------------------------------------

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- private schema: helpers the Data API never exposes (grants are set in the
-- access-control migration)
-- ---------------------------------------------------------------------------

create schema private;

-- A plot item's position: an object whose only keys are x, y, width, height,
-- angle and z, each a finite number.
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
-- users: public profile, 1:1 with auth.users
-- ---------------------------------------------------------------------------

create table public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  handle text not null unique
    constraint users_handle_format check (handle ~ '^[a-z0-9_]{3,24}$'),
  -- 0 new, 1 established, 2 trusted
  trust_level smallint not null default 0
    constraint users_trust_level_range check (trust_level between 0 and 2),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger users_set_updated_at
  before update on public.users
  for each row execute function public.set_updated_at();

-- Moderators/admins. Kept out of `users` so staff membership is never public.
create table public.staff (
  user_id uuid primary key references public.users (id) on delete cascade,
  role public.staff_role not null,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- continents and regions: the map's topic hierarchy
--
-- Labels are named once by Claude and cached forever. `color_slot` is one of
-- the 8 region hues in docs/design.md, assigned so neighbors stay
-- distinguishable; it never changes for a region.
-- ---------------------------------------------------------------------------

create table public.continents (
  id uuid primary key default gen_random_uuid(),
  label text not null
    constraint continents_label_length check (char_length(label) between 1 and 60),
  created_at timestamptz not null default now()
);

create table public.regions (
  id uuid primary key default gen_random_uuid(),
  continent_id uuid references public.continents (id) on delete set null,
  label text not null
    constraint regions_label_length check (char_length(label) between 1 and 60),
  color_slot smallint not null default 1
    constraint regions_color_slot_range check (color_slot between 1 and 8),
  -- The frontier holds plots that do not yet fit any region.
  is_frontier boolean not null default false,
  -- Voyage voyage-4-lite, 512 dims, half precision (about 1 KB). Null only for the frontier.
  centroid_embedding extensions.halfvec(512),
  center_x integer not null,
  center_y integer not null,
  plot_count integer not null default 0
    constraint regions_plot_count_nonnegative check (plot_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint regions_centroid_required check (is_frontier or centroid_embedding is not null)
);

-- At most one frontier region.
create unique index regions_single_frontier on public.regions (is_frontier) where is_frontier;
create index regions_continent_idx on public.regions (continent_id);

create trigger regions_set_updated_at
  before update on public.regions
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- assets: content-addressed media (docs/architecture.md, "Uploads")
--
-- The browser resizes and re-encodes every image (WebP, JPEG as last resort,
-- metadata stripped). The server verifies the bytes' SHA-256, stores the file
-- once under that hash and moderates it once. The same meme uploaded a
-- thousand times is one row, one object, one scan.
-- ---------------------------------------------------------------------------

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
  -- Set once this exact file has passed the Claude image check (CLAUDE.md
  -- 7.4). A hash that passed is never sent to Claude again.
  claude_checked_at timestamptz,
  -- Short description from the Claude check: placement text and fallback alt text.
  ai_description text
    constraint assets_ai_description_length check (char_length(ai_description) <= 500),
  created_at timestamptz not null default now()
);

-- Maps the hash of an original file (computed in the browser) to the asset it
-- produced, so a byte-identical re-upload skips uploading and moderation.
create table public.asset_sources (
  source_sha256 text primary key
    constraint asset_sources_sha256_format check (source_sha256 ~ '^[0-9a-f]{64}$'),
  asset_sha256 text not null references public.assets (sha256) on delete cascade,
  created_at timestamptz not null default now()
);

create index asset_sources_asset_idx on public.asset_sources (asset_sha256);

-- Who uploaded what. A user may only place assets they uploaded themselves.
create table public.asset_uploads (
  asset_sha256 text not null references public.assets (sha256) on delete cascade,
  user_id uuid not null references public.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (asset_sha256, user_id)
);

create index asset_uploads_user_idx on public.asset_uploads (user_id);

-- ---------------------------------------------------------------------------
-- plots: one per user
-- ---------------------------------------------------------------------------

create table public.plots (
  id uuid primary key default gen_random_uuid(),
  -- unique: one plot per user (product rule)
  owner_id uuid not null unique references public.users (id) on delete cascade,
  region_id uuid references public.regions (id) on delete set null,
  placement public.placement_kind not null default 'unplaced',
  -- World grid anchor cell. Null until placed.
  grid_x integer,
  grid_y integer,
  -- Footprint size; exact units (cells per side) are settled in Phase 4.
  base_size integer not null default 1
    constraint plots_base_size_positive check (base_size > 0),
  -- Earned space as of earned_space_updated_at. It decays exponentially and
  -- is computed on read; no job rewrites it (docs/architecture.md, "Growth").
  -- Any write first brings it up to date, then adds the new points.
  earned_space double precision not null default 0
    constraint plots_earned_space_nonnegative check (earned_space >= 0),
  earned_space_updated_at timestamptz not null default now(),
  last_active_at timestamptz not null default now(),
  -- Updated at most once per plot per day; drives cold storage.
  last_visited_at timestamptz not null default now(),
  -- Hash of the normalized approved text last embedded. Unchanged hash, no
  -- Voyage call (CLAUDE.md 7.9).
  text_hash text,
  embedding extensions.halfvec(512),
  -- Which embedding model produced `embedding`, so a model change can be detected.
  embedding_model text,
  -- Current approved thumbnail (content-addressed) and its tiny blur placeholder.
  thumbnail_asset_sha256 text references public.assets (sha256) on delete set null,
  thumb_hash text
    constraint plots_thumb_hash_length check (char_length(thumb_hash) <= 64),
  -- Version of the published snapshot JSON in R2 that visitors read.
  snapshot_version integer not null default 0,
  -- Set while the plot's content lives in R2 cold storage (CLAUDE.md 7.11).
  cold_storage_key text,
  -- Views from everyone, including signed-out visitors. Display only; never growth.
  display_view_count bigint not null default 0
    constraint plots_display_views_nonnegative check (display_view_count >= 0),
  status public.plot_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plots_grid_both_or_neither check ((grid_x is null) = (grid_y is null)),
  constraint plots_grid_cell_unique unique (grid_x, grid_y)
);

create index plots_region_id_idx on public.plots (region_id);
create index plots_last_visited_idx on public.plots (last_visited_at) where cold_storage_key is null;

create trigger plots_set_updated_at
  before update on public.plots
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- plot_items: the things on a plot
-- ---------------------------------------------------------------------------

create table public.plot_items (
  id uuid primary key default gen_random_uuid(),
  plot_id uuid not null references public.plots (id) on delete cascade,
  type public.plot_item_type not null,
  content jsonb not null
    constraint plot_items_content_object check (jsonb_typeof(content) = 'object')
    -- Large media lives in Storage; content only references it.
    constraint plot_items_content_size check (pg_column_size(content) <= 65536),
  -- Layout only, never content: moving an item doesn't re-moderate it, so
  -- position may hold nothing but these numeric fields (otherwise it could
  -- smuggle unmoderated text onto an approved item).
  position jsonb not null default '{}'::jsonb
    constraint plot_items_position_shape check (private.is_valid_position(position)),
  -- Media for image items (and later webpage screenshots). Images must come
  -- through the asset pipeline: no hotlinked URLs in content.
  asset_sha256 text references public.assets (sha256) on delete restrict,
  moderation_status public.moderation_status not null default 'pending',
  -- Shown to the owner when rejected.
  moderation_reason text,
  moderated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plot_items_image_has_asset check (type <> 'image' or asset_sha256 is not null),
  constraint plot_items_description_text check (
    type <> 'description'
    or char_length(coalesce(content ->> 'text', '')) between 1 and 120
  )
);

-- Exactly one description per plot (the "at least one" half is enforced by
-- signup creating it and clients not being allowed to delete it).
create unique index plot_items_one_description on public.plot_items (plot_id)
  where type = 'description';

create index plot_items_plot_id_idx on public.plot_items (plot_id);
create index plot_items_asset_idx on public.plot_items (asset_sha256) where asset_sha256 is not null;
create index plot_items_pending_idx on public.plot_items (created_at)
  where moderation_status = 'pending';

create trigger plot_items_set_updated_at
  before update on public.plot_items
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- comments
-- ---------------------------------------------------------------------------

create table public.comments (
  id uuid primary key default gen_random_uuid(),
  plot_id uuid not null references public.plots (id) on delete cascade,
  author_id uuid not null references public.users (id) on delete cascade,
  body text not null
    constraint comments_body_length check (char_length(body) between 1 and 2000),
  moderation_status public.moderation_status not null default 'pending',
  moderation_reason text,
  moderated_at timestamptz,
  -- Soft delete: hidden from everyone but staff (CLAUDE.md section 3).
  deleted_at timestamptz,
  deleted_by uuid references public.users (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint comments_deleted_pair check ((deleted_at is null) = (deleted_by is null))
);

create index comments_plot_id_idx on public.comments (plot_id, created_at);
create index comments_author_id_idx on public.comments (author_id);
create index comments_pending_idx on public.comments (created_at)
  where moderation_status = 'pending';

create trigger comments_set_updated_at
  before update on public.comments
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- missions
-- ---------------------------------------------------------------------------

create table public.missions (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique
    constraint missions_slug_format check (slug ~ '^[a-z0-9-]{3,64}$'),
  title text not null,
  description text not null,
  reward_points integer not null
    constraint missions_reward_nonnegative check (reward_points >= 0),
  is_sponsored boolean not null default false,
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now(),
  constraint missions_window_order check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create table public.mission_completions (
  id uuid primary key default gen_random_uuid(),
  mission_id uuid not null references public.missions (id) on delete cascade,
  user_id uuid not null references public.users (id) on delete cascade,
  plot_id uuid not null references public.plots (id) on delete cascade,
  evidence jsonb not null default '{}'::jsonb,
  verified boolean not null default false,
  created_at timestamptz not null default now(),
  -- MVP missions are one-time. Revisit if repeatable missions are added.
  constraint mission_completions_once unique (mission_id, user_id)
);

create index mission_completions_user_id_idx on public.mission_completions (user_id);

-- ---------------------------------------------------------------------------
-- attention_daily: one row per plot, visitor and day (written server-side only)
--
-- The browser batches views and dwell time and flushes them every ~30 s. The
-- server folds each batch into this row instead of storing raw events, so the
-- table grows with unique daily visitors, not with clicks. `credited_score`
-- is how much of this visitor's capped daily contribution has already been
-- added to the plot's earned space, which makes the per-visitor daily cap
-- exact (brief 5.2).
-- ---------------------------------------------------------------------------

create table public.attention_daily (
  plot_id uuid not null references public.plots (id) on delete cascade,
  visitor_id uuid not null references public.users (id) on delete cascade,
  day date not null,
  views integer not null default 0
    constraint attention_daily_views_nonnegative check (views >= 0),
  dwell_seconds integer not null default 0
    constraint attention_daily_dwell_nonnegative check (dwell_seconds >= 0),
  is_return_visit boolean not null default false,
  credited_score double precision not null default 0
    constraint attention_daily_credited_nonnegative check (credited_score >= 0),
  updated_at timestamptz not null default now(),
  primary key (plot_id, visitor_id, day)
);

create index attention_daily_visitor_idx on public.attention_daily (visitor_id, day);

create trigger attention_daily_set_updated_at
  before update on public.attention_daily
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- region_visits: powers "wander" (unvisited regions) and the visit mission
-- ---------------------------------------------------------------------------

create table public.region_visits (
  user_id uuid not null references public.users (id) on delete cascade,
  region_id uuid not null references public.regions (id) on delete cascade,
  first_visited_at timestamptz not null default now(),
  primary key (user_id, region_id)
);

-- ---------------------------------------------------------------------------
-- reports
-- ---------------------------------------------------------------------------

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  target_type public.report_target not null,
  -- Polymorphic, so no FK; resolved by target_type.
  target_id uuid not null,
  reporter_id uuid references public.users (id) on delete set null,
  -- Snapshot of the reporter's trust when reporting, and the weight it gives
  -- (docs/decisions.md ADR-015). Filled by the database, not the client.
  reporter_trust_level smallint not null default 0
    constraint reports_trust_range check (reporter_trust_level between 0 and 2),
  weight real not null default 0.25
    constraint reports_weight_range check (weight > 0 and weight <= 1),
  reason text not null
    constraint reports_reason_length check (char_length(reason) between 1 and 1000),
  status public.report_status not null default 'open',
  resolved_by uuid references public.users (id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  -- One report per reporter per target.
  constraint reports_once_per_reporter unique (reporter_id, target_type, target_id)
);

create index reports_open_idx on public.reports (created_at) where status = 'open';
create index reports_target_idx on public.reports (target_type, target_id);

-- ---------------------------------------------------------------------------
-- appeals: a person asks for a human to look again at a moderation decision
-- ---------------------------------------------------------------------------

create table public.appeals (
  id uuid primary key default gen_random_uuid(),
  target_type public.report_target not null,
  target_id uuid not null,
  user_id uuid not null references public.users (id) on delete cascade,
  message text not null
    constraint appeals_message_length check (char_length(message) between 1 and 1000),
  status public.appeal_status not null default 'open',
  resolved_by uuid references public.users (id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

-- One open appeal per person per target. After a decision, a later rejection
-- of the same (edited) item can be appealed again.
create unique index appeals_one_open_per_target on public.appeals (user_id, target_type, target_id)
  where status = 'open';
create index appeals_open_idx on public.appeals (created_at) where status = 'open';

-- ---------------------------------------------------------------------------
-- ai_spend_daily: every Claude call is counted here; the daily cap reads it
-- ---------------------------------------------------------------------------

create table public.ai_spend_daily (
  day date not null,
  purpose public.ai_purpose not null,
  requests integer not null default 0
    constraint ai_spend_requests_nonnegative check (requests >= 0),
  input_tokens bigint not null default 0
    constraint ai_spend_input_nonnegative check (input_tokens >= 0),
  output_tokens bigint not null default 0
    constraint ai_spend_output_nonnegative check (output_tokens >= 0),
  estimated_cost_usd numeric(12, 6) not null default 0
    constraint ai_spend_cost_nonnegative check (estimated_cost_usd >= 0),
  primary key (day, purpose)
);
