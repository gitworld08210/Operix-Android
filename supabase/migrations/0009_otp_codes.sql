-- Custom email OTP storage for the Azure Communication Services (ACS) sign-in
-- flow. The two Supabase Edge Functions (`send-otp` / `verify-otp`) own all
-- access to this table using the service_role key; the app never touches it
-- directly.
--
-- Design notes:
--   * RLS is enabled with NO policies. That means anon/authenticated JWTs can
--     read/write NOTHING here - only the service_role key (which bypasses RLS)
--     used inside the Edge Functions can access rows. This keeps hashed codes,
--     attempt counts and email addresses fully server-side.
--   * `code_hash` is never the raw code: send-otp stores base64(SHA-256(
--     `${code}:${email}:${pepper}`)) so a table leak does not reveal codes.
--   * `purge_expired_otp_codes()` is a SECURITY DEFINER helper (fixed
--     search_path, fully-qualified names, execute revoked from callers) that a
--     scheduled job can call to sweep old rows.
--
-- This migration is an idempotent re-declaration of the schema that is ALREADY
-- applied to the live database (migration otp_codes_table / 20260908082728).
-- Its only purpose is to keep the repo in sync with the live DB; it is safe to
-- run more than once and produces no changes against the applied schema.

create table if not exists public.otp_codes (
  id         uuid primary key default gen_random_uuid(),
  email      text not null,
  code_hash  text not null,
  expires_at timestamptz not null,
  consumed   boolean not null default false,
  attempts   int not null default 0,
  created_at timestamptz default now()
);

-- Lookup index for the newest code per email (send-otp rate limit + verify-otp
-- newest-row select both order by created_at desc for a given email).
create index if not exists otp_codes_email_created_at_idx
  on public.otp_codes (email, created_at desc);

-- Supports the expiry sweep in purge_expired_otp_codes().
create index if not exists otp_codes_expires_at_idx
  on public.otp_codes (expires_at);

-- Enable RLS with no policies: only the service_role key (bypasses RLS) reaches
-- this table. Any anon/authenticated access is denied by default.
alter table public.otp_codes enable row level security;

-- Housekeeping helper: delete consumed or expired codes. SECURITY DEFINER with a
-- fixed empty search_path and fully-qualified names so it cannot be hijacked via
-- a mutable search_path. Execute is revoked from callers so it is only reachable
-- by the owner / a scheduled job running as the definer.
create or replace function public.purge_expired_otp_codes()
returns void
language sql
security definer
set search_path = ''
as $$
  delete from public.otp_codes
  where public.otp_codes.expires_at < now()
     or public.otp_codes.consumed = true;
$$;

revoke all on function public.purge_expired_otp_codes() from anon, authenticated, public;
