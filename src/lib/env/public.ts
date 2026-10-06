import { parseEnv, publicEnvSchema, type PublicEnv } from "./schema";

let cached: PublicEnv | undefined;

/** Env vars that are safe to ship to the browser. */
export function publicEnv(): PublicEnv {
  // Each NEXT_PUBLIC_ var must be referenced literally so Next can inline it
  // into the client bundle.
  cached ??= parseEnv(publicEnvSchema, {
    NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
    NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  });
  return cached;
}
