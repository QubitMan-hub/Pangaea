import { z } from "zod";

/**
 * Environment schemas. Kept free of Next/`server-only` imports so they can be
 * unit tested. Values come from `.env.local` (see `.env.example`).
 */

export const publicEnvSchema = z.object({
  NEXT_PUBLIC_SUPABASE_URL: z.url(),
  NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY: z.string().min(1),
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
  ANTHROPIC_MODEL: z.string().min(1).default("claude-sonnet-5-5"),
  VOYAGE_API_KEY: optionalSecret,
  VOYAGE_MODEL: z.string().min(1).default("voyage-4"),

  // Protects scheduled job endpoints (growth/decay, link rechecks).
  CRON_SECRET: optionalSecret,

  // Growth tuning (brief 5.2).
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
