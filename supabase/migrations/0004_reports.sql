-- Oneleven reports migration (0004).
-- Run this in the Supabase SQL editor AFTER 0002_authz_and_core_tables.sql has
-- been applied (it references auth.users and follows the same RLS conventions
-- introduced there). Contains no service_role/secret keys; the app
-- authenticates with the public anon (publishable) key and relies on the
-- policies below.
--
-- What this migration adds:
--   * public.reports — client-authored abuse reports against a post, profile,
--     or comment. Reports are:
--       - INSERT-own only: an authenticated user may only file reports as
--         themselves (reporter = auth.uid());
--       - SELECT-own only: a reporter may read back their OWN submissions but
--         never anyone else's;
--       - append-only from the client: there is deliberately NO update/delete
--         policy for authenticated users. Moderation review/resolution is a
--         privileged, later-phase concern handled by service-role tooling, not
--         the RLS-limited client.
--
-- Mute model note: the client-side MUTE feature (hiding an author's posts
-- locally) is intentionally client-authoritative this phase and has NO server
-- table. Only blocks (public.blocks, added in 0002) and reports (below) are
-- server-backed. Blocks are enforced server-side via public.can_view_profile;
-- mute is a local product differentiator that never leaves the device.
--
-- Idempotency: this file is re-runnable. Every statement uses
-- `if not exists` / `drop policy if exists` before create, so applying it twice
-- does not error.
--
-- ENV RISK: live application of this migration is UNVERIFIED in this build (no
-- reachable/administerable Supabase project, no service-role key). It has been
-- validated by structural review only.

-- ---------------------------------------------------------------------------
-- Reports (client-authored abuse reports)
-- ---------------------------------------------------------------------------

create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter uuid references auth.users(id) on delete cascade,
  target_type text not null check (target_type in ('post', 'profile', 'comment')),
  target_id uuid not null,
  reason text not null check (char_length(reason) between 1 and 500),
  created_at timestamptz default now()
);

alter table public.reports enable row level security;

-- reports: a user may only create reports as themselves.
drop policy if exists "reports_insert_own" on public.reports;
create policy "reports_insert_own"
  on public.reports for insert to authenticated
  with check (auth.uid() = reporter);

-- reports: a reporter may read back their OWN submissions, but never anyone
-- else's. There is intentionally NO update/delete policy: reports are
-- append-only from the client and moderation review/resolution is deferred to
-- a later privileged (service-role) phase.
drop policy if exists "reports_select_own" on public.reports;
create policy "reports_select_own"
  on public.reports for select to authenticated
  using (auth.uid() = reporter);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

-- A reporter's own submissions, newest-first.
create index if not exists idx_reports_reporter_created
  on public.reports (reporter, created_at desc);
-- Lookups by report target (used by later moderation tooling).
create index if not exists idx_reports_target
  on public.reports (target_type, target_id);
