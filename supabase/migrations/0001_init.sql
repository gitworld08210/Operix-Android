-- Oneleven initial schema, RLS, new-user trigger, and storage buckets.
-- Run this in the Supabase SQL editor before first app launch.
-- Contains no service_role/secret keys; the app authenticates with the
-- public anon (publishable) key and relies on the policies below.

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique,
  display_name text,
  bio text default '',
  avatar_url text,
  banner_url text,
  verified boolean default false,
  verification_kind text default 'verified',
  followers int default 0,
  following int default 0,
  created_at timestamptz default now()
);

create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  owner uuid references auth.users(id) on delete cascade,
  content text not null,
  media_url text,
  media_type text default 'none',
  reply_count int default 0,
  repost_count int default 0,
  like_count int default 0,
  view_count int default 0,
  created_at timestamptz default now()
);

create table if not exists public.reels (
  id uuid primary key default gen_random_uuid(),
  owner uuid references auth.users(id) on delete cascade,
  video_url text not null,
  thumb_url text,
  caption text default '',
  like_count int default 0,
  view_count int default 0,
  created_at timestamptz default now()
);

create table if not exists public.likes (
  user_id uuid references auth.users(id) on delete cascade,
  post_id uuid references public.posts(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, post_id)
);

create table if not exists public.follows (
  follower uuid references auth.users(id) on delete cascade,
  followee uuid references auth.users(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (follower, followee)
);

-- ---------------------------------------------------------------------------
-- Row Level Security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.posts    enable row level security;
alter table public.reels    enable row level security;
alter table public.likes    enable row level security;
alter table public.follows  enable row level security;

-- profiles: readable by any authenticated user; only the owner may write.
create policy "profiles_select_authenticated"
  on public.profiles for select to authenticated
  using (true);

create policy "profiles_insert_own"
  on public.profiles for insert to authenticated
  with check (auth.uid() = id);

create policy "profiles_update_own"
  on public.profiles for update to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- posts: readable by any authenticated user; only the owner may write.
create policy "posts_select_authenticated"
  on public.posts for select to authenticated
  using (true);

create policy "posts_insert_own"
  on public.posts for insert to authenticated
  with check (auth.uid() = owner);

create policy "posts_update_own"
  on public.posts for update to authenticated
  using (auth.uid() = owner)
  with check (auth.uid() = owner);

create policy "posts_delete_own"
  on public.posts for delete to authenticated
  using (auth.uid() = owner);

-- reels: readable by any authenticated user; only the owner may write.
create policy "reels_select_authenticated"
  on public.reels for select to authenticated
  using (true);

create policy "reels_insert_own"
  on public.reels for insert to authenticated
  with check (auth.uid() = owner);

create policy "reels_update_own"
  on public.reels for update to authenticated
  using (auth.uid() = owner)
  with check (auth.uid() = owner);

create policy "reels_delete_own"
  on public.reels for delete to authenticated
  using (auth.uid() = owner);

-- likes: readable by any authenticated user; only the acting user may write.
create policy "likes_select_authenticated"
  on public.likes for select to authenticated
  using (true);

create policy "likes_insert_own"
  on public.likes for insert to authenticated
  with check (auth.uid() = user_id);

create policy "likes_delete_own"
  on public.likes for delete to authenticated
  using (auth.uid() = user_id);

-- follows: readable by any authenticated user; only the follower may write.
create policy "follows_select_authenticated"
  on public.follows for select to authenticated
  using (true);

create policy "follows_insert_own"
  on public.follows for insert to authenticated
  with check (auth.uid() = follower);

create policy "follows_delete_own"
  on public.follows for delete to authenticated
  using (auth.uid() = follower);

-- ---------------------------------------------------------------------------
-- Auto-create a profile row whenever a new auth user is created
-- ---------------------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  base_username text := split_part(new.email, '@', 1);
  candidate text := base_username;
begin
  -- Two users can share an email local-part (alice@a.com / alice@b.com), which
  -- would collide on the `username unique` constraint and abort the auth-user
  -- insert. Suffix the id's leading hex until the username is free so profile
  -- creation never fails on a username clash.
  if exists (select 1 from public.profiles where username = candidate) then
    candidate := base_username || '_' || substr(replace(new.id::text, '-', ''), 1, 6);
  end if;
  insert into public.profiles (id, username, display_name)
  values (new.id, candidate, base_username)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Server-authoritative like_count
-- ---------------------------------------------------------------------------
--
-- `posts.like_count` is a denormalized counter. It MUST be owned by the
-- database, not the client: two clients toggling a like concurrently would
-- each write their own optimistic count and the last writer would win,
-- permanently drifting from the true `count(*)` over `likes`. To avoid that,
-- this trigger recomputes `like_count` from the `likes` join table on every
-- insert/delete, so the counter always reflects the real like set regardless
-- of how many clients are acting at once.
--
-- The client therefore performs only fire-and-forget insert/delete on `likes`
-- and never writes `posts.like_count` itself (see post_repository.dart).
-- Recomputing with count(*) (rather than +/- 1) makes this idempotent: a
-- duplicate insert (already-liked) or a no-op delete leaves the count correct.
create or replace function public.sync_post_like_count()
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
      select count(*) from public.likes where post_id = target_post
    )
    where id = target_post;
  return null;
end;
$$;

drop trigger if exists on_like_change on public.likes;
create trigger on_like_change
  after insert or delete on public.likes
  for each row execute function public.sync_post_like_count();

-- ---------------------------------------------------------------------------
-- Storage buckets + policies (reels videos, profile avatars)
-- ---------------------------------------------------------------------------

-- Both buckets are intentionally PUBLIC. The app loads media with plain
-- URL fetches: Image.network(avatar_url) and video players over
-- reels.video_url, using the URLs returned by getPublicUrl(). Public buckets
-- serve those objects over the CDN path without a session, which is exactly
-- what the UI needs and avoids per-request signed-URL minting.
--
-- Because the buckets are public, we deliberately DO NOT add an
-- "authenticated-only SELECT" policy on storage.objects: such a policy would
-- be silently bypassed by the public CDN path for URL reads and would only
-- create a false impression that reads are gated. Read access is public by
-- design; only writes are owner-scoped (policies below). If a future version
-- needs private media, flip `public` to false here and switch the client to
-- createSignedUrl() instead of getPublicUrl().
insert into storage.buckets (id, name, public)
values ('reels', 'reels', true), ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Only the object owner can create/update/delete their objects.
create policy "storage_insert_own"
  on storage.objects for insert to authenticated
  with check (bucket_id in ('reels', 'avatars') and auth.uid() = owner);

create policy "storage_update_own"
  on storage.objects for update to authenticated
  using (bucket_id in ('reels', 'avatars') and auth.uid() = owner)
  with check (bucket_id in ('reels', 'avatars') and auth.uid() = owner);

create policy "storage_delete_own"
  on storage.objects for delete to authenticated
  using (bucket_id in ('reels', 'avatars') and auth.uid() = owner);
