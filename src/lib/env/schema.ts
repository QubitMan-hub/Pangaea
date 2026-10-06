import { z } from "zod";

/**
 * Environment schemas. Kept free of Next/`server-only` imports so they can be
 * unit tested. Values come from `.env.local` (see `.env.example`).
 */

export const publicEnvSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.url(),
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: z.string().min(1),
  // Base URL of the public bucket as served by the CDN (tiles, thumbnails,
  // approved media). Optional until media lands in Phase 1.
  NEXT_PUBLIC_ASSET_BASE_URL: z.preprocess(
    (value) => (value === "" ? undefined : value),
    z.url().optional(),
  ),
});

export type PublicEnv = z.infer<typeof publicEnvSchema>;

/** Treats empty strings (as left by `KEY=` lines in .env files) as unset. */
const optionalSecret = z.preprocess(
  (value) => (value === "" ? undefined : value),
  z.string().min(1).optional(),
);

export const serverEnvSchema = publicEnvSchema.extend({
  // Bypasses RLS. Server only; used for moderation, placement and jobs.
  SUPABASE_SECRET_KEY: z.string().min(1),

  // AI services are optional until the phase that needs them; each service
  // module asserts its own key when called.
  ANTHROPIC_API_KEY: optionalSecret,
  // Haiku: summaries and region labels are short, frequent-ish and simple.
  ANTHROPIC_MODEL: z.string().min(1).default("claude-haiku-4-5"),
  VOYAGE_API_KEY: optionalSecret,
  VOYAGE_MODEL: z.string().min(1).default("voyage-4"),

  // S3-compatible object storage: Cloudflare R2 in production, Supabase
  // Storage's S3 endpoint locally. Optional until media lands in Phase 1.
  S3_ENDPOINT: z.preprocess((value) => (value === "" ? undefined : value), z.url().optional()),
  S3_REGION: z.string().min(1).default("auto"),
  S3_ACCESS_KEY_ID: optionalSecret,
  S3_SECRET_ACCESS_KEY: optionalSecret,
  S3_PRIVATE_BUCKET: z.string().min(1).default("private"),
  S3_PUBLIC_BUCKET: z.string().min(1).default("public"),

  // Protects scheduled job endpoints (tile rebakes, link rechecks).
  CRON_SECRET: optionalSecret,

  // Growth tuning (brief 5.2). Decay is computed on read from this.
  EARNED_SPACE_HALF_LIFE_DAYS: z.coerce.number().positive().default(30),
});

export type ServerEnv = z.infer<typeof serverEnvSchema>;

/** Formats a ZodError into one readable line per problem, without values. */
export function describeEnvError(error: z.ZodError): string {
  return error.issues
    .map((issue) => `  - ${issue.path.join(".") || "(root)"}: ${issue.message}`)
    .join("\n");
}

export function parseEnv<T extends z.ZodType>(
  schema: T,
  source: Record<string, string | undefined>,
): z.infer<T> {
  const result = schema.safeParse(source);
  if (!result.success) {
    throw new Error(
      `Invalid environment variables (see .env.example):\n${describeEnvError(result.error)}`,
    );
  }
  return result.data;
}
