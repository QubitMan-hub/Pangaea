import "server-only";

import { createClient } from "@supabase/supabase-js";

import { serverEnv } from "@/lib/env/server";

import type { Database } from "./database.types";

/**
 * Service-role client. BYPASSES ROW LEVEL SECURITY.
 *
 * Only for trusted server code: moderation decisions, placement, growth jobs
 * and the admin page. Never pass user-controlled filters into it unchecked,
 * and never import it from a Client Component (`server-only` enforces that).
 */
export function createSupabaseAdminClient() {
  const env = serverEnv();
  return createClient<Database>(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SECRET_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
