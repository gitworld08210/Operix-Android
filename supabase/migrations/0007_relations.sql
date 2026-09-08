-- Oneleven discovery-relations migration (0007).
-- Run this in the Supabase SQL editor AFTER 0001..0006 have been applied.
-- Contains no service_role/secret keys; the app authenticates with the public
-- anon (publishable) key and relies on the RLS policies below.
--
-- PURPOSE (Phase 3, slice 3 — FEAT-010): promote SAVES/bookmarks, RICHER
-- REACTIONS, HASHTAGS, MENTIONS, and LOCATION tags into FIRST-CLASS, INDEXED
-- relations so a later search/discovery phase (roadmap phase_5) is cheap. It
-- adds:
--   * public.saves          — server-backed bookmarks (private, per-user)
--   * public.reactions       — typed reactions (the 6 affect types), one per
--                              (user, post); GENERALIZES the single like
--   * public.hashtags        — the shared tag dictionary (public discovery)
--   * public.post_hashtags    — post <-> hashtag links (indexed for #tag lookup)
--   * public.post_mentions    — post -> mentioned user links (indexed for
--                              "posts mentioning me")
--   * posts.location/lat/lng  — an optional location tag (free text this phase)
-- Every relation carries the indexes a discovery phase needs and RLS that
-- either inherits the post author's visibility (via public.can_view_profile
-- from 0002, mirroring likes_select_viewable / comments_select_viewable) or is
-- owner/self-scoped.
--
-- ===========================================================================
-- REACTIONS-vs-LIKES COEXISTENCE DECISION (read before reviewing) — chosen:
-- "MIGRATE LIKE INTO REACTIONS; reactions is the general table."
--
--   * public.reactions is now the single client-writable reaction store for
--     ALL six types INCLUDING 'like'. The Dart client (post_repository.dart)
--     writes ONLY public.reactions now (upsert/delete keyed by (user_id,
--     post_id)); it no longer inserts into public.likes.
--   * posts.like_count is kept as the authoritative aggregate LIKE counter but
--     is now recomputed from public.reactions WHERE type='like' by the NEW
--     trigger sync_post_reaction_like_count below (mirroring 0001's
--     sync_post_like_count, but sourced from reactions).
--   * The 0001 public.likes table and its sync_post_like_count trigger are left
--     COMPLETELY UNTOUCHED (nothing is dropped, per the "never edit 0001-0006"
--     rule). They are simply DORMANT: because the client stops writing likes,
--     no new rows arrive, on_like_change never fires, and it therefore never
--     writes like_count. So like_count is driven by EXACTLY ONE source
--     (reactions) going forward — there is NO DOUBLE-COUNTING. If historical
--     rows exist in public.likes, a one-time backfill into public.reactions can
--     reconcile them (out of scope here); after backfill, likes stays dormant.
--   * The notify_on_like trigger from 0002 fires on public.likes inserts. Since
--     the client no longer writes likes, "like" notifications for the reaction
--     path are intentionally NOT produced by this migration (a notify-on-react
--     trigger is a follow-up); this is a deliberate, documented scope boundary,
--     not a bug.
-- ===========================================================================
--
-- Idempotency: this file is re-runnable. Every statement uses
-- `if not exists` / `drop ... if exists` before create / `create or replace` /
-- `on conflict`-friendly shapes, so applying it twice does not error.
--
-- ENV RISK (largest known risk for this slice): this SQL is UNVERIFIED against
-- a live Supabase project — there is no reachable/administerable instance and
-- no service-role key in this environment, so it has had STRUCTURAL REVIEW
-- ONLY. Live RLS enforcement, the reaction-count trigger, the FK/uniqueness
-- constraints, and index creation must be validated on a real project before
-- relying on them.

-- ---------------------------------------------------------------------------
-- (a) Saves / bookmarks (server-backed, private per-user)
-- ---------------------------------------------------------------------------

create table if not exists public.saves (
  user_id uuid references auth.users(id) on delete cascade,
  post_id uuid references public.posts(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, post_id)
);

