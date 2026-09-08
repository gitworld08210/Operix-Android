// send-otp: custom email OTP sender backed by Azure Communication Services (ACS).
//
// Flow:
//   1. Validate + normalize the email.
//   2. Rate limit: max 5 codes per email per 15 minutes.
//   3. Invalidate any prior unconsumed codes for that email.
//   4. Generate a uniform crypto-random 6-digit code.
//   5. Store base64(SHA-256(`${code}:${email}:${pepper}`)) with a 10-minute TTL.
//   6. Send the code via the ACS Email REST API using ACS HMAC-SHA256 signing.
//
// Deployed with verify_jwt=false (called by an unauthenticated user during
// sign-in). The AZURE_ACS_CONNECTION_STRING is a SECRET read ONLY from the
// environment here; it is never hardcoded, returned, or logged.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ACS_CONNECTION_STRING = Deno.env.get("AZURE_ACS_CONNECTION_STRING") ?? "";
// A dedicated pepper if provided, otherwise the service role key (server-only
// secret) so the stored hash is useless without server-side context.
const PEPPER = Deno.env.get("OTP_PEPPER") ?? SERVICE_ROLE_KEY;

// Verified ACS sender for this tenant.
const SENDER_ADDRESS =
  "DoNotReply@9492de8c-c56d-44f6-a797-24bc8fd6c182.azurecomm.net";
const ACS_API_VERSION = "2023-03-31";

const RATE_LIMIT_WINDOW_MIN = 15;
const RATE_LIMIT_MAX = 5;
const CODE_TTL_MIN = 10;

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

function base64ToBytes(b64: string): Uint8Array {
  const binary = atob(b64);
  const out = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) out[i] = binary.charCodeAt(i);
  return out;
}

async function sha256Base64(input: string | Uint8Array): Promise<string> {
  const data = typeof input === "string" ? new TextEncoder().encode(input) : input;
  const digest = await crypto.subtle.digest("SHA-256", data);
  return toBase64(new Uint8Array(digest));
}

async function hashCode(
  code: string,
  email: string,
  pepper: string,
): Promise<string> {
  return await sha256Base64(`${code}:${email}:${pepper}`);
}

// Uniform 6-digit code (000000-999999) via rejection sampling on a 32-bit draw
// to avoid modulo bias.
function generateCode(): string {
  const max = 1_000_000;
  const limit = Math.floor(0xffffffff / max) * max; // largest multiple of max <= 2^32
  const buf = new Uint32Array(1);
  let n: number;
  do {
    crypto.getRandomValues(buf);
    n = buf[0];
  } while (n >= limit);
  return (n % max).toString().padStart(6, "0");
}

// Parse an ACS connection string of form
// 'endpoint=https://...;accesskey=<base64>'. Keys are matched
// case-insensitively; the endpoint has any trailing slash stripped.
function parseConnectionString(
  cs: string,
): { endpoint: string; accessKey: string } {
  let endpoint = "";
  let accessKey = "";
  for (const part of cs.split(";")) {
    const idx = part.indexOf("=");
    if (idx === -1) continue;
    const key = part.slice(0, idx).trim().toLowerCase();
    const value = part.slice(idx + 1).trim();
    if (key === "endpoint") endpoint = value.replace(/\/+$/, "");
    else if (key === "accesskey") accessKey = value;
  }
  return { endpoint, accessKey };
}

