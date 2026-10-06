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
const blankAsUnset = <T extends z.ZodType>(schema: T) =>
  z.preprocess((value) => (value === "" ? undefined : value), schema);

const optionalSecret = blankAsUnset(z.string().min(1).optional());

const positiveInt = (fallback: number) =>
  blankAsUnset(z.coerce.number().int().positive().default(fallback));

export const serverEnvSchema = publicEnvSchema.extend({
  // Bypasses RLS. Server only; used for moderation, placement and jobs.
  SUPABASE_SECRET_KEY: z.string().min(1),

  // AI and moderation services are optional until the phase that needs them;
  // each service module asserts its own key when called.
  ANTHROPIC_API_KEY: optionalSecret,
  // Region and continent names, borderline moderation and image checks.
  ANTHROPIC_MODEL: z.string().min(1).default("claude-haiku-4-5-20251001"),
  // Hard daily budget for all Claude calls. At the cap, work waits; it is never skipped.
  CLAUDE_DAILY_BUDGET_USD: blankAsUnset(z.coerce.number().nonnegative().default(1)),
  VOYAGE_API_KEY: optionalSecret,
  VOYAGE_MODEL: z.string().min(1).default("voyage-4-lite"),
  // Must match the halfvec(512) columns in the database.
  VOYAGE_DIMENSIONS: blankAsUnset(z.coerce.number().pipe(z.literal(512)).default(512)),
  // OpenAI Moderation API (free endpoint). Use a key from a project that can
  // only call moderation (CLAUDE.md section 12).
  OPENAI_API_KEY: optionalSecret,

  // S3-compatible object storage: Cloudflare R2 in production, Supabase
  // Storage's S3 endpoint locally. Optional until media lands in Phase 1.
  S3_ENDPOINT: blankAsUnset(z.url().optional()),
  S3_REGION: z.string().min(1).default("auto"),
  S3_ACCESS_KEY_ID: optionalSecret,
  S3_SECRET_ACCESS_KEY: optionalSecret,
  S3_PRIVATE_BUCKET: z.string().min(1).default("private"),
  S3_PUBLIC_BUCKET: z.string().min(1).default("public"),

  // Shared secret for job routes called by the Worker's own cron handler.
  CRON_SECRET: optionalSecret,

  // Nightly encrypted backups (Phase 5). The Worker only ever holds the
  // PUBLIC key (SPKI, base64); the private key stays offline with the owner.
  BACKUP_PUBLIC_KEY: optionalSecret,
  // Direct Postgres connection used only by the backup job.
  BACKUP_DATABASE_URL: optionalSecret,

  // Growth tuning. Decay is computed on read from this.
  EARNED_SPACE_HALF_LIFE_DAYS: blankAsUnset(z.coerce.number().positive().default(30)),

  // Cost guards (CLAUDE.md 7.5). Our limits are the spending cap for R2.
  PLOT_MAX_MEDIA_BYTES: positiveInt(10 * 1024 * 1024),
  PLOT_MAX_IMAGES: positiveInt(30),
  PLOT_MAX_DRAWING_ELEMENTS: positiveInt(2000),
  PLOT_MAX_SCENE_BYTES: positiveInt(1024 * 1024),
  USER_MAX_UPLOADS_PER_DAY: positiveInt(30),
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
