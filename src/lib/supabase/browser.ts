import { createBrowserClient } from "@supabase/ssr";

import { publicEnv } from "@/lib/env/public";

import type { Database } from "./database.types";

/** Supabase client for Client Components. Acts as the signed-in user (RLS applies). */
export function createSupabaseBrowserClient() {
  const env = publicEnv();
  return createBrowserClient<Database>(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  );
}
