-- Oneleven comment-likes migration (0008).
-- Run this in the Supabase SQL editor AFTER 0001..0007 have been applied.
-- Contains no service_role/secret keys; the app authenticates with the public
-- anon (publishable) key and relies on the RLS policies below.
--
-- PURPOSE (Phase 3, slice 4 — FEAT-011): make COMMENT LIKES first-class,
-- mirroring the post-like design. It adds:
--   * public.comment_likes            — the like join table, one row per
--                                       (user_id, comment_id)
--   * public.sync_comment_like_count() — a SECURITY DEFINER trigger that keeps
--                                       comments.like_count server-owned,
--                                       recomputed from count(*) over
--                                       comment_likes (mirrors 0001's
--                                       sync_post_like_count)
--   * public.notify_on_comment_like()  — notifies the liked comment's author
--                                       (guarded against self-notify + blocks),
--                                       mirroring notify_on_like in 0002
--   * idx_comment_likes_comment        — index on (comment_id) for the count
--                                       recompute + "who liked this comment"
--
-- NOTIFY DECISION: a notify_on_comment_like trigger IS included below for
-- parity with the like/reply/repost/follow notifiers in 0002. The centralized
-- notifications.type check constraint (0002) does not include a
-- 'comment_like' value, so the notification is emitted with type 'like' and
-- entity_type 'comment' — this reuses the allowed enum value while the
-- entity_type disambiguates a comment like from a post like for any consumer.
-- No 0001-0007 file is edited (that constraint stays as-is).
--
-- ENV RISK (UNVERIFIED live): this migration was authored and reviewed
-- STRUCTURALLY ONLY. There is no reachable/administerable Supabase project and
-- no service-role credential in this environment, so the RLS visibility, the
-- SECURITY DEFINER count trigger, and the notify trigger have NOT been executed
-- end-to-end. Their live behavior (policy evaluation, trigger firing order,
-- notification production) is the largest known risk and must be verified
-- against a real project before relying on it.
--
-- Everything is idempotent (create table if not exists / drop policy if exists
-- / create or replace / drop trigger if exists / create index if not exists).

-- ---------------------------------------------------------------------------
-- comment_likes (join table)
-- ---------------------------------------------------------------------------

create table if not exists public.comment_likes (
  user_id uuid references auth.users(id) on delete cascade,
  comment_id uuid references public.comments(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, comment_id)
);

alter table public.comment_likes enable row level security;

-- comment_likes: visibility INHERITS the underlying comment's post-author
-- visibility, mirroring comments_select_viewable (0002) — a like row is
-- readable only when the viewer can see the comment's post owner (join through
-- comments -> posts + can_view_profile). Only the acting user may create/remove
-- their own like.
drop policy if exists "comment_likes_select_viewable" on public.comment_likes;
create policy "comment_likes_select_viewable"
  on public.comment_likes for select to authenticated
  using (
    exists (
      select 1
      from public.comments c
      join public.posts p on p.id = c.post_id
      where c.id = comment_likes.comment_id
        and public.can_view_profile(auth.uid(), p.owner)
    )
  );

drop policy if exists "comment_likes_insert_own" on public.comment_likes;
create policy "comment_likes_insert_own"
  on public.comment_likes for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "comment_likes_delete_own" on public.comment_likes;
create policy "comment_likes_delete_own"
  on public.comment_likes for delete to authenticated
  using (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Server-authoritative comments.like_count (mirrors sync_post_like_count)
-- ---------------------------------------------------------------------------
--
-- Like `posts.like_count`, `comments.like_count` is a denormalized counter
-- owned by the database, not the client. The client performs only
-- fire-and-forget insert/delete on `comment_likes` and never writes
-- `comments.like_count` itself (see comment_repository.dart). Recomputing with
-- count(*) (rather than +/- 1) makes this idempotent: a duplicate insert
-- (already-liked) or a no-op delete leaves the count correct.
create or replace function public.sync_comment_like_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_comment uuid := coalesce(new.comment_id, old.comment_id);
begin
  update public.comments
    set like_count = (
      select count(*) from public.comment_likes where comment_id = target_comment
    )
    where id = target_comment;
  return null;
end;
$$;

drop trigger if exists on_comment_like_change on public.comment_likes;
create trigger on_comment_like_change
  after insert or delete on public.comment_likes
  for each row execute function public.sync_comment_like_count();

-- ---------------------------------------------------------------------------
-- Notification producer: a new comment-like notifies the comment's author
-- ---------------------------------------------------------------------------
--
-- Mirrors notify_on_like (0002): guarded against self-notification
-- (actor <> comment owner) and against blocked pairs (is_blocked). The
-- notifications.type check (0002) has no 'comment_like' value, so the row is
-- emitted with type 'like' + entity_type 'comment' (entity_id = the comment
-- id) — the entity_type distinguishes it from a post like for consumers.
create or replace function public.notify_on_comment_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  comment_owner uuid;
begin
  select owner into comment_owner from public.comments where id = new.comment_id;
  if comment_owner is not null
     and comment_owner <> new.user_id
     and not public.is_blocked(new.user_id, comment_owner) then
    insert into public.notifications (recipient, actor, type, entity_type, entity_id)
    values (comment_owner, new.user_id, 'like', 'comment', new.comment_id);
  end if;
  return null;
end;
$$;

drop trigger if exists on_comment_like_notify on public.comment_likes;
create trigger on_comment_like_notify
  after insert on public.comment_likes
  for each row execute function public.notify_on_comment_like();

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

-- Supports the count recompute in sync_comment_like_count and a future
-- "who liked this comment" lookup. The primary key already covers
-- (user_id, comment_id) for the "did I like it" check.
create index if not exists idx_comment_likes_comment
  on public.comment_likes (comment_id);
