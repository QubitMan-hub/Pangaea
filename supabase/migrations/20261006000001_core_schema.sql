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

create type public.attention_kind as enum ('view', 'dwell', 'comment', 'return_visit');

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
  -- Decays exponentially; recomputed by a scheduled job (brief 5.2).
  earned_space double precision not null default 0
    constraint plots_earned_space_nonnegative check (earned_space >= 0),
  last_active_at timestamptz not null default now(),
  -- Derived ONLY from approved content by the server.
  summary text,
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
  moderation_status public.moderation_status not null default 'pending',
  -- Shown to the owner when rejected.
  moderation_reason text,
  moderated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index plot_items_plot_id_idx on public.plot_items (plot_id);
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
-- attention_events: raw signal for the growth job (written server-side only)
-- ---------------------------------------------------------------------------

create table public.attention_events (
  id bigint generated always as identity primary key,
  plot_id uuid not null references public.plots (id) on delete cascade,
  visitor_id uuid references public.users (id) on delete set null,
  kind public.attention_kind not null,
  value double precision not null default 1
    constraint attention_events_value_nonnegative check (value >= 0),
  created_at timestamptz not null default now()
);

create index attention_events_plot_time_idx on public.attention_events (plot_id, created_at);
create index attention_events_visitor_time_idx on public.attention_events (visitor_id, created_at);

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
