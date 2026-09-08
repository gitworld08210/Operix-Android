-- Oneleven authorization + core-tables migration (0002).
-- Run this in the Supabase SQL editor AFTER 0001_init.sql has been applied.
-- Contains no service_role/secret keys; the app authenticates with the
-- public anon (publishable) key and relies on the policies below.
--
-- What this migration adds:
--   * Load-bearing subsystems later phases depend on:
--       - public.comments        (post replies, with server-owned reply_count)
--       - public.notifications    (centralized activity feed, trigger-produced)
--       - public.reposts          (join table + server-owned repost_count)
--   * Privacy + safety primitives:
--       - profiles.is_private     (private accounts)
--       - public.blocks           (mutual blocking)
--       - follows.status          ('pending' | 'accepted' follow requests)
--   * Server-authoritative READ authorization. 0001 let ANY authenticated user
--     read EVERY row (`*_select_authenticated using (true)`), an IDOR/privacy
--     gap. This migration replaces those permissive SELECT policies with ones
--     that call the SECURITY DEFINER helpers public.is_blocked /
--     public.can_view_profile, so privacy + blocking are enforced in the DB
--     rather than trusted to the client.
--   * Indexes for high-frequency queries and keyset-pagination-friendly
--     ordering.
--
-- Idempotency: this file is re-runnable. Every statement uses
-- `if not exists` / `drop ... if exists` before create / `on conflict do
-- nothing` / `create or replace` / a guarded DO block, so applying it twice
-- does not error.
--
-- Note: the Dart client is NOT changed by this migration. The client changes
-- to stop writing repost_count/reply_count (now server-owned) and to create
-- private-account follows as 'pending' land in FEAT-003.

-- ---------------------------------------------------------------------------
-- Privacy primitive: private accounts
-- ---------------------------------------------------------------------------

alter table public.profiles
  add column if not exists is_private boolean not null default false;

-- ---------------------------------------------------------------------------
-- Blocks (mutual blocking)
-- ---------------------------------------------------------------------------

create table if not exists public.blocks (
  blocker uuid references auth.users(id) on delete cascade,
  blocked uuid references auth.users(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (blocker, blocked)
);

alter table public.blocks enable row level security;

-- blocks: a user may only see, create, and remove their OWN block rows.
drop policy if exists "blocks_select_own" on public.blocks;
create policy "blocks_select_own"
  on public.blocks for select to authenticated
  using (auth.uid() = blocker);

drop policy if exists "blocks_insert_own" on public.blocks;
create policy "blocks_insert_own"
  on public.blocks for insert to authenticated
  with check (auth.uid() = blocker and blocker <> blocked);

drop policy if exists "blocks_delete_own" on public.blocks;
create policy "blocks_delete_own"
  on public.blocks for delete to authenticated
  using (auth.uid() = blocker);

-- ---------------------------------------------------------------------------
-- Follow requests: follows.status
-- ---------------------------------------------------------------------------
--
-- Contract: a follow of a PUBLIC account is created directly as 'accepted'. A
-- follow of a PRIVATE account is created by the client as 'pending' and later
-- flipped to 'accepted' by the followee (accepting the request). Private-account
-- content only becomes visible once the follow row is 'accepted' (see
-- can_view_profile below). The status column defaults to 'accepted' so existing
-- rows / public follows need no special handling.
alter table public.follows
  add column if not exists status text not null default 'accepted';

-- Add the ('pending','accepted') check constraint only if it is not present yet
-- (there is no `add constraint if not exists`, so guard it in a DO block).
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'follows_status_check'
  ) then
    alter table public.follows
      add constraint follows_status_check
      check (status in ('pending', 'accepted'));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Visibility helpers (server-authoritative authorization)
-- ---------------------------------------------------------------------------
--
-- These are the single source of truth for read authorization. They are
-- SECURITY DEFINER so they can inspect blocks/follows/profiles regardless of
-- the caller's own row-level policies, and `stable` so the planner may reuse
-- them within a statement.

