/**
 * Background work runs on Cloudflare Cron Triggers (CLAUDE.md 5). The Worker's
 * scheduled handler maps each cron expression to the jobs it should run, and
 * calls each job's route with the shared CRON_SECRET, one after another (a
 * later job can depend on an earlier one). Each job processes one small batch
 * per run.
 *
 * This is the full plan. A cron is only registered in wrangler.jsonc once at
 * least one of its jobs is implemented, so no Worker time is spent waking up
 * for nothing (a unit test enforces this).
 */
export const CRON_JOBS = {
  // Every minute: work a person is waiting for.
  "* * * * *": ["moderation-queue", "publish-layout"],
  // Every 5 minutes: batched AI work.
  "*/5 * * * *": ["claude-batches", "embeddings"],
  // Hourly: housekeeping.
  "17 * * * *": ["link-rechecks", "cold-storage"],
  // Nightly: encrypted backup (needs Workers Paid CPU time).
  "23 3 * * *": ["backup"],
} as const satisfies Record<string, readonly string[]>;

export type CronExpression = keyof typeof CRON_JOBS;
export type JobName = (typeof CRON_JOBS)[CronExpression][number];

export const JOB_NAMES: readonly JobName[] = Object.values(CRON_JOBS).flat();

/** Jobs with a real implementation. Add each one here in the phase that builds it. */
export const IMPLEMENTED_JOBS: ReadonlySet<JobName> = new Set<JobName>([]);

/** Implemented jobs to run for a cron expression, in order. */
export function jobsForCron(cron: string): readonly JobName[] {
  if (!Object.hasOwn(CRON_JOBS, cron)) return [];
  return CRON_JOBS[cron as CronExpression].filter((job) => IMPLEMENTED_JOBS.has(job));
}

export function isJobName(value: string): value is JobName {
  return (JOB_NAMES as readonly string[]).includes(value);
}

/** Header the scheduled handler sends to job routes. */
export const CRON_SECRET_HEADER = "x-pangaea-cron-secret";

/**
 * Constant-time string comparison for the cron secret. Only the length can
 * leak, which reveals nothing useful about a random secret.
 */
export function secretsMatch(given: string | null, expected: string | undefined): boolean {
  if (!given || !expected) return false;
  const a = new TextEncoder().encode(given);
  const b = new TextEncoder().encode(expected);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  return diff === 0;
}
