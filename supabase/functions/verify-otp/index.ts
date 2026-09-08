// verify-otp: validates an emailed OTP and bootstraps a Supabase auth session.
//
// Flow:
//   1. Validate + normalize { email, code } (code must be 6 digits).
//   2. Select the newest unconsumed, unexpired otp_codes row for the email.
//   3. Lock out after 5 failed attempts on that row.
//   4. Recompute the hash the SAME way as send-otp and compare in
//      constant-time; on mismatch bump attempts, on match mark consumed.
//   5. Find-or-create the auth user (email_confirm:true so the profiles trigger
//      fires and no Supabase email confirmation is needed), then mint a
//      magiclink and return its hashed_token as `token_hash`.
//
// CLIENT SESSION CONTRACT (must match the Flutter app feature):
//   The Flutter client finalizes the session with
//       supabase.auth.verifyOTP(type: OtpType.magiclink, tokenHash: token_hash)
//   after which supabase.auth.currentSession != null. The 'magiclink' verify
//   type pairs with generateLink({ type: 'magiclink' }) used below.
//
// Deployed with verify_jwt=false (called by an unauthenticated user during
// sign-in). Uses the service_role key for the Admin API.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// Must match send-otp's pepper choice exactly so the hashes line up.
const PEPPER = Deno.env.get("OTP_PEPPER") ?? SERVICE_ROLE_KEY;

const MAX_ATTEMPTS = 5;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

async function hashCode(
  code: string,
  email: string,
  pepper: string,
): Promise<string> {
  const data = new TextEncoder().encode(`${code}:${email}:${pepper}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return toBase64(new Uint8Array(digest));
}

// Length-safe constant-time string comparison.
function timingSafeEqual(a: string, b: string): boolean {
  const aBytes = new TextEncoder().encode(a);
  const bBytes = new TextEncoder().encode(b);
  if (aBytes.length !== bBytes.length) return false;
  let diff = 0;
  for (let i = 0; i < aBytes.length; i++) diff |= aBytes[i] ^ bBytes[i];
  return diff === 0;
}

// Find an existing auth user by email, paging through listUsers. Returns the
// user id or null. (supabase-js v2 has no direct get-by-email admin method.)
async function findUserByEmail(
  // deno-lint-ignore no-explicit-any
  admin: any,
  email: string,
): Promise<string | null> {
  const perPage = 200;
  for (let page = 1; page <= 50; page++) {
    const { data, error } = await admin.listUsers({ page, perPage });
    if (error) throw error;
    const users = data?.users ?? [];
    const match = users.find(
      // deno-lint-ignore no-explicit-any
      (u: any) => (u.email ?? "").toLowerCase() === email,
    );
    if (match) return match.id;
    if (users.length < perPage) break;
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  let email: string;
  let code: string;
  try {
    const body = await req.json();
    email = String(body?.email ?? "").trim().toLowerCase();
    code = String(body?.code ?? "").trim();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return json({ error: "invalid_email" }, 400);
  }
  if (!/^\d{6}$/.test(code)) {
    return json({ error: "invalid_code" }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Newest live code for this email.
  const nowIso = new Date().toISOString();
  const { data: rows, error: selErr } = await supabase
    .from("otp_codes")
    .select("id, code_hash, attempts")
    .eq("email", email)
    .eq("consumed", false)
    .gt("expires_at", nowIso)
    .order("created_at", { ascending: false })
    .limit(1);
  if (selErr) {
    console.error("select otp error", selErr.message);
    return json({ error: "server_error" }, 500);
  }
  const row = rows?.[0];
  if (!row) {
    return json({ error: "invalid_or_expired" }, 400);
  }

  if ((row.attempts ?? 0) >= MAX_ATTEMPTS) {
    return json({ error: "too_many_attempts" }, 429);
  }

  const expected = await hashCode(code, email, PEPPER);
  if (!timingSafeEqual(expected, row.code_hash)) {
    await supabase
      .from("otp_codes")
      .update({ attempts: (row.attempts ?? 0) + 1 })
      .eq("id", row.id);
    return json({ error: "invalid_code" }, 400);
  }

  // Correct code: consume it so it cannot be replayed.
  const { error: consumeErr } = await supabase
    .from("otp_codes")
    .update({ consumed: true })
    .eq("id", row.id);
  if (consumeErr) {
    console.error("consume otp error", consumeErr.message);
    return json({ error: "server_error" }, 500);
  }

  // Find-or-create the auth user with email_confirm:true so the profiles
  // trigger fires and Supabase does not require a separate confirmation.
  const admin = supabase.auth.admin;
  try {
    let userId = await findUserByEmail(admin, email);
    if (!userId) {
      const { data: created, error: createErr } = await admin.createUser({
        email,
        email_confirm: true,
      });
      if (createErr) {
        // Handle the race where the user was created concurrently.
        userId = await findUserByEmail(admin, email);
        if (!userId) {
          console.error("createUser error", createErr.message);
          return json({ error: "server_error" }, 500);
        }
      } else {
        userId = created?.user?.id ?? null;
      }
    }

    // Mint a magiclink and hand its hashed_token to the client. The client
    // finalizes with verifyOTP(type: OtpType.magiclink, tokenHash: token_hash).
    const { data: linkData, error: linkErr } = await admin.generateLink({
      type: "magiclink",
      email,
    });
    if (linkErr || !linkData?.properties?.hashed_token) {
      console.error("generateLink error", linkErr?.message ?? "no hashed_token");
      return json({ error: "server_error" }, 500);
    }

    return json({ token_hash: linkData.properties.hashed_token, email });
  } catch (e) {
    console.error("session bootstrap error", (e as Error).message);
    return json({ error: "server_error" }, 500);
  }
});
