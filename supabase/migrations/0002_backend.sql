-- Oneleven backend extension: reposts, replies, bookmarks, notifications,
-- direct messages (conversations + messages), and server-authoritative
-- counters (repost_count, reply_count, followers/following).
--
-- This migration completes the backend for features that were previously
-- mock-only / in-memory in the app (see profile_repository.dart notifications
-- + conversations, and post_repository.dart repost/bookmark notes). Run AFTER
-- 0001_init.sql. It is idempotent (create ... if not exists / drop trigger if
-- exists) and adds no service_role/secret keys; the app uses the public anon
-- key and relies on the RLS policies below.

-- ===========================================================================
-- 1. REPLIES: threaded posts via a self-referencing parent_id
-- ===========================================================================
-- A reply is a normal post that points at its parent. This reuses the whole
-- posts pipeline (RLS, media, counters) instead of a separate table.
alter table public.posts
  add column if not exists parent_id uuid
    references public.posts(id) on delete cascade;

create index if not exists posts_parent_id_idx on public.posts(parent_id);
create index if not exists posts_owner_idx on public.posts(owner);
create index if not exists posts_created_at_idx on public.posts(created_at desc);

-- Server-authoritative reply_count: recompute from count(*) of children on
-- every insert/delete/parent-change, mirroring sync_post_like_count so the
-- counter never drifts under concurrent clients.
create or replace function public.sync_post_reply_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  affected uuid;
begin
  -- Recompute for both the old and new parent (handles inserts, deletes, and
  -- re-parenting) so every touched parent's count stays correct.
  for affected in
    select unnest(array[old.parent_id, new.parent_id])
  loop
    if affected is not null then
      update public.posts
        set reply_count = (
          select count(*) from public.posts where parent_id = affected
        )
        where id = affected;
    end if;
  end loop;
  return null;
end;
$$;

drop trigger if exists on_reply_change on public.posts;
create trigger on_reply_change
  after insert or delete or update of parent_id on public.posts
  for each row execute function public.sync_post_reply_count();

-- ===========================================================================
-- 2. REPOSTS: first-class join table + server-authoritative repost_count
-- ===========================================================================
-- Replaces the client-authoritative repost_count write documented as a known
-- limitation in post_repository.dart (_persistRepostCount). With this table +
-- trigger the count is owned by the DB, exactly like likes.
create table if not exists public.reposts (
  user_id uuid references auth.users(id) on delete cascade,
  post_id uuid references public.posts(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, post_id)
);

alter table public.reposts enable row level security;

create policy "reposts_select_authenticated"
  on public.reposts for select to authenticated
  using (true);

create policy "reposts_insert_own"
  on public.reposts for insert to authenticated
  with check (auth.uid() = user_id);

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

-- ===========================================================================
-- 3. BOOKMARKS: private per-user saved posts
-- ===========================================================================
-- Backs Post.bookmarked, which was local-only. Unlike likes/reposts these are
-- PRIVATE: a user may only see their own bookmarks (select is owner-scoped).
create table if not exists public.bookmarks (
  user_id uuid references auth.users(id) on delete cascade,
  post_id uuid references public.posts(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, post_id)
);

alter table public.bookmarks enable row level security;

create policy "bookmarks_select_own"
  on public.bookmarks for select to authenticated
  using (auth.uid() = user_id);

create policy "bookmarks_insert_own"
  on public.bookmarks for insert to authenticated
  with check (auth.uid() = user_id);

create policy "bookmarks_delete_own"
  on public.bookmarks for delete to authenticated
  using (auth.uid() = user_id);

-- ===========================================================================
-- 4. FOLLOWERS / FOLLOWING counters (server-authoritative)
-- ===========================================================================
-- profiles.followers / profiles.following were static columns. Keep them in
-- sync from the follows table via a trigger, recomputing with count(*) so they
-- stay correct under concurrent follow/unfollow.
create or replace function public.sync_follow_counts()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  the_follower uuid := coalesce(new.follower, old.follower);
  the_followee uuid := coalesce(new.followee, old.followee);
begin
  -- followee gained/lost a follower
  update public.profiles
    set followers = (select count(*) from public.follows where followee = the_followee)
    where id = the_followee;
  -- follower changed how many people they follow
  update public.profiles
    set following = (select count(*) from public.follows where follower = the_follower)
    where id = the_follower;
  return null;
end;
$$;

drop trigger if exists on_follow_change on public.follows;
create trigger on_follow_change
  after insert or delete on public.follows
  for each row execute function public.sync_follow_counts();

-- ===========================================================================
-- 5. NOTIFICATIONS
-- ===========================================================================
-- Backs profile_repository.notifications() (previously mock-only). Matches the
-- NotificationType enum in notification_item.dart: like, reply, repost,
-- follow, mention.
do $$
begin
  if not exists (select 1 from pg_type where typname = 'notification_type') then
    create type public.notification_type as enum
      ('like', 'reply', 'repost', 'follow', 'mention');
  end if;