-- is_blocked(a, b): true when a has blocked b OR b has blocked a. A block is
-- mutual for visibility purposes: neither party should see the other.
create or replace function public.is_blocked(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.blocks
    where (blocker = a and blocked = b)
       or (blocker = b and blocked = a)
  );
$$;

-- can_view_profile(viewer, target): true when
--   * viewer = target (always see yourself), OR
--   * viewer and target have NOT blocked each other AND
--       * the target profile is public, OR
--       * viewer follows target with an 'accepted' follow row.
create or replace function public.can_view_profile(viewer uuid, target uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select
    viewer = target
    or (
      not public.is_blocked(viewer, target)
      and (
        exists (
          select 1 from public.profiles p
          where p.id = target and p.is_private = false
        )
        or exists (
          select 1 from public.follows f
          where f.follower = viewer
            and f.followee = target
            and f.status = 'accepted'
        )
      )
    );
$$;

-- ---------------------------------------------------------------------------
-- Rewrite READ RLS to be server-authoritative (privacy + blocking)
-- ---------------------------------------------------------------------------
--
-- Replaces the permissive `*_select_authenticated using (true)` policies from
-- 0001. The owner-scoped insert/update/delete policies from 0001 remain correct
-- and are intentionally left untouched, as are the storage.objects policies and
-- the public-reads-for-storage rationale documented in 0001.

-- profiles: visible only when can_view_profile allows it.
drop policy if exists "profiles_select_authenticated" on public.profiles;
drop policy if exists "profiles_select_viewable" on public.profiles;
create policy "profiles_select_viewable"
  on public.profiles for select to authenticated
  using (public.can_view_profile(auth.uid(), id));

-- posts: visible only when the viewer can see the post's author.
drop policy if exists "posts_select_authenticated" on public.posts;
drop policy if exists "posts_select_viewable" on public.posts;
create policy "posts_select_viewable"
  on public.posts for select to authenticated
  using (public.can_view_profile(auth.uid(), owner));

-- reels: visible only when the viewer can see the reel's author.
drop policy if exists "reels_select_authenticated" on public.reels;
drop policy if exists "reels_select_viewable" on public.reels;
create policy "reels_select_viewable"
  on public.reels for select to authenticated
  using (public.can_view_profile(auth.uid(), owner));

-- follows: a follow row is visible to either party, or to anyone who can see
-- both profiles involved (so follower/following lists respect privacy/blocking).
drop policy if exists "follows_select_authenticated" on public.follows;
drop policy if exists "follows_select_viewable" on public.follows;
create policy "follows_select_viewable"
  on public.follows for select to authenticated
  using (
    auth.uid() in (follower, followee)
    or (
      public.can_view_profile(auth.uid(), follower)
      and public.can_view_profile(auth.uid(), followee)
    )
  );

-- likes: a like is visible only when the viewer can see the liked post's author.
drop policy if exists "likes_select_authenticated" on public.likes;
drop policy if exists "likes_select_viewable" on public.likes;
create policy "likes_select_viewable"
  on public.likes for select to authenticated
  using (
    exists (
      select 1 from public.posts p
      where p.id = likes.post_id
        and public.can_view_profile(auth.uid(), p.owner)
    )
  );

-- ---------------------------------------------------------------------------
-- Comments (post replies)
-- ---------------------------------------------------------------------------

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.posts(id) on delete cascade,
  owner uuid references auth.users(id) on delete cascade,
  parent_id uuid references public.comments(id) on delete cascade null,
  content text not null check (char_length(content) between 1 and 2000),
  like_count int not null default 0,
  created_at timestamptz default now()
);

alter table public.comments enable row level security;

-- comments: visibility inherits from the parent post's author.
drop policy if exists "comments_select_viewable" on public.comments;
create policy "comments_select_viewable"
  on public.comments for select to authenticated
  using (
    exists (
      select 1 from public.posts p
      where p.id = comments.post_id
        and public.can_view_profile(auth.uid(), p.owner)
    )
  );

-- comments: only the owner may create, and only on a post they can view.
drop policy if exists "comments_insert_own" on public.comments;
create policy "comments_insert_own"
  on public.comments for insert to authenticated
  with check (
    auth.uid() = owner
    and exists (
      select 1 from public.posts p
      where p.id = comments.post_id
        and public.can_view_profile(auth.uid(), p.owner)
    )
  );

