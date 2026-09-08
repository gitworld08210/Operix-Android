-- Oneleven FEAT-001 follow-up: address performance advisors.
--   (a) unindexed_foreign_keys: add covering index for reels.owner
--   (b) auth_rls_initplan: wrap auth.uid() in (select auth.uid()) across all
--       policies so it is evaluated once per statement, not once per row.
-- Idempotent: drop policy if exists + recreate. Run AFTER 0004.

-- (a) reels.owner covering index -------------------------------------------
create index if not exists reels_owner_idx on public.reels(owner);

-- (b) RLS initplan optimization --------------------------------------------
-- profiles
drop policy if exists "profiles_insert_own" on public.profiles;
create policy "profiles_insert_own"
  on public.profiles for insert to authenticated
  with check ((select auth.uid()) = id);

drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- posts
drop policy if exists "posts_insert_own" on public.posts;
create policy "posts_insert_own"
  on public.posts for insert to authenticated
  with check ((select auth.uid()) = owner);

drop policy if exists "posts_update_own" on public.posts;
create policy "posts_update_own"
  on public.posts for update to authenticated
  using ((select auth.uid()) = owner)
  with check ((select auth.uid()) = owner);

drop policy if exists "posts_delete_own" on public.posts;
create policy "posts_delete_own"
  on public.posts for delete to authenticated
  using ((select auth.uid()) = owner);

-- reels
drop policy if exists "reels_insert_own" on public.reels;
create policy "reels_insert_own"
  on public.reels for insert to authenticated
  with check ((select auth.uid()) = owner);

drop policy if exists "reels_update_own" on public.reels;
create policy "reels_update_own"
  on public.reels for update to authenticated
  using ((select auth.uid()) = owner)
  with check ((select auth.uid()) = owner);

drop policy if exists "reels_delete_own" on public.reels;
create policy "reels_delete_own"
  on public.reels for delete to authenticated
  using ((select auth.uid()) = owner);

-- likes
drop policy if exists "likes_insert_own" on public.likes;
create policy "likes_insert_own"
  on public.likes for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "likes_delete_own" on public.likes;
create policy "likes_delete_own"
  on public.likes for delete to authenticated
  using ((select auth.uid()) = user_id);

-- follows
drop policy if exists "follows_insert_own" on public.follows;
create policy "follows_insert_own"
  on public.follows for insert to authenticated
  with check ((select auth.uid()) = follower);

drop policy if exists "follows_delete_own" on public.follows;
create policy "follows_delete_own"
  on public.follows for delete to authenticated
  using ((select auth.uid()) = follower);

-- reposts
drop policy if exists "reposts_insert_own" on public.reposts;
create policy "reposts_insert_own"
  on public.reposts for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "reposts_delete_own" on public.reposts;
create policy "reposts_delete_own"
  on public.reposts for delete to authenticated
  using ((select auth.uid()) = user_id);

-- bookmarks
drop policy if exists "bookmarks_select_own" on public.bookmarks;
create policy "bookmarks_select_own"
  on public.bookmarks for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "bookmarks_insert_own" on public.bookmarks;
create policy "bookmarks_insert_own"
  on public.bookmarks for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "bookmarks_delete_own" on public.bookmarks;
create policy "bookmarks_delete_own"
  on public.bookmarks for delete to authenticated
  using ((select auth.uid()) = user_id);

-- notifications
drop policy if exists "notifications_select_own" on public.notifications;
create policy "notifications_select_own"
  on public.notifications for select to authenticated
  using ((select auth.uid()) = recipient);

drop policy if exists "notifications_insert_as_actor" on public.notifications;
create policy "notifications_insert_as_actor"
  on public.notifications for insert to authenticated
  with check ((select auth.uid()) = actor and actor <> recipient);

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own"
  on public.notifications for update to authenticated
  using ((select auth.uid()) = recipient)
  with check ((select auth.uid()) = recipient);

drop policy if exists "notifications_delete_own" on public.notifications;
create policy "notifications_delete_own"
  on public.notifications for delete to authenticated
  using ((select auth.uid()) = recipient);

-- conversation_participants
drop policy if exists "participants_insert_self_or_member" on public.conversation_participants;
create policy "participants_insert_self_or_member"
  on public.conversation_participants for insert to authenticated
  with check (
    (select auth.uid()) = user_id
    or public.is_conversation_participant(conversation_id)
  );

drop policy if exists "participants_update_own" on public.conversation_participants;
create policy "participants_update_own"
  on public.conversation_participants for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "participants_delete_own" on public.conversation_participants;
create policy "participants_delete_own"
  on public.conversation_participants for delete to authenticated
  using ((select auth.uid()) = user_id);

-- messages
drop policy if exists "messages_insert_participant" on public.messages;
create policy "messages_insert_participant"
  on public.messages for insert to authenticated
  with check (
    (select auth.uid()) = sender
    and public.is_conversation_participant(conversation_id)
  );

drop policy if exists "messages_delete_own" on public.messages;
create policy "messages_delete_own"
  on public.messages for delete to authenticated
  using ((select auth.uid()) = sender);
