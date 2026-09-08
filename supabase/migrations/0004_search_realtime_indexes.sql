-- Oneleven FEAT-001: search RPCs, realtime publication membership, and
-- FK-covering indexes. Idempotent. Run AFTER 0003_harden_functions.sql.

-- ===========================================================================
-- 1. Trigram extension for case-insensitive substring search
-- ===========================================================================
-- Installed into the dedicated extensions schema (Supabase convention) rather
-- than public, so it never clutters the app's namespace.
create extension if not exists pg_trgm with schema extensions;

-- ===========================================================================
-- 2. Search indexes
-- ===========================================================================
-- GIN trigram indexes back case-insensitive substring/handle search on
-- profiles, and hashtag/text search on posts. Expression indexes on lower()
-- keep the search case-insensitive.
create index if not exists profiles_username_trgm_idx
  on public.profiles using gin (lower(username) extensions.gin_trgm_ops);

create index if not exists profiles_display_name_trgm_idx
  on public.profiles using gin (lower(display_name) extensions.gin_trgm_ops);

create index if not exists posts_content_trgm_idx
  on public.posts using gin (lower(content) extensions.gin_trgm_ops);

-- ===========================================================================
-- 3. FK-covering indexes (flagged by the performance advisor)
-- ===========================================================================
-- likes/reposts/bookmarks are keyed (user_id, post_id); the leading-column
-- pkey does not cover lookups/cascades by post_id. follows likewise needs a
-- followee index (pkey leads with follower).
create index if not exists likes_post_id_idx on public.likes(post_id);
create index if not exists reposts_post_id_idx on public.reposts(post_id);
create index if not exists bookmarks_post_id_idx on public.bookmarks(post_id);
create index if not exists follows_followee_idx on public.follows(followee);
create index if not exists messages_sender_idx on public.messages(sender);
create index if not exists notifications_actor_idx on public.notifications(actor);
create index if not exists notifications_post_id_idx on public.notifications(post_id);

-- ===========================================================================
-- 4. Search RPCs
-- ===========================================================================
-- SECURITY INVOKER so the caller's RLS applies (profiles/posts are readable by
-- any authenticated user). Fixed search_path per hardening convention.
-- Returns whole rows so PostgREST maps them to the same shape the app already
-- consumes from a plain select.
create or replace function public.search_profiles(q text)
returns setof public.profiles
language sql
security invoker
stable
set search_path = ''
as $$
  select p.*
  from public.profiles p
  where q <> ''
    and (
      lower(p.username) like '%' || lower(q) || '%'
      or lower(p.display_name) like '%' || lower(q) || '%'
    )
  order by
    (lower(p.username) = lower(q)) desc,
    p.followers desc
  limit 50;
$$;

create or replace function public.search_posts(q text)
returns setof public.posts
language sql
security invoker
stable
set search_path = ''
as $$
  select p.*
  from public.posts p
  where q <> ''
    and p.parent_id is null
    and lower(p.content) like '%' || lower(q) || '%'
  order by p.created_at desc
  limit 50;
$$;

-- ===========================================================================
-- 5. Realtime publication membership
-- ===========================================================================
-- Add the live-updating tables to the supabase_realtime publication so the
-- client can subscribe to feed/message/notification changes. Guarded so
-- re-running does not error if a table is already a member.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'posts'
  ) then
    alter publication supabase_realtime add table public.posts;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'conversations'
  ) then
    alter publication supabase_realtime add table public.conversations;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public' and tablename = 'conversation_participants'
  ) then
    alter publication supabase_realtime add table public.conversation_participants;
  end if;
end$$;

-- Keep the search RPCs off the anon role's ad-hoc surface is unnecessary here:
-- they are SECURITY INVOKER and rely on RLS, so leaving EXECUTE to
-- authenticated is correct. Revoke from anon to avoid unauthenticated probing.
revoke execute on function public.search_profiles(text) from anon;
revoke execute on function public.search_posts(text) from anon;
grant execute on function public.search_profiles(text) to authenticated;
grant execute on function public.search_posts(text) to authenticated;