alter table public.saves enable row level security;

-- saves are PRIVATE: a user may only see/create/remove their OWN save rows.
drop policy if exists "saves_select_own" on public.saves;
create policy "saves_select_own"
  on public.saves for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "saves_insert_own" on public.saves;
create policy "saves_insert_own"
  on public.saves for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "saves_delete_own" on public.saves;
create policy "saves_delete_own"
  on public.saves for delete to authenticated
  using (auth.uid() = user_id);

-- "my saves, newest-first" is the hot query for a Saved/bookmarks screen.
create index if not exists idx_saves_user
  on public.saves (user_id, created_at desc);

-- ---------------------------------------------------------------------------
-- (b) Reactions (typed; one per user per post) + like_count sync
-- ---------------------------------------------------------------------------

create table if not exists public.reactions (
  user_id uuid references auth.users(id) on delete cascade,
  post_id uuid references public.posts(id) on delete cascade,
  type text not null check (type in ('like', 'love', 'laugh', 'wow', 'sad', 'angry')),
  created_at timestamptz default now(),
  -- one reaction per user per post: switching type is an UPSERT on this pk.
  primary key (user_id, post_id)
);

alter table public.reactions enable row level security;

-- reactions: visible only when the viewer can see the reacted post's author
-- (mirrors likes_select_viewable from 0002); only the acting user may
-- create/update/remove their own reaction.
drop policy if exists "reactions_select_viewable" on public.reactions;
create policy "reactions_select_viewable"
  on public.reactions for select to authenticated
  using (
    exists (
      select 1 from public.posts p
      where p.id = reactions.post_id
        and public.can_view_profile(auth.uid(), p.owner)
    )
  );

drop policy if exists "reactions_insert_own" on public.reactions;
create policy "reactions_insert_own"
  on public.reactions for insert to authenticated
  with check (auth.uid() = user_id);

-- update is needed so an UPSERT that switches the reaction type succeeds.
drop policy if exists "reactions_update_own" on public.reactions;
create policy "reactions_update_own"
  on public.reactions for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "reactions_delete_own" on public.reactions;
create policy "reactions_delete_own"
  on public.reactions for delete to authenticated
  using (auth.uid() = user_id);

-- "reactions on a post, grouped by type" (the reactionCounts aggregate) and the
-- like-count recompute below both hit (post_id, type).
create index if not exists idx_reactions_post_type
  on public.reactions (post_id, type);

-- Server-authoritative posts.like_count, recomputed from public.reactions where
-- type='like' (see the coexistence decision at the head of this file). This is
-- the ONLY writer of like_count on the going-forward reaction path; the 0001
-- likes trigger is dormant, so there is no double-counting.
create or replace function public.sync_post_reaction_like_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_post uuid := coalesce(new.post_id, old.post_id);
begin
  update public.posts
    set like_count = (
      select count(*) from public.reactions
      where post_id = target_post and type = 'like'
    )
    where id = target_post;
  return null;
end;
$$;

-- Fires on insert/update (type switch to/from 'like') and delete.
drop trigger if exists on_reaction_change on public.reactions;
create trigger on_reaction_change
  after insert or update or delete on public.reactions
  for each row execute function public.sync_post_reaction_like_count();

-- ---------------------------------------------------------------------------
-- (c) Hashtags (shared dictionary) + post_hashtags (links)
-- ---------------------------------------------------------------------------

create table if not exists public.hashtags (
  id uuid primary key default gen_random_uuid(),
  tag text unique not null,
  created_at timestamptz default now()
);

alter table public.hashtags enable row level security;

-- hashtags are PUBLIC discovery data: any authenticated user may read them
-- (using true is intentional and documented — tags carry no private info) and
-- any authenticated user may upsert a tag into the shared dictionary (the link
-- to a post, which is where visibility matters, is gated on post_hashtags).
drop policy if exists "hashtags_select_all" on public.hashtags;
create policy "hashtags_select_all"
  on public.hashtags for select to authenticated
  using (true);

