-- Pangaea core schema: tables, enums, indexes.
-- Access control (RLS, grants, views) lives in the next migration so the two
-- can be reviewed separately.

create extension if not exists vector with schema extensions;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------

create type public.moderation_status as enum ('pending', 'approved', 'rejected', 'blurred');

create type public.plot_item_type as enum (
  'text', 'drawing', 'image', 'link', 'code', 'webpage', 'video', 'document'
);

-- 'suspended' hides a whole plot from the public (e.g. owner banned).
create type public.plot_status as enum ('active', 'suspended');

create type public.report_target as enum ('plot', 'plot_item', 'comment', 'user');

create type public.report_status as enum ('open', 'actioned', 'dismissed');

create type public.staff_role as enum ('moderator', 'admin');

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
-- regions: topic "continents" on the map
-- ---------------------------------------------------------------------------

create table public.regions (
  id uuid primary key default gen_random_uuid(),
  label text not null
    constraint regions_label_length check (char_length(label) between 1 and 60),
  -- The frontier holds plots that do not yet fit any region (brief 5.1 step 5).
  is_frontier boolean not null default false,
  -- Voyage voyage-4 family, 1024 dims. Null only for the frontier.
  centroid_embedding extensions.vector(1024),
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

create trigger regions_set_updated_at
  before update on public.regions
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- plots: one per user
-- ---------------------------------------------------------------------------

create table public.plots (
  id uuid primary key default gen_random_uuid(),
  -- unique: one plot per user (product rule)
  owner_id uuid not null unique references public.users (id) on delete cascade,
  region_id uuid references public.regions (id) on delete set null,
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
  -- Derived ONLY from approved content by the server.
  summary text,
  -- Hash of the approved content `summary` was built from. If the content
  -- hash hasn't changed, no AI call is made (docs/architecture.md, "AI").
  summary_source_hash text,
  embedding extensions.vector(1024),
  -- Which embedding model produced `embedding`, so a model change can be detected.
  embedding_model text,
  thumbnail_url text,
  status public.plot_status not null default 'active',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plots_grid_both_or_neither check ((grid_x is null) = (grid_y is null)),
  constraint plots_grid_cell_unique unique (grid_x, grid_y)
);

create index plots_region_id_idx on public.plots (region_id);

create trigger plots_set_updated_at
  before update on public.plots
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- assets: content-addressed media (docs/architecture.md, "Uploads")
--
-- Every image is re-encoded server-side (WebP, resized, metadata stripped)
-- and stored once under the SHA-256 of the result, then moderated once. The
-- same meme uploaded a thousand times is one row, one object, one scan.
-- ---------------------------------------------------------------------------

create table public.assets (
  sha256 text primary key
    constraint assets_sha256_format check (sha256 ~ '^[0-9a-f]{64}$'),
  mime_type text not null
    constraint assets_mime_type check (mime_type in ('image/webp', 'image/avif')),
  byte_size integer not null
    constraint assets_byte_size_positive check (byte_size > 0),
  width integer not null
    constraint assets_width_positive check (width > 0),
  height integer not null
    constraint assets_height_positive check (height > 0),
  moderation_status public.moderation_status not null default 'pending',
  moderation_reason text,
  moderated_at timestamptz,
  created_at timestamptz not null default now()
);

-- Maps the hash of an original upload to the asset it produced, so a
-- byte-identical re-upload skips re-encoding and moderation entirely.
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
  position jsonb not null default '{}'::jsonb
    constraint plot_items_position_object check (jsonb_typeof(position) = 'object'),
  -- Media for image items (and later webpage screenshots). Images must come
  -- through the asset pipeline: no hotlinked URLs in content.
  asset_sha256 text references public.assets (sha256) on delete restrict,
  moderation_status public.moderation_status not null default 'pending',
  -- Shown to the owner when rejected.
  moderation_reason text,
  moderated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint plot_items_image_has_asset check (type <> 'image' or asset_sha256 is not null)
);

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
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
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
