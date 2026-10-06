-- Object storage buckets for LOCAL DEVELOPMENT.
--
-- In production, objects live in Cloudflare R2 behind Cloudflare's CDN
-- (free egress; docs/architecture.md, "Hosting"). The app talks to storage
-- only through the S3 API, and Supabase Storage speaks S3 too, so locally
-- these two buckets stand in for the two R2 buckets of the same names.
--
--   private  Never public. Single-use upload keys (`incoming/<user id>/<upload
--            id>`, written by the browser through a presigned URL), verified
--            media waiting for moderation (`pending/<sha256>.webp`, written
--            only by the server), cold storage (`cold/<plot id>.json`)
--            and encrypted backups (`backups/...`; a separate bucket in R2).
--   public   Served through the CDN with immutable caching. Only the server
--            writes here, and only approved or derived-from-approved data:
--              a/<sha256>.webp          approved media and thumbnails
--              p/<plot id>/<version>.json published plot snapshots
--              map/...                  world.json, regions, layout chunks
--
-- Clients never write to storage directly with their Supabase session:
-- uploads use short-lived presigned PUT URLs that the server issues for one
-- exact, never-reused key, so no storage RLS policies are needed.
-- The browser encodes every image to WebP (JPEG only where WebP encoding is
-- unavailable) before upload, so only those types are accepted. SVG is never
-- accepted (it can carry script).

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('private', 'private', false, 52428800, array['image/webp', 'image/jpeg', 'application/json', 'application/octet-stream']),
  ('public', 'public', true, 5242880, array['image/webp', 'image/jpeg', 'application/json'])
on conflict (id) do nothing;
