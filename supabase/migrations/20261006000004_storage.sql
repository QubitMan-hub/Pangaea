-- Storage buckets.
--
--   uploads    private. Owners upload raw images here under `<user id>/...`.
--              Nobody else can read them: they are unmoderated.
--   media      public. The server copies an image here only after it passes
--              moderation. Written by the service role only.
--   thumbnails public. Server-rendered PNG plot thumbnails (brief 3), built
--              from approved content only. Written by the service role only.
--
-- SVG is excluded everywhere (it can carry script). GIF is excluded for now
-- because image moderation APIs typically check a single frame.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('uploads', 'uploads', false, 10485760, array['image/png', 'image/jpeg', 'image/webp']),
  ('media', 'media', true, 10485760, array['image/png', 'image/jpeg', 'image/webp']),
  ('thumbnails', 'thumbnails', true, 2097152, array['image/png'])
on conflict (id) do nothing;

create policy uploads_insert_own_folder on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'uploads'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy uploads_select_own_folder on storage.objects
  for select to authenticated
  using (
    bucket_id = 'uploads'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy uploads_delete_own_folder on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'uploads'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