end$$;

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  -- who receives this notification
  recipient uuid not null references auth.users(id) on delete cascade,
  -- who performed the action
  actor uuid not null references auth.users(id) on delete cascade,
  type public.notification_type not null,
  -- optional related post (for like/reply/repost/mention)
  post_id uuid references public.posts(id) on delete cascade,
  -- optional preview text (e.g. the post content that was acted on)
  preview text,
  read boolean not null default false,
  created_at timestamptz default now()
);

create index if not exists notifications_recipient_idx
  on public.notifications(recipient, created_at desc);

alter table public.notifications enable row level security;

-- A user sees only notifications addressed to them.
create policy "notifications_select_own"
  on public.notifications for select to authenticated
  using (auth.uid() = recipient);

-- The actor creates the notification (e.g. when they like/follow). They must
-- be the acting user, and cannot notify themselves.
create policy "notifications_insert_as_actor"
  on public.notifications for insert to authenticated
  with check (auth.uid() = actor and actor <> recipient);

-- The recipient may update their own notifications (mark as read).
create policy "notifications_update_own"
  on public.notifications for update to authenticated
  using (auth.uid() = recipient)
  with check (auth.uid() = recipient);

create policy "notifications_delete_own"
  on public.notifications for delete to authenticated
  using (auth.uid() = recipient);

-- ===========================================================================
-- 6. DIRECT MESSAGES: conversations + participants + messages
-- ===========================================================================
-- Backs profile_repository.conversations() and conversation_screen.dart
-- (previously mock-only). Modeled as a general thread with a participants
-- join table (supports 1:1 today, groups later). Message.fromMe in the app is
-- derived client-side by comparing sender to the current user.

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  last_preview text default '',
  updated_at timestamptz default now(),
  created_at timestamptz default now()
);

create table if not exists public.conversation_participants (
  conversation_id uuid references public.conversations(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  -- per-participant unread counter, maintained by trigger below
  unread int not null default 0,
  joined_at timestamptz default now(),
  primary key (conversation_id, user_id)
);

create index if not exists conversation_participants_user_idx
  on public.conversation_participants(user_id);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender uuid not null references auth.users(id) on delete cascade,
  text text not null,
  sent_at timestamptz default now()
);

create index if not exists messages_conversation_idx
  on public.messages(conversation_id, sent_at);

alter table public.conversations enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.messages enable row level security;

-- Helper: is the current user a participant of a given conversation? Used by
-- the policies below. SECURITY DEFINER so the membership check itself is not
-- gated by conversation_participants' own RLS (which would recurse).
create or replace function public.is_conversation_participant(conv uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.conversation_participants
    where conversation_id = conv and user_id = auth.uid()
  );
$$;

-- conversations: visible only to their participants.
create policy "conversations_select_participant"
  on public.conversations for select to authenticated
  using (public.is_conversation_participant(id));

-- Any authenticated user may create a conversation shell; they then add
-- participants (including themselves) in conversation_participants.
create policy "conversations_insert_authenticated"
  on public.conversations for insert to authenticated
  with check (true);

create policy "conversations_update_participant"
  on public.conversations for update to authenticated
  using (public.is_conversation_participant(id))
  with check (public.is_conversation_participant(id));

-- participants: a row is visible if the viewer is a participant of that
-- conversation (so both sides can see who is in the thread).
create policy "participants_select_member"
  on public.conversation_participants for select to authenticated
  using (public.is_conversation_participant(conversation_id));

-- A user may add themselves, or add others to a conversation they belong to.
create policy "participants_insert_self_or_member"
  on public.conversation_participants for insert to authenticated
  with check (
    auth.uid() = user_id
    or public.is_conversation_participant(conversation_id)
  );

-- A participant may update their own row (e.g. reset their unread counter).
create policy "participants_update_own"
  on public.conversation_participants for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "participants_delete_own"
  on public.conversation_participants for delete to authenticated
  using (auth.uid() = user_id);

-- messages: visible to participants of the conversation.
create policy "messages_select_participant"
  on public.messages for select to authenticated
  using (public.is_conversation_participant(conversation_id));

-- Only a participant may send, and only as themselves.
create policy "messages_insert_participant"
  on public.messages for insert to authenticated
  with check (
    auth.uid() = sender
    and public.is_conversation_participant(conversation_id)
  );

create policy "messages_delete_own"
  on public.messages for delete to authenticated
  using (auth.uid() = sender);

-- On a new message: bump the conversation's preview/updated_at and increment
-- unread for every participant except the sender. Keeps
-- Conversation.lastPreview / updatedAt / unread server-authoritative.
create or replace function public.handle_new_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversations
    set last_preview = new.text,
        updated_at = new.sent_at
    where id = new.conversation_id;

  update public.conversation_participants
    set unread = unread + 1
    where conversation_id = new.conversation_id
      and user_id <> new.sender;

  return null;
end;
$$;

drop trigger if exists on_message_created on public.messages;
create trigger on_message_created
  after insert on public.messages
  for each row execute function public.handle_new_message();
