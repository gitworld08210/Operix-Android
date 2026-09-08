-- ---------------------------------------------------------------------------
-- 0003_follow_accept_notification.sql
--
-- Closes the acceptance-notification gap called out in the Phase 1 review:
-- `notify_on_follow` (migration 0002) fires only `after insert`, so when a
-- private-account follow request is later accepted by flipping
-- `follows.status` from 'pending' -> 'accepted' (an UPDATE), the follower never
-- receives a 'follow' notification signalling that the request was accepted.
--
-- This migration adds an `after update` producer that emits exactly one
-- 'follow' notification to the ORIGINAL REQUESTER (the follower) on the
-- pending -> accepted transition, and only on that transition. It mirrors the
-- guards and style of the 0002 notification producers:
--   * SECURITY DEFINER + `set search_path = public` (bypasses the no-insert RLS
--     on notifications, exactly like the other producers);
--   * self-notification guard (follower <> followee);
--   * blocked-pair suppression via public.is_blocked;
--   * fires only when status actually changes to 'accepted' from 'pending', so
--     it is idempotent under no-op updates and never double-notifies.
--
-- Note the RECIPIENT here is the follower (the person whose request was just
-- accepted), which is the inverse of the insert-time producer whose recipient
-- is the followee. It is additive and does not touch migration 0001 or 0002.
-- ---------------------------------------------------------------------------

create or replace function public.notify_on_follow_accepted()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'accepted'
     and old.status is distinct from 'accepted'
     and new.follower is not null
     and new.followee <> new.follower
     and not public.is_blocked(new.follower, new.followee) then
    -- Recipient is the follower: their pending request to `followee` was
    -- accepted. Actor is the followee who accepted it.
    insert into public.notifications (recipient, actor, type, entity_type, entity_id)
    values (
      new.follower,
      new.followee,
      'follow',
      'profile',
      new.followee
    );
  end if;
  return null;
end;
$$;

drop trigger if exists on_follow_accept_notify on public.follows;
create trigger on_follow_accept_notify
  after update of status on public.follows
  for each row execute function public.notify_on_follow_accepted();
