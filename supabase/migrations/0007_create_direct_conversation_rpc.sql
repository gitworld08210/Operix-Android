-- Oneleven review fix (v1 semantic round): atomic find-or-create for a 1:1
-- direct conversation. Run AFTER 0006_profile_embed_fkeys.sql.
--
-- Why this exists:
-- The client previously created a conversation by inserting BOTH
-- conversation_participants rows in a single multi-row INSERT. The RLS insert
-- policy participants_insert_self_or_member is
--   (auth.uid() = user_id) OR is_conversation_participant(conversation_id)
-- and is_conversation_participant(conv) is
--   exists (select 1 from conversation_participants
--           where conversation_id = conv and user_id = auth.uid())
-- Within one multi-row INSERT the caller's own (not-yet-visible) sibling row is
-- not seen by that EXISTS subquery, so the OTHER user's row fails both branches
-- and the whole statement is rejected. Splitting into two sequential inserts
-- would work, but leaves a window where a half-created conversation can exist
-- if the second insert fails. This SECURITY DEFINER RPC does the whole thing
-- (find-or-create + both participant rows) atomically in one transaction.
--
-- Conventions (match 0004): fixed empty search_path, granted to authenticated,
-- revoked from public/anon so only signed-in callers can invoke it.

create or replace function public.create_direct_conversation(other_user uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  me uuid := auth.uid();
  conv uuid;
begin
  if me is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  if other_user is null or other_user = me then
    raise exception 'invalid target user' using errcode = '22023';
  end if;

  -- Reuse an existing 1:1 conversation that has exactly these two members.
  select cp_me.conversation_id
    into conv
  from public.conversation_participants cp_me
  join public.conversation_participants cp_other
    on cp_other.conversation_id = cp_me.conversation_id
   and cp_other.user_id = other_user
  where cp_me.user_id = me
    and (
      select count(*) from public.conversation_participants cp_all
      where cp_all.conversation_id = cp_me.conversation_id
    ) = 2
  limit 1;

  if conv is not null then
    return conv;
  end if;

  insert into public.conversations default values returning id into conv;
  insert into public.conversation_participants (conversation_id, user_id)
  values (conv, me), (conv, other_user);

  return conv;
end;
$$;

-- PostgreSQL grants EXECUTE to PUBLIC by default; revoke that (and anon) so the
-- SECURITY DEFINER function is only reachable by signed-in users, then grant to
-- authenticated. This clears the anon "Public Can Execute SECURITY DEFINER
-- Function" advisor; the remaining authenticated advisor is expected and
-- intended (signed-in users are precisely who may start a DM), matching the
-- accepted status of the existing is_conversation_participant helper.
revoke execute on function public.create_direct_conversation(uuid) from public;
revoke execute on function public.create_direct_conversation(uuid) from anon;
grant execute on function public.create_direct_conversation(uuid) to authenticated;
