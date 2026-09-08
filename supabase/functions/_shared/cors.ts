// Shared CORS headers for the OTP Edge Functions. Both functions are invoked
// from the Flutter client via supabase.functions.invoke(...) during an
// unauthenticated sign-in, so they must be deployed with verify_jwt=false and
// answer the browser/SDK preflight OPTIONS request.
export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
