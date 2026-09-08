-- Security hardening: lock down SECURITY DEFINER functions so they cannot be
-- invoked directly over the PostgREST RPC surface (/rest/v1/rpc/<fn>).
--
-- The trigger functions below (and handle_new_user) are only ever meant to run
-- from their triggers. A trigger executes with the privileges of the function
-- regardless of whether the *caller* holds EXECUTE, so revoking EXECUTE from
-- the exposed roles does NOT affect trigger firing -- it only removes the
-- ability for anon/authenticated clients to call them as ad-hoc RPCs. This
-- clears the Supabase database linter warnings
-- (0028_anon / 0029_authenticated security_definer_function_executable).
--
-- Run AFTER 0002_backend.sql. Idempotent: revoking an absent grant is a no-op.

revoke execute on function public.handle_new_user()        from anon, authenticated, public;
revoke execute on function public.handle_new_message()      from anon, authenticated, public;
revoke execute on function public.sync_post_like_count()    from anon, authenticated, public;
revoke execute on function public.sync_post_reply_count()   from anon, authenticated, public;
revoke execute on function public.sync_post_repost_count()  from anon, authenticated, public;
revoke execute on function public.sync_follow_counts()      from anon, authenticated, public;

-- is_conversation_participant() is different: it is referenced *inside* RLS
-- policies on conversations/messages, which are evaluated as the current
-- (authenticated) role. Authenticated therefore MUST retain EXECUTE for those
-- policies to work. It only needs to be unreachable by anonymous users and as
-- a public RPC, so scope it to authenticated explicitly.
revoke execute on function public.is_conversation_participant(uuid) from anon, public;
grant  execute on function public.is_conversation_participant(uuid) to authenticated;
