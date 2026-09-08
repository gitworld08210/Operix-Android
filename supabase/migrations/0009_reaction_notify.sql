-- Oneleven reaction-notification migration (0009).
-- Run this in the Supabase SQL editor AFTER 0001..0008 have been applied.
-- Contains no service_role/secret keys; the app authenticates with the public
-- anon (publishable) key and relies on the RLS policies from the prior files.
--
-- PURPOSE (Phase 3 review v1, issue 4): CLOSE the "like" notification gap left
-- by the migrate-like-into-reactions decision (0007). Since the client now
-- writes likes/reactions ONLY to public.reactions, the 0002 notify_on_like
-- trigger — which fires on public.likes inserts — never runs on the going-
-- forward path, so a like made via a reaction produced NO notification. This
-- migration adds a notify-on-react trigger on public.reactions that mirrors
-- notify_on_like exactly for type='like', restoring like notifications on the
-- reaction path.
--
-- SCOPE: only type='like' produces a notification, matching the pre-Phase-3
-- behavior (a single like notification). The other five affect types
-- (love/laugh/wow/sad/angry) are deliberately NOT notified here — the
-- notifications.type check constraint (0002) has no per-affect value, and a
-- richer "reacted to your post" notification is a later-phase concern. This is
-- a deliberate, documented boundary, not an omission.
--
-- GUARDS (identical to notify_on_like / notify_on_comment_like):
--   * self-notification guard: the post owner is never notified about their
--     own reaction (post_owner <> new.user_id);
--   * blocked-pair suppression via public.is_blocked (either direction);
--   * fires only when the reaction is (or becomes) a 'like', so switching AWAY
--     from like, or a non-like reaction, emits nothing.
--   * the row is emitted with type 'like' + entity_type 'post' (entity_id =
--     the post id) — byte-identical to notify_on_like's payload — so existing
--     notification consumers treat a reaction-path like exactly like a legacy
--     like with no client change.
--
-- Idempotency: re-runnable. Uses `create or replace function` and
-- `drop trigger if exists` before create.
--
-- ENV RISK: UNVERIFIED against a live Supabase project (no reachable/
-- administerable instance, no service-role key in this environment) — this has
-- had STRUCTURAL REVIEW ONLY. The trigger firing conditions, the self-notify /
-- is_blocked guards, and the notifications insert must be validated on a real
-- project. Because it is additive (a new trigger on public.reactions) and
-- reuses the frozen notifications payload shape, its blast radius is small.

-- A new (or switched-to) 'like' reaction notifies the reacted post's owner.
-- Guarded against self-notification (post_owner <> actor) and blocked pairs.
create or replace function public.notify_on_reaction_like()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  post_owner uuid;
begin
  -- Only a 'like' reaction produces a notification (see scope note above).
  -- On UPDATE this covers a switch TO like; a switch away from like (old was
  -- like, new is not) emits nothing.
  if new.type <> 'like' then
    return null;
  end if;
  -- On UPDATE, do not re-notify when the reaction was ALREADY a like (e.g. a
  -- no-op upsert), only when it becomes a like.
  if tg_op = 'UPDATE' and old.type = 'like' then
    return null;
  end if;

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

-- Fires on insert (a fresh like) and on update (a reaction switched TO like).
-- The count-sync trigger (on_reaction_change, 0007) is a separate trigger on
-- the same table; both fire independently.
drop trigger if exists on_reaction_like_notify on public.reactions;
create trigger on_reaction_like_notify
  after insert or update on public.reactions
  for each row execute function public.notify_on_reaction_like();