drop policy if exists "comments_update_own" on public.comments;
create policy "comments_update_own"
  on public.comments for update to authenticated
  using (auth.uid() = owner)
  with check (auth.uid() = owner);

drop policy if exists "comments_delete_own" on public.comments;
create policy "comments_delete_own"
  on public.comments for delete to authenticated
  using (auth.uid() = owner);

-- ---------------------------------------------------------------------------
-- Server-authoritative reply_count (mirrors sync_post_like_count)
-- ---------------------------------------------------------------------------
--
-- Like `posts.like_count`, `posts.reply_count` is a denormalized counter owned
-- by the database, not the client. Recomputing from count(*) on every
-- insert/delete makes it idempotent and drift-free under concurrent clients.
-- The client must NOT write posts.reply_count (that Dart change lands in
-- FEAT-003).
create or replace function public.sync_post_reply_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_post uuid := coalesce(new.post_id, old.post_id);
begin
  update public.posts
    set reply_count = (
      select count(*) from public.comments where post_id = target_post
    )
    where id = target_post;
  return null;
end;
$$;

drop trigger if exists on_comment_change on public.comments;
create trigger on_comment_change
  after insert or delete on public.comments
  for each row execute function public.sync_post_reply_count();

-- ---------------------------------------------------------------------------
-- Reposts (join table) + server-authoritative repost_count
-- ---------------------------------------------------------------------------
--
-- This retires the client-write repost_count drift debt documented in 0001:
-- `posts.repost_count` becomes server-owned, recomputed from count(*) of the
-- reposts join table exactly like `sync_post_like_count`. The client change to
-- stop writing repost_count and to insert/delete on `reposts` instead lands in
-- FEAT-003.

create table if not exists public.reposts (
  user_id uuid references auth.users(id) on delete cascade,
  post_id uuid references public.posts(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, post_id)
);

alter table public.reposts enable row level security;

-- reposts: visible only when the viewer can see the reposted post's author;
-- only the acting user may create/remove their own repost.
drop policy if exists "reposts_select_viewable" on public.reposts;
create policy "reposts_select_viewable"
  on public.reposts for select to authenticated
  using (
    exists (
      select 1 from public.posts p
      where p.id = reposts.post_id
        and public.can_view_profile(auth.uid(), p.owner)
    )
  );

drop policy if exists "reposts_insert_own" on public.reposts;
create policy "reposts_insert_own"
  on public.reposts for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "reposts_delete_own" on public.reposts;
create policy "reposts_delete_own"
  on public.reposts for delete to authenticated
  using (auth.uid() = user_id);

create or replace function public.sync_post_repost_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_post uuid := coalesce(new.post_id, old.post_id);
begin
  update public.posts
    set repost_count = (
      select count(*) from public.reposts where post_id = target_post
    )
    where id = target_post;
  return null;
end;
$$;

drop trigger if exists on_repost_change on public.reposts;
create trigger on_repost_change
  after insert or delete on public.reposts
  for each row execute function public.sync_post_repost_count();

-- ---------------------------------------------------------------------------
-- Notifications (centralized activity feed, trigger-produced)
-- ---------------------------------------------------------------------------

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  recipient uuid references auth.users(id) on delete cascade,
  actor uuid references auth.users(id) on delete cascade,
  type text not null check (type in (
    'like', 'reply', 'repost', 'follow', 'mention', 'follow_request', 'system'
  )),
  entity_type text,
  entity_id uuid,
  preview text,
  read boolean not null default false,
  created_at timestamptz default now()
);

alter table public.notifications enable row level security;

-- notifications: a user may only read and update (mark read) their OWN
-- notifications. There is deliberately NO client insert policy: allowing
-- authenticated users to insert arbitrary `recipient` rows would let anyone
-- spoof notifications from any actor. Notifications are produced ONLY by the
-- SECURITY DEFINER triggers below, which run with the definer's rights and
-- bypass RLS insert restrictions.
drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
  on public.notifications for select to authenticated
  using (auth.uid() = recipient);

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own"
  on public.notifications for update to authenticated
  using (auth.uid() = recipient)
  with check (auth.uid() = recipient);

