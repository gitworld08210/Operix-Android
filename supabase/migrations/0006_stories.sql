-- Oneleven stories migration (0006) — 24h ephemeral stories.
-- Run this in the Supabase SQL editor AFTER 0001..0005 have been applied.
-- Contains no service_role/secret keys; the app authenticates with the public
-- anon (publishable) key and relies on the policies below.
--
-- What this migration adds:
--   * public.stories       — ephemeral stories carrying media BY URL/reference
--       (media_url), with an EXPIRY column (expires_at). PHASE 4 SEAM: real
--       device capture/upload is a later phase; this phase stores an already
--       hosted media_url.
--   * public.story_views   — server-side seen tracking, keyed by
--       (story_id, viewer), so seen/unseen can later be server-authoritative
--       (the client records a view via StoryRepository._persistSeen).
--   * Author-inherited, not-expired READ RLS mirroring the
--       comments_select_viewable / reposts_select_viewable visibility pattern
--       from 0002 (a can_view_profile(auth.uid(), owner) predicate), plus a
--       time predicate `expires_at > now()` so the SERVER — not just the client
--       — enforces ephemerality on read.
--   * Indexes for the active-stories query and a future expiry sweep.
--
-- ENV RISK (documented): this file has NOT been applied/exercised against a
-- live Supabase project in this environment (no reachable/administerable
-- project, no service-role key). It is validated by STRUCTURAL REVIEW ONLY. The
-- largest known risk is exactly the live behavior of the expiry predicate and
-- author-inherited RLS. Client-side ephemerality (Story.isActive filtering in
-- StoryRepository) is a UX mirror; the true gate is the server RLS below plus a
-- scheduled DELETE/sweep of expired rows (a LATER OPS CONCERN — e.g. a pg_cron
-- job `delete from public.stories where expires_at < now()` — not created here
-- because it needs the scheduler/service role unavailable in this env).
--
-- Idempotency: this file is re-runnable. Every statement uses
-- `if not exists` / `drop ... if exists` before create / `create or replace` /
-- a guarded DO block, so applying it twice does not error.

-- ---------------------------------------------------------------------------
-- Stories
-- ---------------------------------------------------------------------------

create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  owner uuid references auth.users(id) on delete cascade,
  media_url text not null,
  media_type text not null default 'image'
    check (media_type in ('image', 'video')),
  created_at timestamptz default now(),
  expires_at timestamptz not null
);

alter table public.stories enable row level security;

-- stories SELECT: visible only while NOT expired AND the viewer can see the
-- author. The `expires_at > now()` clause makes ephemerality server-enforced on
-- read; can_view_profile mirrors the author-visibility pattern used by
-- comments_select_viewable / reposts_select_viewable in 0002.
drop policy if exists "stories_select_viewable" on public.stories;
create policy "stories_select_viewable"
  on public.stories for select to authenticated
  using (
    expires_at > now()
    and public.can_view_profile(auth.uid(), owner)
  );

-- stories write: only the owner may create/update/delete their own stories.
drop policy if exists "stories_insert_own" on public.stories;
create policy "stories_insert_own"
  on public.stories for insert to authenticated
  with check (auth.uid() = owner);

drop policy if exists "stories_update_own" on public.stories;
create policy "stories_update_own"
  on public.stories for update to authenticated
  using (auth.uid() = owner)
  with check (auth.uid() = owner);

drop policy if exists "stories_delete_own" on public.stories;
create policy "stories_delete_own"
  on public.stories for delete to authenticated
  using (auth.uid() = owner);

-- ---------------------------------------------------------------------------
-- Story views (server-side seen tracking)
-- ---------------------------------------------------------------------------

create table if not exists public.story_views (
  story_id uuid references public.stories(id) on delete cascade,
  viewer uuid references auth.users(id) on delete cascade,
  seen_at timestamptz default now(),
  primary key (story_id, viewer)
);

alter table public.story_views enable row level security;

-- story_views SELECT: the viewer sees their OWN view rows, and a story's OWNER
-- sees who viewed their story (so a later "seen by" surface is possible).
drop policy if exists "story_views_select_own_or_owner" on public.story_views;
create policy "story_views_select_own_or_owner"
  on public.story_views for select to authenticated
  using (
    auth.uid() = viewer
    or exists (
      select 1 from public.stories s
      where s.id = story_views.story_id
        and s.owner = auth.uid()
    )
  );

-- story_views INSERT: a user may only record their OWN view, and only of a
-- story they can currently see (inherits the not-expired + author-visibility
-- gate from the stories SELECT policy shape).
drop policy if exists "story_views_insert_own" on public.story_views;
create policy "story_views_insert_own"
  on public.story_views for insert to authenticated
  with check (
    auth.uid() = viewer
    and exists (
      select 1 from public.stories s
      where s.id = story_views.story_id
        and s.expires_at > now()
        and public.can_view_profile(auth.uid(), s.owner)
    )
  );

drop policy if exists "story_views_delete_own" on public.story_views;
create policy "story_views_delete_own"
  on public.story_views for delete to authenticated
  using (auth.uid() = viewer);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

-- Active-stories-by-author lookup (StoryRepository.load / activeStoriesFor).
create index if not exists idx_stories_owner_expires
  on public.stories (owner, expires_at desc);
-- Supports a scheduled expiry sweep `... where expires_at < now()` (see head
-- comment) and the not-expired SELECT predicate.
create index if not exists idx_stories_expires
  on public.stories (expires_at);
-- "which stories has this viewer seen" lookup.
create index if not exists idx_story_views_viewer
  on public.story_views (viewer);