// Send the OTP email via the ACS Email REST API with ACS HMAC-SHA256 signing.
// Returns true on a 2xx response. Never leaks ACS internals to the caller.
async function sendAcsEmail(code: string, email: string): Promise<boolean> {
  const { endpoint, accessKey } = parseConnectionString(ACS_CONNECTION_STRING);
  if (!endpoint || !accessKey) {
    console.error("ACS connection string missing endpoint/accesskey");
    return false;
  }

  const pathAndQuery = `/emails:send?api-version=${ACS_API_VERSION}`;
  const url = `${endpoint}${pathAndQuery}`;
  const host = new URL(endpoint).host;

  const payload = {
    senderAddress: SENDER_ADDRESS,
    content: {
      subject: "Your Oneleven code",
      plainText:
        `Your Oneleven verification code is ${code}. It expires in ${CODE_TTL_MIN} minutes. ` +
        `If you did not request this, you can ignore this email.`,
      html:
        `<div style="font-family:sans-serif;font-size:16px;color:#0f1419">` +
        `<p>Your Oneleven verification code is:</p>` +
        `<p style="font-size:32px;font-weight:700;letter-spacing:4px">${code}</p>` +
        `<p>It expires in ${CODE_TTL_MIN} minutes. If you did not request this, you can ignore this email.</p>` +
        `</div>`,
    },
    recipients: { to: [{ address: email }] },
  };

  // The signed content hash must be computed over the EXACT bytes sent.
  const bodyString = JSON.stringify(payload);
  const bodyBytes = new TextEncoder().encode(bodyString);
  const contentHash = await sha256Base64(bodyBytes);
  const xMsDate = new Date().toUTCString();

  // string-to-sign order: VERB \n path+query \n x-ms-date;host;x-ms-content-sha256
  const stringToSign =
    `POST\n${pathAndQuery}\n${xMsDate};${host};${contentHash}`;

  // HMAC key = raw bytes of the base64-decoded access key.
  const key = await crypto.subtle.importKey(
    "raw",
    base64ToBytes(accessKey),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sigBuf = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(stringToSign),
  );
  const signature = toBase64(new Uint8Array(sigBuf));

  // SignedHeaders list order MUST match the concatenation order above.
  const authorization =
    `HMAC-SHA256 SignedHeaders=x-ms-date;host;x-ms-content-sha256&Signature=${signature}`;

  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-ms-date": xMsDate,
      "x-ms-content-sha256": contentHash,
      "Authorization": authorization,
    },
    body: bodyString,
  });

  if (res.status < 200 || res.status >= 300) {
    const text = await res.text().catch(() => "<no body>");
    console.error(`ACS emails:send failed: ${res.status} ${text}`);
    return false;
  }
  return true;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  let email: string;
  try {
    const body = await req.json();
    email = String(body?.email ?? "").trim().toLowerCase();
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  // Basic email validation.
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return json({ error: "invalid_email" }, 400);
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Rate limit: no more than RATE_LIMIT_MAX codes per email per window.
  const windowStart = new Date(
    Date.now() - RATE_LIMIT_WINDOW_MIN * 60_000,
  ).toISOString();
  const { count, error: countErr } = await supabase
    .from("otp_codes")
    .select("id", { count: "exact", head: true })
    .eq("email", email)
    .gt("created_at", windowStart);
  if (countErr) {
    console.error("rate-limit count error", countErr.message);
    return json({ error: "server_error" }, 500);
  }
  if ((count ?? 0) >= RATE_LIMIT_MAX) {
    return json(
      { error: "rate_limited", message: "Too many code requests. Please try again in a few minutes." },
      429,
    );
  }

  // Invalidate prior unconsumed codes for this email so only the newest is live.
  const { error: purgeErr } = await supabase
    .from("otp_codes")
    .update({ consumed: true })
    .eq("email", email)
    .eq("consumed", false);
  if (purgeErr) {
    console.error("invalidate prior codes error", purgeErr.message);
    return json({ error: "server_error" }, 500);
  }

  const code = generateCode();
  const codeHash = await hashCode(code, email, PEPPER);
  const expiresAt = new Date(Date.now() + CODE_TTL_MIN * 60_000).toISOString();

  const { error: insertErr } = await supabase
    .from("otp_codes")
    .insert({ email, code_hash: codeHash, expires_at: expiresAt });
  if (insertErr) {
    console.error("insert otp error", insertErr.message);
    return json({ error: "server_error" }, 500);
  }

  const sent = await sendAcsEmail(code, email);
  if (!sent) {
    return json({ error: "send_failed", message: "Could not send the code. Please try again." }, 502);
  }

  return json({ ok: true });
});
