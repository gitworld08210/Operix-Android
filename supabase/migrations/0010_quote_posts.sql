-- Oneleven quote-posts migration (0010).
-- Run this in the Supabase SQL editor AFTER 0001-0009 have been applied.
-- Contains no service_role/secret keys; the app authenticates with the public
-- anon (publishable) key and relies on the existing policies.
--
-- PURPOSE
--   Adds QUOTE-POSTS: a post may embed/reference another post. This is modeled
--   as a nullable self-referencing FK on public.posts. Existing posts have a
--   null reference and behave exactly as before, so this change is fully
--   backward compatible.
--
-- WHAT THIS MIGRATION ADDS
--   * posts.quoted_post_id : nullable uuid FK -> public.posts(id).
--   * a self-quote CHECK constraint (a post may not quote itself).
--   * an index on quoted_post_id for reverse lookups (who quoted post X).
--
-- ON DELETE SET NULL RATIONALE
--   The FK uses `on delete set null` so that deleting a quoted post degrades the
--   quoting post to a normal (non-quote) post rather than cascading a delete of
--   the quoting post. Losing the quoted target must never destroy the author's
--   own commentary.
--
-- SELF-QUOTE CHECK
--   `posts_no_self_quote` forbids `quoted_post_id = id`. There is no
--   `add constraint if not exists`, so the constraint is added inside a guarded
--   DO block (mirroring the `follows_status_check` pattern in 0002) so this file
--   stays re-runnable.
--
-- NO NEW RLS IS REQUIRED
--   The existing `posts_select_viewable` policy (see 0002) already gates every
--   posts row by `can_view_profile(auth.uid(), owner)`. A joined quoted post is
--   fetched as its OWN posts row subject to the SAME policy, so a viewer who
--   cannot see the quoted post's author simply gets null for the embed. No
--   additional policy is added or needed.
--
-- ENV RISK (UNVERIFIED)
--   Live application of this migration is UNVERIFIED here: there is no
--   reachable/administerable Supabase project and no service-role key in this
--   environment, so this SQL has been validated by STRUCTURAL REVIEW ONLY. In
--   particular the RLS inheritance on the self-join, the self-FK
--   on-delete-set-null behavior, and the aliased self-embed PostgREST join
--   shape (`quoted:quoted_post_id(...)`) are the largest known risks and must be
--   confirmed against a live project before relying on them in production.
--
-- IDEMPOTENCY
--   Re-runnable: `add column if not exists`, a guarded DO block for the CHECK,
--   and `create index if not exists`.

-- ---------------------------------------------------------------------------
-- Quote reference column (nullable self-FK, ON DELETE SET NULL)
-- ---------------------------------------------------------------------------

alter table public.posts
  add column if not exists quoted_post_id uuid
    references public.posts(id) on delete set null;

-- ---------------------------------------------------------------------------
-- Self-quote CHECK (guarded; no `add constraint if not exists` exists)
-- ---------------------------------------------------------------------------

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'posts_no_self_quote'
  ) then
    alter table public.posts
      add constraint posts_no_self_quote
      check (quoted_post_id is null or quoted_post_id <> id);
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Index for reverse lookups (who quoted post X)
-- ---------------------------------------------------------------------------

create index if not exists idx_posts_quoted_post_id
  on public.posts (quoted_post_id);
