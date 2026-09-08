-- Oneleven FEAT-001: add foreign keys from user-referencing columns to
-- public.profiles(id) so PostgREST can embed the author/actor/participant
-- profile (e.g. posts.select('*, profiles(*)')). The columns already reference
-- auth.users(id); profiles.id == auth.users.id (1:1, populated by the
-- handle_new_user trigger), so these added FKs are always satisfiable.
-- Idempotent: guard each add with a catalog check. Run AFTER 0005.

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'posts_owner_profile_fkey'
  ) then
    alter table public.posts
      add constraint posts_owner_profile_fkey
      foreign key (owner) references public.profiles(id) on delete cascade;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'notifications_actor_profile_fkey'
  ) then
    alter table public.notifications
      add constraint notifications_actor_profile_fkey
      foreign key (actor) references public.profiles(id) on delete cascade;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'conversation_participants_user_profile_fkey'
  ) then
    alter table public.conversation_participants
      add constraint conversation_participants_user_profile_fkey
      foreign key (user_id) references public.profiles(id) on delete cascade;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'messages_sender_profile_fkey'
  ) then
    alter table public.messages
      add constraint messages_sender_profile_fkey
      foreign key (sender) references public.profiles(id) on delete cascade;
  end if;
end$$;
