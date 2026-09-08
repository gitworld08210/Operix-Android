-- Oneleven polymorphic content migration (0005).
-- Run this in the Supabase SQL editor AFTER 0001-0004 have been applied.
-- Contains no service_role/secret keys; the app authenticates with the public
-- anon (publishable) key and relies on the policies below.
--
-- What this migration adds (Phase 3, FEAT-008 — polymorphic content model):
--   * posts.kind — a content discriminator ('text' | 'image' | 'carousel' |
--     'video'). A post is text (no media), a single image, a single video, or
--     a multi-image carousel. Defaults to 'text'; existing rows need no data
--     backfill (the client mapper's legacy media_url fallback covers them).
--   * public.post_attachments — an ORDERED (post_id, position) list of media
--     references that generalizes the old single posts.media_url/media_type
--     slot into single-image, single-video, and multi-image CAROUSEL posts,
--     leaving room for new media kinds without reworking every consumer.
--
-- PHASE 4 SEAM: attachments are carried BY URL/reference only (url/thumb_url
-- point at already-hosted media). Real device capture + upload of bytes to the
-- storage bucket is Phase 4; this migration only models/stores the references.
--
-- Authorization: post_attachments SELECT visibility INHERITS the parent post's
-- author visibility, mirroring comments_select_viewable / reposts_select_viewable
-- from 0002 (join through public.posts + public.can_view_profile(auth.uid(),
-- owner)). Insert/update/delete are scoped to the parent post's owner.
--
-- Idempotency: re-runnable. Every statement uses `add column if not exists` /
-- `create table if not exists` / `drop policy if exists` before create /
-- `create index if not exists`, so applying it twice does not error.
--
-- ENV RISK (largest known risk for this change): this SQL was NOT applied or
-- exercised against a live Supabase project — there is no reachable/administerable
-- project and no service-role key in this environment. It is validated by
-- STRUCTURAL REVIEW ONLY (schema shape, RLS parity with the 0002 patterns,
-- idempotency). Live behavior (RLS enforcement, cascade deletes, the index) is
-- unverified and must be checked when this is applied to a real project.

-- ---------------------------------------------------------------------------
-- posts.kind — polymorphic content discriminator
-- ---------------------------------------------------------------------------

alter table public.posts
  add column if not exists kind text not null default 'text'
  check (kind in ('text', 'image', 'carousel', 'video'));

-- ---------------------------------------------------------------------------
-- post_attachments — ordered media references
-- ---------------------------------------------------------------------------

create table if not exists public.post_attachments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.posts(id) on delete cascade,
  position int not null default 0,
  type text not null check (type in ('image', 'video')),
  url text not null,
  thumb_url text,
  width int,
  height int,
  alt_text text,
  created_at timestamptz default now()
);

alter table public.post_attachments enable row level security;

-- post_attachments: visibility INHERITS the parent post's author visibility
-- (mirrors comments_select_viewable / reposts_select_viewable in 0002).
drop policy if exists "post_attachments_select_viewable" on public.post_attachments;
create policy "post_attachments_select_viewable"
  on public.post_attachments for select to authenticated
  using (
    exists (
      select 1 from public.posts p
      where p.id = post_attachments.post_id
        and public.can_view_profile(auth.uid(), p.owner)
    )
  );

-- post_attachments: only the parent post's owner may create/update/delete its
-- attachments.
drop policy if exists "post_attachments_insert_own" on public.post_attachments;
create policy "post_attachments_insert_own"
  on public.post_attachments for insert to authenticated
  with check (
    exists (
      select 1 from public.posts p
      where p.id = post_attachments.post_id
        and p.owner = auth.uid()
    )
  );

drop policy if exists "post_attachments_update_own" on public.post_attachments;
create policy "post_attachments_update_own"
  on public.post_attachments for update to authenticated
  using (
    exists (
      select 1 from public.posts p
      where p.id = post_attachments.post_id
        and p.owner = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.posts p
      where p.id = post_attachments.post_id
        and p.owner = auth.uid()
    )
  );

drop policy if exists "post_attachments_delete_own" on public.post_attachments;
create policy "post_attachments_delete_own"
  on public.post_attachments for delete to authenticated
  using (
    exists (
      select 1 from public.posts p
      where p.id = post_attachments.post_id
        and p.owner = auth.uid()
    )
  );

-- Ordered lookup by (post_id, position) — the natural read path for rendering a
-- post's attachments in order.
create index if not exists idx_post_attachments_post_position
  on public.post_attachments (post_id, position);