-- Notification producers. Each guards against self-notification
-- (actor <> recipient) and against blocked actors (is_blocked), so a user is
-- never notified about their own action or about a user they have blocked / who
-- has blocked them.

-- A new like notifies the liked post's owner.
create or replace function public.notify_on_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  post_owner uuid;
begin
  select owner into post_owner from public.posts where id = new.post_id;
  if post_owner is not null
     and post_owner <> new.user_id
     and not public.is_blocked(new.user_id, post_owner) then
    insert into public.notifications (recipient, actor, type, entity_type, entity_id)
    values (post_owner, new.user_id, 'like', 'post', new.post_id);
  end if;
  return null;
end;
$$;

drop trigger if exists on_like_notify on public.likes;
create trigger on_like_notify
  after insert on public.likes
  for each row execute function public.notify_on_like();

-- A new comment notifies the parent post's owner.
create or replace function public.notify_on_comment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  post_owner uuid;
begin
  select owner into post_owner from public.posts where id = new.post_id;
  if post_owner is not null
     and post_owner <> new.owner
     and not public.is_blocked(new.owner, post_owner) then
    insert into public.notifications (recipient, actor, type, entity_type, entity_id, preview)
    values (post_owner, new.owner, 'reply', 'post', new.post_id, left(new.content, 140));
  end if;
  return null;
end;
$$;

drop trigger if exists on_comment_notify on public.comments;
create trigger on_comment_notify
  after insert on public.comments
  for each row execute function public.notify_on_comment();

-- A new repost notifies the reposted post's owner.
create or replace function public.notify_on_repost()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  post_owner uuid;
begin
  select owner into post_owner from public.posts where id = new.post_id;
  if post_owner is not null
     and post_owner <> new.user_id
     and not public.is_blocked(new.user_id, post_owner) then
    insert into public.notifications (recipient, actor, type, entity_type, entity_id)
    values (post_owner, new.user_id, 'repost', 'post', new.post_id);
  end if;
  return null;
end;
$$;

drop trigger if exists on_repost_notify on public.reposts;
create trigger on_repost_notify
  after insert on public.reposts
  for each row execute function public.notify_on_repost();

-- A new follow notifies the followee. A follow of a private account arrives as
-- 'pending' (a follow_request); a follow of a public account is 'accepted'
-- (a follow).
create or replace function public.notify_on_follow()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.followee is not null
     and new.followee <> new.follower
     and not public.is_blocked(new.follower, new.followee) then
    insert into public.notifications (recipient, actor, type, entity_type, entity_id)
    values (
      new.followee,
      new.follower,
      case when new.status = 'pending' then 'follow_request' else 'follow' end,
      'profile',
      new.follower
    );
  end if;
  return null;
end;
$$;

drop trigger if exists on_follow_notify on public.follows;
create trigger on_follow_notify
  after insert on public.follows
  for each row execute function public.notify_on_follow();

-- ---------------------------------------------------------------------------
-- Indexes for high-frequency queries + keyset-pagination-friendly ordering
-- ---------------------------------------------------------------------------

create index if not exists idx_posts_owner on public.posts (owner);
create index if not exists idx_posts_created_at on public.posts (created_at desc);
-- Composite (created_at desc, id) supports keyset pagination over the feed:
-- `where (created_at, id) < (:last_created_at, :last_id) order by created_at desc, id desc`.
create index if not exists idx_posts_created_at_id on public.posts (created_at desc, id);
create index if not exists idx_comments_post_created on public.comments (post_id, created_at);
create index if not exists idx_likes_post on public.likes (post_id);
create index if not exists idx_reposts_post on public.reposts (post_id);
create index if not exists idx_follows_follower_status on public.follows (follower, status);
create index if not exists idx_follows_followee_status on public.follows (followee, status);
create index if not exists idx_notifications_recipient_created on public.notifications (recipient, created_at desc);
create index if not exists idx_blocks_blocked on public.blocks (blocked);