drop policy if exists "hashtags_insert_authenticated" on public.hashtags;
create policy "hashtags_insert_authenticated"
  on public.hashtags for insert to authenticated
  with check (true);

-- "find the tag row for #foo" — exact-match tag lookup.
create index if not exists idx_hashtags_tag on public.hashtags (tag);

create table if not exists public.post_hashtags (
  post_id uuid references public.posts(id) on delete cascade,
  hashtag_id uuid references public.hashtags(id) on delete cascade,
  primary key (post_id, hashtag_id)
);

alter table public.post_hashtags enable row level security;

-- post_hashtags: selectable when the viewer can see the linked post's author
-- (so "posts for #tag" respects privacy/blocking); insertable only by the post
-- OWNER (so a user can only tag their own posts).
drop policy if exists "post_hashtags_select_viewable" on public.post_hashtags;
create policy "post_hashtags_select_viewable"
  on public.post_hashtags for select to authenticated
  using (
    exists (
      select 1 from public.posts p
      where p.id = post_hashtags.post_id
        and public.can_view_profile(auth.uid(), p.owner)
    )
  );

drop policy if exists "post_hashtags_insert_owner" on public.post_hashtags;
create policy "post_hashtags_insert_owner"
  on public.post_hashtags for insert to authenticated
  with check (
    exists (
      select 1 from public.posts p
      where p.id = post_hashtags.post_id
        and p.owner = auth.uid()
    )
  );

drop policy if exists "post_hashtags_delete_owner" on public.post_hashtags;
create policy "post_hashtags_delete_owner"
  on public.post_hashtags for delete to authenticated
  using (
    exists (
      select 1 from public.posts p
      where p.id = post_hashtags.post_id
        and p.owner = auth.uid()
    )
  );

-- "all posts for a given hashtag" — the core discovery query.
create index if not exists idx_post_hashtags_hashtag
  on public.post_hashtags (hashtag_id);

-- ---------------------------------------------------------------------------
-- (d) Post mentions (post -> mentioned user)
-- ---------------------------------------------------------------------------

create table if not exists public.post_mentions (
  post_id uuid references public.posts(id) on delete cascade,
  mentioned_user uuid references auth.users(id) on delete cascade,
  primary key (post_id, mentioned_user)
);

alter table public.post_mentions enable row level security;

-- post_mentions: selectable when the viewer can see the mentioning post's
-- author (mirrors post visibility); insertable only by the post OWNER.
drop policy if exists "post_mentions_select_viewable" on public.post_mentions;
create policy "post_mentions_select_viewable"
  on public.post_mentions for select to authenticated
  using (
    exists (
      select 1 from public.posts p
      where p.id = post_mentions.post_id
        and public.can_view_profile(auth.uid(), p.owner)
    )
  );

drop policy if exists "post_mentions_insert_owner" on public.post_mentions;
create policy "post_mentions_insert_owner"
  on public.post_mentions for insert to authenticated
  with check (
    exists (
      select 1 from public.posts p
      where p.id = post_mentions.post_id
        and p.owner = auth.uid()
    )
  );

drop policy if exists "post_mentions_delete_owner" on public.post_mentions;
create policy "post_mentions_delete_owner"
  on public.post_mentions for delete to authenticated
  using (
    exists (
      select 1 from public.posts p
      where p.id = post_mentions.post_id
        and p.owner = auth.uid()
    )
  );

-- "posts mentioning me" — the core notification/discovery query.
create index if not exists idx_post_mentions_user
  on public.post_mentions (mentioned_user);

-- ---------------------------------------------------------------------------
-- (e) Location tag on posts (free text this phase; lat/lng optional)
-- ---------------------------------------------------------------------------

alter table public.posts
  add column if not exists location text;
alter table public.posts
  add column if not exists lat double precision;
alter table public.posts
  add column if not exists lng double precision;

-- Partial index so "posts at / near a location" is cheap without bloating the
-- index with the (common) null-location rows.
create index if not exists idx_posts_location
  on public.posts (location)
  where location is not null;
