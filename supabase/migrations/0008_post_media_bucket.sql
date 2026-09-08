-- Add a public `post-media` bucket for images attached to posts, mirroring the
-- owner-scoped write RLS of the existing `avatars` / `reels` buckets from
-- 0001_init.sql.
--
-- Rationale for a dedicated bucket (rather than reusing `reels`): the `reels`
-- bucket is semantically for short videos and its objects are surfaced through
-- the first-class `reels` table. Post images are a different content type with
-- their own lifecycle, so they get their own bucket. Objects are keyed by
-- `<userId>/<file>` so the per-object owner check gates each write.
--
-- Reads are public (served over the CDN via getPublicUrl), so we deliberately
-- add NO authenticated-only SELECT policy: it would be silently bypassed by the
-- public CDN path and only create a false impression that reads are gated.
-- Only writes are owner-scoped. This mirrors the design note in 0001_init.sql.
-- If a future version needs private post media, flip `public` to false here and
-- switch the client to createSignedUrl() instead of getPublicUrl().

insert into storage.buckets (id, name, public)
values ('post-media', 'post-media', true)
on conflict (id) do nothing;

-- Recreate the owner-scoped write policies to include the new bucket. Dropping
-- first keeps the bucket allow-list in a single place and makes the migration
-- idempotent.
drop policy if exists "storage_insert_own" on storage.objects;
create policy "storage_insert_own"
  on storage.objects for insert to authenticated
  with check (bucket_id in ('reels', 'avatars', 'post-media') and auth.uid() = owner);

drop policy if exists "storage_update_own" on storage.objects;
create policy "storage_update_own"
  on storage.objects for update to authenticated
  using (bucket_id in ('reels', 'avatars', 'post-media') and auth.uid() = owner)
  with check (bucket_id in ('reels', 'avatars', 'post-media') and auth.uid() = owner);

drop policy if exists "storage_delete_own" on storage.objects;
create policy "storage_delete_own"
  on storage.objects for delete to authenticated
  using (bucket_id in ('reels', 'avatars', 'post-media') and auth.uid() = owner);
