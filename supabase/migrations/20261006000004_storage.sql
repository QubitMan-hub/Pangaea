-- Object storage buckets for LOCAL DEVELOPMENT.
--
-- In production, objects live in Cloudflare R2 behind Cloudflare's CDN
-- (free egress; docs/architecture.md, "Hosting"). The app talks to storage
-- only through the S3 API, and Supabase Storage speaks S3 too, so locally
-- these two buckets stand in for the two R2 buckets of the same names.
--
--   private  Never public. Raw uploads (`raw/<user id>/...`, deleted after
--            processing) and re-encoded media waiting for moderation
--            (`pending/<sha256>.webp`).
--   public   Served through the CDN with immutable caching. Only the server
--            writes here, and only approved or derived-from-approved data:
--              a/<sha256>.webp          approved media
--              th/<sha256>.webp         plot thumbnails
--              t/<z>/<x>/<y>/<hash>.webp map tiles
--
-- Clients never write to storage directly with their Supabase session:
-- uploads use short-lived presigned PUT URLs that the server issues for one
-- exact key under raw/<their id>/, so no storage RLS policies are needed.
-- SVG is never accepted (it can carry script). GIFs are flattened to their
-- first frame on re-encode, so moderation scans exactly what is shown.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  (
    'private', 'private', false, 15728640,
    array['image/png', 'image/jpeg', 'image/webp', 'image/avif', 'image/gif']
  ),
  ('public', 'public', true, 5242880, array['image/webp', 'image/avif', 'application/json'])
on conflict (id) do nothing;
